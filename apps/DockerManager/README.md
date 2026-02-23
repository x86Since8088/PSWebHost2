# Docker Manager

Docker container and image management

## Category
**Containers** > **Docker**

## Installation
This app is automatically loaded by PSWebHost when placed in the \pps/\ directory.

## Configuration
- **Route Prefix:** \$RoutePrefix\
- **Required Roles:** admin, system_admin
- **Author:** test

## File Structure
\\\
DockerManager/
├── app.yaml                 # App manifest
├── app_init.ps1             # Initialization script
├── menu.yaml                # Menu entries
├── data/                    # App data storage
├── modules/                 # App-specific modules
├── public/elements/         # UI components
└── routes/api/v1/           # API endpoints
\\\

## Development
To add new features:
1. Create routes in \outes/api/v1/\
2. Add UI elements in \public/elements/\
3. Update \menu.yaml\ for menu integration
4. Update this README

## API Endpoints

### Container Management
- \GET /apps/dockermanager/api/v1/docker/containers\ - List all containers
- \POST /apps/dockermanager/api/v1/docker/containers/{id}/start\ - Start container
- \POST /apps/dockermanager/api/v1/docker/containers/{id}/stop\ - Stop container
- \POST /apps/dockermanager/api/v1/docker/containers/{id}/restart\ - Restart container
- \DELETE /apps/dockermanager/api/v1/docker/containers/{id}\ - Delete container
- \GET /apps/dockermanager/api/v1/docker/containers/{id}/logs\ - View container logs

### Docker Info
- \GET /apps/dockermanager/api/v1/docker/info\ - Docker daemon status and statistics
- \GET /apps/dockermanager/api/v1/status\ - App metadata


## Version History
- **1.0.0** (2026-01-10) - Initial release
