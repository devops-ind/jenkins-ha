"""
Pytest configuration and fixtures for blue-green deployment testing.
"""
import json
import os
import tempfile
import time
from pathlib import Path
from typing import Dict, List, Any

import pytest
import yaml
import docker
import requests
from testcontainers.jenkins import JenkinsContainer


@pytest.fixture(scope="session")
def project_root():
    """Return the project root directory."""
    return Path(__file__).parent.parent.parent


@pytest.fixture(scope="session") 
def test_config():
    """Load test configuration."""
    return {
        "jenkins": {
            "admin_user": "admin",
            "admin_password": "admin123",
            "blue_port": 8081,
            "green_port": 8082,
            "startup_timeout": 120
        },
        "haproxy": {
            "stats_port": 8404,
            "frontend_port": 8080
        },
        "teams": [
            {
                "team_name": "devops",
                "active_environment": "blue",
                "blue_green_enabled": True
            },
            {
                "team_name": "qa", 
                "active_environment": "green",
                "blue_green_enabled": True
            }
        ],
        "timeouts": {
            "container_start": 60,
            "health_check": 30,
            "switch_operation": 120
        }
    }


@pytest.fixture(scope="session")
def docker_client():
    """Docker client for container operations."""
    return docker.from_env()


@pytest.fixture(scope="function")
def mock_inventory(tmp_path, test_config):
    """Create a mock Ansible inventory for testing."""
    inventory_content = {
        "all": {
            "vars": {
                "jenkins_domain": "test.local",
                "jenkins_teams": test_config["teams"],
                "ssl_enabled": False,
                "deployment_environment": "test"
            }
        },
        "jenkins_masters": {
            "hosts": {
                "test-host": {
                    "ansible_host": "localhost",
                    "ansible_connection": "local"
                }
            }
        },
        "load_balancers": {
            "hosts": {
                "test-lb": {
                    "ansible_host": "localhost", 
                    "ansible_connection": "local"
                }
            }
        }
    }
    
    inventory_file = tmp_path / "test_inventory.yml"
    with open(inventory_file, 'w') as f:
        yaml.dump(inventory_content, f)
    
    return str(inventory_file)


@pytest.fixture(scope="function")
def jenkins_containers(docker_client, test_config):
    """Create Jenkins containers for blue-green testing."""
    containers = {}
    
    for env in ["blue", "green"]:
        port = test_config["jenkins"][f"{env}_port"]
        container_name = f"jenkins-test-{env}"
        
        # Remove existing container if it exists
        try:
            existing = docker_client.containers.get(container_name)
            existing.remove(force=True)
        except docker.errors.NotFound:
            pass
            
        # Create new container
        container = docker_client.containers.run(
            "jenkins/jenkins:lts",
            name=container_name,
            ports={8080: port},
            environment={
                "JENKINS_ADMIN_ID": test_config["jenkins"]["admin_user"],
                "JENKINS_ADMIN_PASSWORD": test_config["jenkins"]["admin_password"]
            },
            detach=True,
            remove=True
        )
        
        containers[env] = {
            "container": container,
            "port": port,
            "url": f"http://localhost:{port}"
        }
    
    # Wait for containers to be ready
    for env, info in containers.items():
        _wait_for_jenkins_ready(info["url"], test_config["jenkins"]["startup_timeout"])
    
    yield containers
    
    # Cleanup
    for env, info in containers.items():
        try:
            info["container"].remove(force=True)
        except Exception:
            pass


@pytest.fixture(scope="function") 
def haproxy_container(docker_client, test_config, tmp_path):
    """Create HAProxy container for routing tests."""
    # Generate HAProxy config
    config_content = f"""
global
    daemon
    
defaults
    mode http
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

frontend jenkins_frontend
    bind *:80
    default_backend jenkins_backend
    
backend jenkins_backend
    balance roundrobin
    option httpchk GET /login
    server jenkins-blue localhost:{test_config["jenkins"]["blue_port"]} check
    server jenkins-green localhost:{test_config["jenkins"]["green_port"]} check backup

listen stats
    bind *:8404
    stats enable
    stats uri /stats
"""
    
    config_file = tmp_path / "haproxy.cfg"
    with open(config_file, 'w') as f:
        f.write(config_content)
    
    container_name = "haproxy-test"
    
    # Remove existing container
    try:
        existing = docker_client.containers.get(container_name)
        existing.remove(force=True)
    except docker.errors.NotFound:
        pass
    
    # Create HAProxy container
    container = docker_client.containers.run(
        "haproxy:alpine",
        name=container_name,
        ports={
            80: test_config["haproxy"]["frontend_port"],
            8404: test_config["haproxy"]["stats_port"]
        },
        volumes={str(config_file): {"bind": "/usr/local/etc/haproxy/haproxy.cfg", "mode": "ro"}},
        detach=True,
        remove=True
    )
    
    # Wait for HAProxy to be ready
    time.sleep(5)
    
    yield {
        "container": container,
        "stats_url": f"http://localhost:{test_config['haproxy']['stats_port']}/stats",
        "frontend_url": f"http://localhost:{test_config['haproxy']['frontend_port']}"
    }
    
    # Cleanup
    try:
        container.remove(force=True)
    except Exception:
        pass


@pytest.fixture(scope="function")
def mock_jenkins_api():
    """Mock Jenkins API responses for testing."""
    return {
        "healthy": {
            "status": 200,
            "json": {
                "mode": "NORMAL",
                "nodeDescription": "Jenkins Test Instance",
                "numExecutors": 2,
                "jobs": []
            }
        },
        "with_builds": {
            "status": 200, 
            "json": {
                "jobs": [
                    {
                        "name": "test-job",
                        "builds": [
                            {"building": True, "number": 1},
                            {"building": False, "number": 2}
                        ]
                    }
                ]
            }
        },
        "unhealthy": {
            "status": 503,
            "json": {"message": "Jenkins is starting up"}
        }
    }


def _wait_for_jenkins_ready(url: str, timeout: int) -> bool:
    """Wait for Jenkins to be ready."""
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        try:
            response = requests.get(f"{url}/login", timeout=5)
            if response.status_code in [200, 403]:  # 403 is OK for login page
                return True
        except requests.RequestException:
            pass
        
        time.sleep(2)
    
    raise TimeoutError(f"Jenkins at {url} did not become ready within {timeout} seconds")


@pytest.fixture(scope="function")
def blue_green_state_file(tmp_path):
    """Create a temporary blue-green state file."""
    state_file = tmp_path / "blue_green_state.json"
    initial_state = {
        "teams": {
            "devops": {
                "active_environment": "blue",
                "last_switch_time": "2024-01-01T00:00:00Z",
                "switch_count": 0
            },
            "qa": {
                "active_environment": "green", 
                "last_switch_time": "2024-01-01T00:00:00Z",
                "switch_count": 0
            }
        }
    }
    
    with open(state_file, 'w') as f:
        json.dump(initial_state, f)
    
    return str(state_file)


@pytest.fixture(scope="function")
def circuit_breaker_state(tmp_path):
    """Create a circuit breaker state file.""" 
    cb_file = tmp_path / "circuit_breaker.json"
    initial_state = {
        "state": "closed",
        "failure_count": 0,
        "last_failure_time": None,
        "cooldown_until": 0
    }
    
    with open(cb_file, 'w') as f:
        json.dump(initial_state, f)
        
    return str(cb_file)


# Pytest configuration
def pytest_configure(config):
    """Configure pytest with custom markers."""
    config.addinivalue_line(
        "markers", "slow: marks tests as slow (deselect with '-m \"not slow\"')"
    )
    config.addinivalue_line(
        "markers", "integration: marks tests as integration tests"
    )
    config.addinivalue_line(
        "markers", "ansible: marks tests that require Ansible"
    )


def pytest_collection_modifyitems(config, items):
    """Add markers to tests based on their location."""
    for item in items:
        if "integration" in str(item.fspath):
            item.add_marker(pytest.mark.integration)
        if "ansible" in str(item.fspath):
            item.add_marker(pytest.mark.ansible)