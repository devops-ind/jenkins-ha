// Folder Definitions - Sandbox Compatible
// Creates all necessary folders for organizing Jenkins jobs

// Infrastructure folder
folder('Infrastructure') {
    displayName('Infrastructure Management')
    description('''
        Jobs for managing Jenkins infrastructure including:
        • System deployments and updates
        • Infrastructure monitoring and health checks  
        • Backup and disaster recovery operations
        • Security scanning and compliance
    ''')
    
    properties {
        folderCredentialsProperty {
            domainCredentials {
                domainCredentials {
                    domain {
                        name('infrastructure')
                        description('Infrastructure-specific credentials')
                    }
                }
            }
        }
    }
}

// Applications folder
folder('Applications') {
    displayName('Application Jobs')
    description('''
        Jobs for building, testing, and deploying applications including:
        • Build pipelines for different tech stacks
        • Automated testing and quality gates
        • Deployment automation
        • Application monitoring
    ''')
    
    properties {
        folderCredentialsProperty {
            domainCredentials {
                domainCredentials {
                    domain {
                        name('applications')
                        description('Application-specific credentials')
                    }
                }
            }
        }
    }
}

// Utilities folder
folder('Utilities') {
    displayName('Utility Jobs')
    description('''
        Utility and maintenance jobs including:
        • System maintenance tasks
        • Data cleanup operations
        • Administrative functions
        • Development tools and helpers
    ''')
}

// Success message (sandbox-safe)
out.println('✅ All folders created successfully')