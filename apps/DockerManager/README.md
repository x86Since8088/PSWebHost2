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
├── app.json                 # App manifest
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
- \GET /apps/dockermanager/api/v1/status\ - App status


## Version History
- **1.0.0** (2026-01-10) - Initial release
