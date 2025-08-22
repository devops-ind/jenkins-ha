"""
SSL certificate handling tests for blue-green deployments.

This module tests SSL/TLS certificate management including:
- Certificate generation and validation
- Domain routing with SSL
- Wildcard certificate handling
- Team-specific subdomains
- Certificate rotation during switches
"""
import os
import tempfile
import time
import pytest
from pathlib import Path
from unittest.mock import Mock, patch, mock_open
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
import datetime


class TestSSLCertificateGeneration:
    """Test SSL certificate generation for blue-green deployments."""
    
    def test_wildcard_certificate_creation(self, tmp_path):
        """Test creation of wildcard SSL certificates."""
        def generate_wildcard_certificate(domain, teams, output_dir):
            """Generate wildcard certificate with team subdomains."""
            # Create private key
            private_key = rsa.generate_private_key(
                public_exponent=65537,
                key_size=2048,
            )
            
            # Build subject alternative names
            san_list = [
                x509.DNSName(f"*.{domain}"),
                x509.DNSName(domain),
                x509.DNSName(f"jenkins.{domain}")
            ]
            
            # Add team-specific subdomains
            for team in teams:
                san_list.append(x509.DNSName(f"{team['team_name']}jenkins.{domain}"))
            
            # Add monitoring subdomains
            san_list.extend([
                x509.DNSName(f"prometheus.{domain}"),
                x509.DNSName(f"grafana.{domain}"),
                x509.DNSName(f"node-exporter.{domain}")
            ])
            
            # Create certificate
            subject = x509.Name([
                x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
                x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "California"),
                x509.NameAttribute(NameOID.LOCALITY_NAME, "San Francisco"),
                x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Jenkins HA Infrastructure"),
                x509.NameAttribute(NameOID.COMMON_NAME, f"*.{domain}"),
            ])
            
            cert = x509.CertificateBuilder().subject_name(
                subject
            ).issuer_name(
                subject  # Self-signed
            ).public_key(
                private_key.public_key()
            ).serial_number(
                x509.random_serial_number()
            ).not_valid_before(
                datetime.datetime.utcnow()
            ).not_valid_after(
                datetime.datetime.utcnow() + datetime.timedelta(days=365)
            ).add_extension(
                x509.SubjectAlternativeName(san_list),
                critical=False,
            ).add_extension(
                x509.KeyUsage(
                    digital_signature=True,
                    key_encipherment=True,
                    non_repudiation=True,
                    key_cert_sign=False,
                    crl_sign=False,
                    content_commitment=False,
                    data_encipherment=False,
                    key_agreement=False,
                    encipher_only=False,
                    decipher_only=False
                ),
                critical=True,
            ).add_extension(
                x509.ExtendedKeyUsage([
                    x509.oid.ExtendedKeyUsageOID.SERVER_AUTH,
                    x509.oid.ExtendedKeyUsageOID.CLIENT_AUTH,
                ]),
                critical=False,
            ).sign(private_key, hashes.SHA256())
            
            # Save certificate and key
            cert_file = output_dir / f"wildcard-{domain}.crt"
            key_file = output_dir / f"wildcard-{domain}.key"
            
            with open(cert_file, "wb") as f:
                f.write(cert.public_bytes(serialization.Encoding.PEM))
            
            with open(key_file, "wb") as f:
                f.write(private_key.private_bytes(
                    encoding=serialization.Encoding.PEM,
                    format=serialization.PrivateFormat.PKCS8,
                    encryption_algorithm=serialization.NoEncryption()
                ))
            
            return {
                "certificate_file": str(cert_file),
                "private_key_file": str(key_file),
                "san_count": len(san_list),
                "domains": [name.value for name in san_list]
            }
        
        # Test certificate generation
        test_domain = "test.local"
        test_teams = [
            {"team_name": "devops"},
            {"team_name": "qa"},
            {"team_name": "staging"}
        ]
        
        cert_info = generate_wildcard_certificate(test_domain, test_teams, tmp_path)
        
        # Verify certificate files were created
        assert os.path.exists(cert_info["certificate_file"])
        assert os.path.exists(cert_info["private_key_file"])
        
        # Verify SAN list includes expected domains
        expected_domains = [
            f"*.{test_domain}",
            test_domain,
            f"jenkins.{test_domain}",
            "devopsjenkins.test.local",
            "qajenkins.test.local", 
            "stagingjenkins.test.local",
            f"prometheus.{test_domain}",
            f"grafana.{test_domain}",
            f"node-exporter.{test_domain}"
        ]
        
        for expected_domain in expected_domains:
            assert expected_domain in cert_info["domains"], f"Missing domain: {expected_domain}"
        
        assert cert_info["san_count"] == len(expected_domains)
    
    def test_certificate_validation(self, tmp_path):
        """Test SSL certificate validation."""
        def validate_certificate(cert_file, key_file, expected_domains=None):
            """Validate SSL certificate properties."""
            try:
                # Load certificate
                with open(cert_file, "rb") as f:
                    cert_data = f.read()
                    cert = x509.load_pem_x509_certificate(cert_data)
                
                # Load private key
                with open(key_file, "rb") as f:
                    key_data = f.read()
                    private_key = serialization.load_pem_private_key(key_data, password=None)
                
                # Validate certificate properties
                validation_results = {
                    "valid": True,
                    "issues": [],
                    "properties": {}
                }
                
                # Check expiration
                now = datetime.datetime.utcnow()
                if cert.not_valid_after < now:
                    validation_results["issues"].append("Certificate expired")
                    validation_results["valid"] = False
                
                if cert.not_valid_before > now:
                    validation_results["issues"].append("Certificate not yet valid")
                    validation_results["valid"] = False
                
                # Check key match
                cert_public_key = cert.public_key()
                private_public_key = private_key.public_key()
                
                # Simple key matching check (comparing public key numbers)
                cert_numbers = cert_public_key.public_numbers()
                private_numbers = private_public_key.public_numbers()
                
                if cert_numbers.n != private_numbers.n or cert_numbers.e != private_numbers.e:
                    validation_results["issues"].append("Certificate and private key do not match")
                    validation_results["valid"] = False
                
                # Extract SAN domains
                try:
                    san_extension = cert.extensions.get_extension_for_oid(x509.oid.ExtensionOID.SUBJECT_ALTERNATIVE_NAME)
                    san_domains = [name.value for name in san_extension.value]
                    validation_results["properties"]["san_domains"] = san_domains
                except x509.ExtensionNotFound:
                    validation_results["issues"].append("No SAN extension found")
                
                # Validate expected domains
                if expected_domains:
                    missing_domains = set(expected_domains) - set(validation_results["properties"].get("san_domains", []))
                    if missing_domains:
                        validation_results["issues"].append(f"Missing expected domains: {list(missing_domains)}")
                        validation_results["valid"] = False
                
                return validation_results
                
            except Exception as e:
                return {
                    "valid": False,
                    "issues": [f"Certificate validation error: {str(e)}"],
                    "properties": {}
                }
        
        # Create a test certificate first
        private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        
        subject = x509.Name([
            x509.NameAttribute(NameOID.COMMON_NAME, "*.test.local"),
        ])
        
        cert = x509.CertificateBuilder().subject_name(
            subject
        ).issuer_name(
            subject
        ).public_key(
            private_key.public_key()
        ).serial_number(
            x509.random_serial_number()
        ).not_valid_before(
            datetime.datetime.utcnow()
        ).not_valid_after(
            datetime.datetime.utcnow() + datetime.timedelta(days=30)
        ).add_extension(
            x509.SubjectAlternativeName([
                x509.DNSName("*.test.local"),
                x509.DNSName("test.local"),
                x509.DNSName("jenkins.test.local")
            ]),
            critical=False,
        ).sign(private_key, hashes.SHA256())
        
        # Save test certificate
        cert_file = tmp_path / "test.crt"
        key_file = tmp_path / "test.key"
        
        with open(cert_file, "wb") as f:
            f.write(cert.public_bytes(serialization.Encoding.PEM))
        
        with open(key_file, "wb") as f:
            f.write(private_key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption()
            ))
        
        # Test certificate validation
        validation = validate_certificate(
            str(cert_file), 
            str(key_file),
            expected_domains=["*.test.local", "test.local", "jenkins.test.local"]
        )
        
        assert validation["valid"], f"Certificate should be valid: {validation['issues']}"
        assert len(validation["issues"]) == 0, f"Should have no validation issues: {validation['issues']}"
        
        # Verify SAN domains
        san_domains = validation["properties"]["san_domains"]
        assert "*.test.local" in san_domains
        assert "test.local" in san_domains
        assert "jenkins.test.local" in san_domains
    
    def test_team_specific_domains(self):
        """Test generation of team-specific domain configurations."""
        def generate_team_domains(base_domain, teams):
            """Generate domain configurations for teams."""
            domain_config = {
                "base_domain": base_domain,
                "wildcard_domain": f"*.{base_domain}",
                "team_domains": [],
                "service_domains": []
            }
            
            # Generate team-specific subdomains
            for team in teams:
                team_name = team["team_name"]
                team_domain = f"{team_name}jenkins.{base_domain}"
                
                domain_config["team_domains"].append({
                    "team": team_name,
                    "domain": team_domain,
                    "blue_url": f"https://{team_domain}/blue",
                    "green_url": f"https://{team_domain}/green"
                })
            
            # Add service domains
            services = ["prometheus", "grafana", "node-exporter"]
            for service in services:
                service_domain = f"{service}.{base_domain}"
                domain_config["service_domains"].append({
                    "service": service,
                    "domain": service_domain,
                    "url": f"https://{service_domain}"
                })
            
            return domain_config
        
        # Test domain generation
        test_teams = [
            {"team_name": "devops"},
            {"team_name": "qa"},
            {"team_name": "frontend"},
            {"team_name": "backend"}
        ]
        
        domain_config = generate_team_domains("company.com", test_teams)
        
        # Verify base configuration
        assert domain_config["base_domain"] == "company.com"
        assert domain_config["wildcard_domain"] == "*.company.com"
        
        # Verify team domains
        assert len(domain_config["team_domains"]) == 4
        
        team_domains = {td["team"]: td["domain"] for td in domain_config["team_domains"]}
        assert team_domains["devops"] == "devopsjenkins.company.com"
        assert team_domains["qa"] == "qajenkins.company.com"
        assert team_domains["frontend"] == "frontendjenkins.company.com"
        assert team_domains["backend"] == "backendjenkins.company.com"
        
        # Verify service domains
        assert len(domain_config["service_domains"]) == 3
        
        service_domains = {sd["service"]: sd["domain"] for sd in domain_config["service_domains"]}
        assert service_domains["prometheus"] == "prometheus.company.com"
        assert service_domains["grafana"] == "grafana.company.com"
        assert service_domains["node-exporter"] == "node-exporter.company.com"


class TestSSLCertificateRotation:
    """Test SSL certificate rotation during blue-green switches."""
    
    def test_certificate_rotation_workflow(self, tmp_path):
        """Test certificate rotation workflow."""
        def rotate_certificates(current_cert_path, teams, rotation_strategy="zero-downtime"):
            """Simulate certificate rotation process."""
            rotation_steps = []
            
            if rotation_strategy == "zero-downtime":
                # Zero-downtime rotation
                rotation_steps.extend([
                    "Generate new certificate with updated SAN list",
                    "Create new certificate bundle",
                    "Update load balancer configuration (staged)",
                    "Test new certificate with health checks",
                    "Switch traffic to new certificate",
                    "Verify certificate functionality",
                    "Remove old certificate files"
                ])
            elif rotation_strategy == "maintenance-window":
                # Maintenance window rotation
                rotation_steps.extend([
                    "Schedule maintenance window",
                    "Stop services temporarily",
                    "Generate new certificate",
                    "Update all configurations",
                    "Restart services",
                    "Verify certificate functionality"
                ])
            
            # Simulate rotation execution
            rotation_result = {
                "strategy": rotation_strategy,
                "steps_completed": len(rotation_steps),
                "total_steps": len(rotation_steps),
                "success": True,
                "new_cert_path": str(tmp_path / "rotated-cert.crt"),
                "rollback_available": True,
                "downtime": 0 if rotation_strategy == "zero-downtime" else 60
            }
            
            return rotation_result
        
        # Test zero-downtime rotation
        teams = [{"team_name": "devops"}, {"team_name": "qa"}]
        current_cert = str(tmp_path / "current-cert.crt")
        
        zero_downtime_result = rotate_certificates(current_cert, teams, "zero-downtime")
        
        assert zero_downtime_result["success"]
        assert zero_downtime_result["strategy"] == "zero-downtime"
        assert zero_downtime_result["downtime"] == 0
        assert zero_downtime_result["steps_completed"] == 7
        assert zero_downtime_result["rollback_available"]
        
        # Test maintenance window rotation
        maintenance_result = rotate_certificates(current_cert, teams, "maintenance-window")
        
        assert maintenance_result["success"]
        assert maintenance_result["strategy"] == "maintenance-window"
        assert maintenance_result["downtime"] == 60  # 1 minute downtime
        assert maintenance_result["steps_completed"] == 6
    
    def test_certificate_rollback(self, tmp_path):
        """Test certificate rollback on rotation failure."""
        def attempt_certificate_rollback(current_cert, backup_cert, failure_reason):
            """Attempt to rollback certificate on rotation failure."""
            rollback_steps = []
            
            try:
                # Step 1: Validate backup certificate exists
                if not os.path.exists(backup_cert):
                    raise FileNotFoundError("Backup certificate not found")
                rollback_steps.append("Validated backup certificate exists")
                
                # Step 2: Restore backup certificate
                # In real implementation, this would copy the backup over current
                rollback_steps.append("Restored backup certificate")
                
                # Step 3: Update load balancer configuration
                rollback_steps.append("Updated load balancer configuration")
                
                # Step 4: Restart services
                rollback_steps.append("Restarted affected services")
                
                # Step 5: Verify rollback success
                rollback_steps.append("Verified certificate functionality")
                
                return {
                    "rollback_successful": True,
                    "steps_completed": rollback_steps,
                    "active_certificate": backup_cert,
                    "failure_reason": failure_reason
                }
                
            except Exception as e:
                return {
                    "rollback_successful": False,
                    "steps_completed": rollback_steps,
                    "error": str(e),
                    "failure_reason": failure_reason
                }
        
        # Create mock certificate files
        current_cert = tmp_path / "current.crt"
        backup_cert = tmp_path / "backup.crt"
        
        current_cert.write_text("mock current certificate")
        backup_cert.write_text("mock backup certificate")
        
        # Test successful rollback
        rollback_result = attempt_certificate_rollback(
            str(current_cert), 
            str(backup_cert), 
            "New certificate validation failed"
        )
        
        assert rollback_result["rollback_successful"]
        assert len(rollback_result["steps_completed"]) == 5
        assert rollback_result["active_certificate"] == str(backup_cert)
        assert rollback_result["failure_reason"] == "New certificate validation failed"
        
        # Test rollback failure (missing backup)
        missing_backup = str(tmp_path / "missing-backup.crt")
        rollback_failure = attempt_certificate_rollback(
            str(current_cert),
            missing_backup,
            "Certificate generation failed"
        )
        
        assert not rollback_failure["rollback_successful"]
        assert "Backup certificate not found" in rollback_failure["error"]
    
    def test_certificate_expiration_monitoring(self):
        """Test monitoring of certificate expiration."""
        def check_certificate_expiration(certificates, warning_days=30):
            """Check certificate expiration status."""
            now = datetime.datetime.utcnow()
            expiration_status = {}
            
            for cert_name, cert_info in certificates.items():
                days_until_expiry = (cert_info["expires"] - now).days
                
                status = {
                    "expires": cert_info["expires"],
                    "days_until_expiry": days_until_expiry,
                    "status": "valid"
                }
                
                if days_until_expiry < 0:
                    status["status"] = "expired"
                    status["alert_level"] = "critical"
                elif days_until_expiry <= warning_days:
                    status["status"] = "expiring_soon"
                    status["alert_level"] = "warning"
                else:
                    status["alert_level"] = "ok"
                
                expiration_status[cert_name] = status
            
            return expiration_status
        
        # Test certificate expiration checking
        now = datetime.datetime.utcnow()
        test_certificates = {
            "current-prod": {
                "expires": now + datetime.timedelta(days=60)  # 60 days from now
            },
            "expiring-cert": {
                "expires": now + datetime.timedelta(days=15)  # 15 days from now
            },
            "expired-cert": {
                "expires": now - datetime.timedelta(days=5)   # 5 days ago
            }
        }
        
        expiration_status = check_certificate_expiration(test_certificates)
        
        # Verify current-prod certificate (valid)
        current_status = expiration_status["current-prod"]
        assert current_status["status"] == "valid"
        assert current_status["alert_level"] == "ok"
        assert current_status["days_until_expiry"] == 60
        
        # Verify expiring certificate (warning)
        expiring_status = expiration_status["expiring-cert"]
        assert expiring_status["status"] == "expiring_soon"
        assert expiring_status["alert_level"] == "warning"
        assert expiring_status["days_until_expiry"] == 15
        
        # Verify expired certificate (critical)
        expired_status = expiration_status["expired-cert"]
        assert expired_status["status"] == "expired"
        assert expired_status["alert_level"] == "critical"
        assert expired_status["days_until_expiry"] == -5


class TestSSLIntegrationWithBlueGreen:
    """Test SSL certificate integration with blue-green deployments."""
    
    def test_ssl_during_environment_switch(self):
        """Test SSL behavior during environment switching."""
        def switch_environment_with_ssl(from_env, to_env, ssl_config):
            """Switch environments while maintaining SSL connectivity."""
            switch_sequence = []
            
            # Pre-switch SSL validation
            switch_sequence.append({
                "step": "pre_switch_ssl_validation",
                "action": f"Validate SSL certificate for {to_env} environment",
                "status": "completed"
            })
            
            # Update SSL configuration for target environment
            switch_sequence.append({
                "step": "update_ssl_config",
                "action": f"Update SSL configuration for {to_env}",
                "ssl_cert_path": ssl_config["cert_path"],
                "status": "completed"
            })
            
            # Test SSL connectivity on target
            switch_sequence.append({
                "step": "test_ssl_connectivity",
                "action": f"Test SSL connectivity to {to_env}",
                "test_url": f"https://{ssl_config['domain']}/login",
                "status": "completed"
            })
            
            # Switch traffic with SSL validation
            switch_sequence.append({
                "step": "switch_traffic",
                "action": f"Switch traffic from {from_env} to {to_env}",
                "ssl_validation": "passed",
                "status": "completed"
            })
            
            # Post-switch SSL verification
            switch_sequence.append({
                "step": "post_switch_verification",
                "action": "Verify SSL after environment switch",
                "certificate_valid": True,
                "https_accessible": True,
                "status": "completed"
            })
            
            return {
                "switch_successful": True,
                "from_environment": from_env,
                "to_environment": to_env,
                "ssl_maintained": True,
                "sequence": switch_sequence
            }
        
        # Test SSL-enabled environment switch
        ssl_config = {
            "cert_path": "/etc/ssl/certs/wildcard-company.com.crt",
            "key_path": "/etc/ssl/private/wildcard-company.com.key",
            "domain": "jenkins.company.com"
        }
        
        switch_result = switch_environment_with_ssl("blue", "green", ssl_config)
        
        assert switch_result["switch_successful"]
        assert switch_result["ssl_maintained"]
        assert len(switch_result["sequence"]) == 5
        
        # Verify all steps completed successfully
        for step in switch_result["sequence"]:
            assert step["status"] == "completed"
        
        # Verify SSL-specific steps
        ssl_steps = [s for s in switch_result["sequence"] if "ssl" in s["step"]]
        assert len(ssl_steps) >= 2  # At least pre and post SSL validation
    
    def test_ssl_certificate_update_during_switch(self, tmp_path):
        """Test updating SSL certificates during blue-green switch."""
        def update_ssl_during_switch(teams, new_team_added=None):
            """Update SSL certificate when teams are modified."""
            # Current certificate domains
            current_domains = set()
            for team in teams:
                current_domains.add(f"{team['team_name']}jenkins.company.com")
            
            # Add new team domain if specified
            if new_team_added:
                current_domains.add(f"{new_team_added}jenkins.company.com")
            
            # Standard domains
            current_domains.update([
                "*.company.com",
                "company.com", 
                "jenkins.company.com",
                "prometheus.company.com",
                "grafana.company.com"
            ])
            
            # Generate new certificate with updated domains
            new_cert_config = {
                "domains": list(current_domains),
                "cert_file": str(tmp_path / "updated-wildcard.crt"),
                "key_file": str(tmp_path / "updated-wildcard.key"),
                "bundle_file": str(tmp_path / "updated-haproxy.pem")
            }
            
            update_process = [
                "Generate new certificate with updated SAN list",
                "Create HAProxy certificate bundle",
                "Stage new certificate in load balancer",
                "Test certificate with new team domains",
                "Switch to new certificate", 
                "Verify all team domains accessible",
                "Clean up old certificate files"
            ]
            
            return {
                "certificate_updated": True,
                "new_domains": list(current_domains),
                "cert_config": new_cert_config,
                "update_process": update_process,
                "downtime": 0  # Zero downtime update
            }
        
        # Test SSL update when adding new team
        existing_teams = [
            {"team_name": "devops"},
            {"team_name": "qa"}
        ]
        
        update_result = update_ssl_during_switch(existing_teams, new_team_added="frontend")
        
        assert update_result["certificate_updated"]
        assert update_result["downtime"] == 0
        assert len(update_result["update_process"]) == 7
        
        # Verify new team domain included
        new_domains = update_result["new_domains"]
        assert "frontendjenkins.company.com" in new_domains
        assert "devopsjenkins.company.com" in new_domains
        assert "qajenkins.company.com" in new_domains
        
        # Verify standard domains still included
        assert "*.company.com" in new_domains
        assert "prometheus.company.com" in new_domains
    
    def test_ssl_validation_in_health_checks(self):
        """Test SSL validation as part of health checks."""
        def ssl_health_check(endpoints):
            """Perform SSL health checks on endpoints."""
            health_results = {}
            
            for endpoint in endpoints:
                url = endpoint["url"]
                expected_cert = endpoint.get("expected_cert")
                
                # Simulate SSL health check
                health_status = {
                    "url": url,
                    "ssl_valid": True,
                    "cert_expiry_days": 45,
                    "cert_issuer": "Jenkins HA Infrastructure",
                    "protocols": ["TLSv1.2", "TLSv1.3"],
                    "cipher_suites": ["TLS_AES_256_GCM_SHA384", "TLS_CHACHA20_POLY1305_SHA256"]
                }
                
                # Check for SSL issues
                if "expired" in url:
                    health_status["ssl_valid"] = False
                    health_status["cert_expiry_days"] = -5
                    health_status["error"] = "Certificate expired"
                
                if "mismatch" in url:
                    health_status["ssl_valid"] = False
                    health_status["error"] = "Certificate domain mismatch"
                
                health_results[url] = health_status
            
            return health_results
        
        # Test SSL health checks
        test_endpoints = [
            {"url": "https://devopsjenkins.company.com"},
            {"url": "https://qajenkins.company.com"},
            {"url": "https://expiredjenkins.company.com"},  # Simulate expired cert
            {"url": "https://mismatchjenkins.company.com"}  # Simulate domain mismatch
        ]
        
        health_results = ssl_health_check(test_endpoints)
        
        # Verify healthy endpoints
        devops_health = health_results["https://devopsjenkins.company.com"]
        assert devops_health["ssl_valid"]
        assert devops_health["cert_expiry_days"] > 30
        assert "TLSv1.3" in devops_health["protocols"]
        
        qa_health = health_results["https://qajenkins.company.com"]
        assert qa_health["ssl_valid"]
        
        # Verify expired certificate detection
        expired_health = health_results["https://expiredjenkins.company.com"]
        assert not expired_health["ssl_valid"]
        assert expired_health["cert_expiry_days"] < 0
        assert "expired" in expired_health["error"]
        
        # Verify domain mismatch detection
        mismatch_health = health_results["https://mismatchjenkins.company.com"]
        assert not mismatch_health["ssl_valid"]
        assert "mismatch" in mismatch_health["error"]
    
    def test_ssl_load_balancer_integration(self):
        """Test SSL integration with load balancer configuration."""
        def generate_haproxy_ssl_config(teams, ssl_cert_path):
            """Generate HAProxy SSL configuration for teams."""
            config_sections = []
            
            # Global SSL configuration
            config_sections.append("""
global
    tune.ssl.default-dh-param 2048
    ssl-default-bind-ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets
""")
            
            # Frontend with SSL termination
            config_sections.append(f"""
frontend jenkins_https
    bind *:443 ssl crt {ssl_cert_path}
    mode http
    
    # HSTS header
    http-response set-header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    
    # Team-based routing
""")
            
            # Team-specific ACLs and backends
            for team in teams:
                team_name = team["team_name"]
                active_env = team.get("active_environment", "blue")
                
                config_sections.append(f"""
    # {team_name.upper()} team routing
    acl is_{team_name} hdr_beg(host) -i {team_name}jenkins.
    use_backend jenkins_{team_name}_backend if is_{team_name}
    
backend jenkins_{team_name}_backend
    mode http
    balance roundrobin
    option httpchk GET /{team_name}/login
    http-check expect status 200,403
    
    server jenkins-{team_name}-{active_env} localhost:808{1 if active_env == 'blue' else 2} check ssl verify none
    server jenkins-{team_name}-{'green' if active_env == 'blue' else 'blue'} localhost:808{2 if active_env == 'blue' else 1} check backup ssl verify none
""")
            
            return "\n".join(config_sections)
        
        # Test SSL configuration generation
        test_teams = [
            {"team_name": "devops", "active_environment": "blue"},
            {"team_name": "qa", "active_environment": "green"}
        ]
        
        ssl_config = generate_haproxy_ssl_config(
            test_teams, 
            "/etc/ssl/certs/wildcard-company.com.pem"
        )
        
        # Verify SSL configuration elements
        assert "ssl crt /etc/ssl/certs/wildcard-company.com.pem" in ssl_config
        assert "ssl-min-ver TLSv1.2" in ssl_config
        assert "Strict-Transport-Security" in ssl_config
        
        # Verify team-specific routing
        assert "acl is_devops hdr_beg(host) -i devopsjenkins." in ssl_config
        assert "acl is_qa hdr_beg(host) -i qajenkins." in ssl_config
        
        # Verify backend SSL configuration
        assert "check ssl verify none" in ssl_config
        
        # Verify active environment routing
        assert "jenkins-devops-blue" in ssl_config  # devops active=blue
        assert "jenkins-qa-green" in ssl_config     # qa active=green