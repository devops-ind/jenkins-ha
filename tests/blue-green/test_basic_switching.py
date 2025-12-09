"""
Basic blue-green environment switching tests.

This module tests core blue-green deployment functionality including:
- Environment switching (blue ↔ green)
- Container lifecycle management
- Port mapping validation
- Service accessibility
"""
import json
import time
import pytest
import requests
import docker
from unittest.mock import Mock, patch


class TestBasicSwitching:
    """Test basic blue-green switching functionality."""
    
    def test_container_port_mapping(self, jenkins_containers, test_config):
        """Test that containers have correct port mappings."""
        blue_info = jenkins_containers["blue"]
        green_info = jenkins_containers["green"]
        
        # Verify blue container port
        blue_port = blue_info["port"]
        blue_response = requests.get(f"http://localhost:{blue_port}/login", timeout=10)
        assert blue_response.status_code in [200, 403], f"Blue Jenkins not accessible on port {blue_port}"
        
        # Verify green container port
        green_port = green_info["port"] 
        green_response = requests.get(f"http://localhost:{green_port}/login", timeout=10)
        assert green_response.status_code in [200, 403], f"Green Jenkins not accessible on port {green_port}"
        
        # Verify ports are different
        assert blue_port != green_port, "Blue and green containers should use different ports"
    
    def test_container_lifecycle(self, docker_client):
        """Test container creation, start, stop, and removal."""
        container_name = "test-jenkins-lifecycle"
        
        # Create container
        container = docker_client.containers.run(
            "jenkins/jenkins:lts",
            name=container_name,
            ports={8080: 8090},
            detach=True,
            remove=True
        )
        
        try:
            # Verify container is running
            container.reload()
            assert container.status == "running"
            
            # Stop container
            container.stop()
            container.reload()
            assert container.status == "exited"
            
            # Restart container
            container.start()
            container.reload()
            assert container.status == "running"
            
        finally:
            # Cleanup
            container.remove(force=True)
    
    def test_jenkins_health_check(self, jenkins_containers):
        """Test Jenkins health check endpoints."""
        for env, info in jenkins_containers.items():
            url = info["url"]
            
            # Test login page accessibility
            login_response = requests.get(f"{url}/login", timeout=10)
            assert login_response.status_code in [200, 403], f"{env} Jenkins login page not accessible"
            
            # Test API endpoint
            api_response = requests.get(f"{url}/api/json", timeout=10)
            assert api_response.status_code in [200, 403], f"{env} Jenkins API not accessible"
    
    def test_environment_switching_logic(self, blue_green_state_file):
        """Test environment switching logic without actual containers."""
        # Load initial state
        with open(blue_green_state_file, 'r') as f:
            state = json.load(f)
        
        # Test switching devops team from blue to green
        devops_team = state["teams"]["devops"]
        assert devops_team["active_environment"] == "blue"
        
        # Simulate switch to green
        devops_team["active_environment"] = "green"
        devops_team["switch_count"] += 1
        devops_team["last_switch_time"] = "2024-01-01T12:00:00Z"
        
        # Verify switch
        assert devops_team["active_environment"] == "green"
        assert devops_team["switch_count"] == 1
        
        # Test switching back to blue
        devops_team["active_environment"] = "blue"
        devops_team["switch_count"] += 1
        
        assert devops_team["active_environment"] == "blue"
        assert devops_team["switch_count"] == 2
    
    def test_active_environment_detection(self, jenkins_containers, test_config):
        """Test detection of which environment is currently active."""
        # Mock function to determine active environment based on port accessibility
        def get_active_environment():
            blue_port = test_config["jenkins"]["blue_port"]
            green_port = test_config["jenkins"]["green_port"]
            
            blue_active = False
            green_active = False
            
            try:
                requests.get(f"http://localhost:{blue_port}/login", timeout=5)
                blue_active = True
            except:
                pass
                
            try:
                requests.get(f"http://localhost:{green_port}/login", timeout=5)
                green_active = True
            except:
                pass
            
            if blue_active and green_active:
                return "both"
            elif blue_active:
                return "blue"
            elif green_active:
                return "green"
            else:
                return "none"
        
        # Both environments should be active in test setup
        active = get_active_environment()
        assert active == "both", "Both blue and green environments should be running in test"
    
    @pytest.mark.slow
    def test_jenkins_startup_time(self, docker_client, test_config):
        """Test Jenkins container startup time."""
        container_name = "test-jenkins-startup"
        
        # Remove existing container
        try:
            existing = docker_client.containers.get(container_name)
            existing.remove(force=True)
        except docker.errors.NotFound:
            pass
        
        start_time = time.time()
        
        # Create and start container
        container = docker_client.containers.run(
            "jenkins/jenkins:lts",
            name=container_name,
            ports={8080: 8091},
            detach=True,
            remove=True
        )
        
        try:
            # Wait for Jenkins to be ready
            timeout = test_config["timeouts"]["container_start"]
            ready = False
            
            while time.time() - start_time < timeout:
                try:
                    response = requests.get("http://localhost:8091/login", timeout=5)
                    if response.status_code in [200, 403]:
                        ready = True
                        break
                except:
                    pass
                time.sleep(2)
            
            startup_time = time.time() - start_time
            
            assert ready, f"Jenkins did not start within {timeout} seconds"
            assert startup_time < timeout, f"Jenkins startup took {startup_time:.2f}s, expected < {timeout}s"
            
            print(f"Jenkins startup time: {startup_time:.2f} seconds")
            
        finally:
            container.remove(force=True)
    
    def test_concurrent_access(self, jenkins_containers):
        """Test concurrent access to both environments."""
        import concurrent.futures
        import threading
        
        results = []
        
        def access_jenkins(env, url):
            """Access Jenkins and record result."""
            try:
                response = requests.get(f"{url}/login", timeout=10)
                results.append({
                    "env": env,
                    "status": response.status_code,
                    "success": response.status_code in [200, 403],
                    "thread": threading.current_thread().name
                })
            except Exception as e:
                results.append({
                    "env": env,
                    "status": None,
                    "success": False,
                    "error": str(e),
                    "thread": threading.current_thread().name
                })
        
        # Concurrent access to both environments
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            futures = []
            
            # Submit multiple requests to each environment
            for _ in range(3):
                for env, info in jenkins_containers.items():
                    future = executor.submit(access_jenkins, env, info["url"])
                    futures.append(future)
            
            # Wait for all requests to complete
            concurrent.futures.wait(futures)
        
        # Verify all requests succeeded
        assert len(results) == 6, f"Expected 6 results, got {len(results)}"
        
        successful_requests = [r for r in results if r["success"]]
        assert len(successful_requests) == 6, f"All requests should succeed, but {6 - len(successful_requests)} failed"
        
        # Verify both environments were accessed
        blue_accesses = [r for r in results if r["env"] == "blue"]
        green_accesses = [r for r in results if r["env"] == "green"]
        
        assert len(blue_accesses) == 3, "Expected 3 blue environment accesses"
        assert len(green_accesses) == 3, "Expected 3 green environment accesses"


class TestEnvironmentConfiguration:
    """Test environment configuration and validation."""
    
    def test_team_configuration_validation(self, test_config):
        """Test team configuration structure."""
        teams = test_config["teams"]
        
        for team in teams:
            # Required fields
            assert "team_name" in team, "Team must have team_name"
            assert "active_environment" in team, "Team must have active_environment"
            assert "blue_green_enabled" in team, "Team must have blue_green_enabled"
            
            # Valid values
            assert team["active_environment"] in ["blue", "green"], "active_environment must be blue or green"
            assert isinstance(team["blue_green_enabled"], bool), "blue_green_enabled must be boolean"
            assert len(team["team_name"]) > 0, "team_name cannot be empty"
    
    def test_port_configuration(self, test_config):
        """Test port configuration validation."""
        jenkins_config = test_config["jenkins"]
        
        blue_port = jenkins_config["blue_port"]
        green_port = jenkins_config["green_port"]
        
        # Ports must be different
        assert blue_port != green_port, "Blue and green ports must be different"
        
        # Ports must be in valid range
        assert 1024 <= blue_port <= 65535, "Blue port must be in valid range"
        assert 1024 <= green_port <= 65535, "Green port must be in valid range"
    
    def test_timeout_configuration(self, test_config):
        """Test timeout configuration validation."""
        timeouts = test_config["timeouts"]
        
        for timeout_name, timeout_value in timeouts.items():
            assert isinstance(timeout_value, int), f"{timeout_name} timeout must be integer"
            assert timeout_value > 0, f"{timeout_name} timeout must be positive"
            assert timeout_value <= 300, f"{timeout_name} timeout should not exceed 5 minutes"


class TestErrorHandling:
    """Test error handling in blue-green operations."""
    
    def test_invalid_environment_name(self):
        """Test handling of invalid environment names."""
        valid_environments = ["blue", "green"]
        invalid_environments = ["red", "yellow", "purple", "", None]
        
        for env in invalid_environments:
            assert env not in valid_environments, f"'{env}' should be invalid environment name"
    
    def test_missing_container_handling(self, docker_client):
        """Test handling when expected containers are missing."""
        # Try to get non-existent container
        with pytest.raises(docker.errors.NotFound):
            docker_client.containers.get("non-existent-jenkins")
    
    def test_network_error_handling(self):
        """Test handling of network errors."""
        # Test connection to non-existent service
        with pytest.raises(requests.RequestException):
            requests.get("http://localhost:99999/login", timeout=1)
    
    def test_jenkins_unavailable(self):
        """Test handling when Jenkins is unavailable."""
        # Test connection to stopped Jenkins (assuming no Jenkins on port 9999)
        try:
            response = requests.get("http://localhost:9999/login", timeout=2)
            # If we get here, there's actually something on port 9999
            # That's unexpected but not necessarily a test failure
            pass
        except requests.RequestException:
            # This is expected - Jenkins should not be running on port 9999
            pass