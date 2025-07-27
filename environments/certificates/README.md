# SSL Certificates

Place your SSL certificates in this directory:

- `jenkins.crt` - Jenkins SSL certificate
- `jenkins.key` - Jenkins SSL private key  
- `ca-bundle.crt` - Certificate Authority bundle

## File Permissions

Ensure proper permissions:
```bash
chmod 600 jenkins.key
chmod 644 jenkins.crt
chmod 644 ca-bundle.crt
```
