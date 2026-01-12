# Docker Manager

Manage Docker containers and images on the host system.

## Requirements
- Docker daemon must be running
- User must have Docker permissions
- Linux platform recommended

## Features

### Container Management
View and control running containers:
- Container name and ID
- Image used
- Status (running, exited, paused)
- Port mappings
- Creation date

### Container Actions
- **Start/Stop**: Control container state
- **Restart**: Quick restart without removing
- **View Logs**: See container output
- **Remove**: Delete stopped containers

### Image Management
View available Docker images:
- Repository name
- Tag/version
- Image size
- Creation date

### Image Actions
- **Pull**: Download new images
- **Remove**: Delete unused images
- **Inspect**: View image details

## Resource Monitoring
View per-container:
- CPU usage percentage
- Memory consumption
- Network I/O
- Disk usage

## Access
This component requires `site_admin`, `system_admin`, or `admin` role.

**Note**: This feature is intended for Linux deployments.
