// Folder Definitions
// Creates all necessary folders for organizing Jenkins jobs

folder('Infrastructure') {
    displayName('Infrastructure Management')
    description('Jobs for managing Jenkins infrastructure, deployments, and maintenance')
}

folder('Applications') {
    displayName('Application Jobs')
    description('Jobs for building and deploying applications')
}

println "All folders created successfully"