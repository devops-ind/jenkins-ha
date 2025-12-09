# Blue-Green Deployment Test Suite

This directory contains comprehensive tests for the Jenkins HA blue-green deployment functionality.

## Test Structure

```
tests/blue-green/
├── README.md                          # This file
├── conftest.py                        # Pytest configuration and fixtures
├── requirements.txt                   # Python test dependencies
├── test_basic_switching.py            # Basic blue-green switching tests
├── test_multi_team.py                 # Multi-team independent switching tests
├── test_failure_scenarios.py          # Failure handling and rollback tests
├── test_haproxy_routing.py            # HAProxy routing validation tests
├── test_ssl_certificates.py           # SSL certificate handling tests
├── ansible/                           # Ansible test playbooks
│   ├── test_blue_green_deployment.yml # Consolidated deployment test
│   ├── test_environment_switching.yml # Environment switching test
│   └── test_rollback_scenarios.yml    # Rollback testing
└── fixtures/                          # Test data and configurations
    ├── test_inventory.yml             # Test inventory configurations
    └── mock_responses.json            # Mock API responses for testing
```

## Running Tests

### Prerequisites
```bash
# Install Python dependencies
pip install -r requirements.txt

# Install Ansible collections
ansible-galaxy collection install -r ../../collections/requirements.yml
```

### Run All Tests
```bash
# Run all blue-green tests
pytest tests/blue-green/ -v

# Run specific test categories
pytest tests/blue-green/test_basic_switching.py -v
pytest tests/blue-green/test_multi_team.py -v
pytest tests/blue-green/test_failure_scenarios.py -v
```

### Run Ansible Tests
```bash
# Basic deployment test
ansible-playbook tests/blue-green/ansible/test_blue_green_deployment.yml

# Environment switching test
ansible-playbook tests/blue-green/ansible/test_environment_switching.yml

# Rollback scenarios test
ansible-playbook tests/blue-green/ansible/test_rollback_scenarios.yml
```

## Test Scenarios Covered

### 1. Basic Environment Switching
- ✅ Blue to Green switching
- ✅ Green to Blue switching
- ✅ Container lifecycle management
- ✅ Port mapping validation
- ✅ Service accessibility checks

### 2. Multi-Team Operations
- ✅ Independent team switching
- ✅ Team isolation verification
- ✅ Concurrent operations
- ✅ Configuration validation

### 3. Failure Scenarios
- ✅ Pre-switch validation failures
- ✅ Switch operation failures
- ✅ Automatic rollback triggers
- ✅ Circuit breaker patterns
- ✅ Recovery procedures

### 4. HAProxy Integration
- ✅ Traffic routing validation
- ✅ Health check integration
- ✅ SSL certificate handling
- ✅ Load balancer configuration

### 5. SSL/TLS Management
- ✅ Certificate generation
- ✅ Domain routing validation
- ✅ Wildcard certificate handling
- ✅ Team-specific subdomains

## CI/CD Integration

Tests are designed to run in CI/CD pipelines with:
- Docker container support
- Mock services for external dependencies
- Parallel test execution
- Comprehensive reporting

## Test Data Management

All test configurations use:
- Isolated test environments
- Mock credentials (never real secrets)
- Reproducible test scenarios
- Clean state between test runs

## Configuration

### Test Configuration Files
- `conftest.py`: Pytest fixtures and configuration
- `requirements.txt`: Python dependencies
- `fixtures/test_inventory.yml`: Ansible inventory for testing
- `fixtures/mock_responses.json`: Mock API responses

### Environment Variables
```bash
# Optional environment variables for testing
export JENKINS_TEST_TIMEOUT=300        # Test timeout in seconds
export DOCKER_REGISTRY=localhost:5000  # Docker registry for test images
export TEST_LOG_LEVEL=INFO            # Log level for test output
export SKIP_SLOW_TESTS=false          # Skip slow tests
```

## Continuous Integration

The test suite integrates with GitHub Actions via `.github/workflows/blue-green-tests.yml`:

### Workflow Triggers
- Push to main/develop branches
- Pull requests
- Daily scheduled runs (2 AM UTC)
- Manual workflow dispatch

### Test Matrix
- **Unit Tests**: Fast, isolated tests without external dependencies
- **Integration Tests**: Full stack tests with Docker containers
- **Ansible Tests**: Playbook syntax and execution tests
- **Performance Tests**: Load and stress testing scenarios
- **Security Tests**: Dependency and code security scans

### Manual Execution
```bash
# Trigger specific test suite
gh workflow run blue-green-tests.yml \
  -f test_suite=basic \
  -f environment=local

# Available test suites:
# - all (default)
# - basic
# - multi-team
# - failure-scenarios
# - haproxy
# - ssl
```

## Test Data Management

### Mock Data Strategy
- All tests use mock data defined in `fixtures/mock_responses.json`
- No real credentials or production data
- Reproducible test scenarios
- Isolated test environments

### State Management
- Tests maintain clean state between runs
- Container cleanup after each test
- Temporary directories for test artifacts
- Circuit breaker state files in `/tmp/jenkins-ha-test/`

## Debugging Tests

### Local Development
```bash
# Run tests with verbose output
pytest tests/blue-green/ -v -s

# Run specific test with debugging
pytest tests/blue-green/test_basic_switching.py::TestBasicSwitching::test_container_port_mapping -v -s

# Run tests with coverage
pytest tests/blue-green/ --cov=. --cov-report=html

# Run only fast tests
pytest tests/blue-green/ -m "not slow and not integration"
```

### Container Debugging
```bash
# List test containers
docker ps -a --filter "name=jenkins-test"

# View container logs
docker logs jenkins-test-blue
docker logs jenkins-test-green

# Inspect container configuration
docker inspect jenkins-test-blue
```

### Log Analysis
```bash
# View test logs
tail -f /tmp/jenkins-ha-test/logs/test.log

# Check circuit breaker state
cat /tmp/jenkins-ha-test/circuit-breaker/state.json

# View Ansible execution logs
tail -f /tmp/ansible.log
```

## Performance Benchmarks

### Target Performance Metrics
- **Environment Switch Time**: < 30 seconds
- **Health Check Response**: < 5 seconds
- **Container Startup**: < 60 seconds
- **Rollback Time**: < 15 seconds
- **SSL Certificate Generation**: < 10 seconds

### Monitoring Integration
Tests include metrics collection for:
- Switch operation duration
- Container resource usage
- Network response times
- Error rates and availability
- Memory and CPU utilization

## Contributing

### Adding New Tests
1. **Follow naming conventions**: `test_<module>_<functionality>.py`
2. **Include comprehensive docstrings**: Describe test purpose and scenarios
3. **Use appropriate fixtures**: Leverage existing fixtures for setup/teardown
4. **Ensure test isolation**: Tests should not depend on other tests
5. **Add to CI matrix**: Include new test suites in GitHub Actions workflow
6. **Update documentation**: Document new test scenarios in this README

### Test Categories
Use pytest markers to categorize tests:
- `@pytest.mark.integration`: Integration tests requiring containers
- `@pytest.mark.ansible`: Ansible playbook tests
- `@pytest.mark.slow`: Long-running tests (> 30 seconds)
- `@pytest.mark.security`: Security-related tests

### Code Quality
All tests must pass:
- Linting with flake8, black, and isort
- Type checking with mypy
- Security scanning with bandit
- Dependency scanning with safety

### Pull Request Process
1. Ensure all tests pass locally
2. Add/update relevant tests for new functionality
3. Update documentation for test changes
4. CI must pass all test suites
5. Include test summary in PR description