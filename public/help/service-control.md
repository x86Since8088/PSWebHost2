# Service Control

Manage system services running on the host machine.

## Platform Support

### Windows
Interfaces with Windows Service Control Manager to manage services.

### Linux
Integrates with systemd for service management.

## Features

### Service List
View all relevant services with:
- Service name
- Current status (running, stopped, starting)
- Process ID (PID)
- Memory usage
- CPU utilization

### Actions
- **Start**: Launch a stopped service
- **Stop**: Gracefully stop a running service
- **Restart**: Stop and start a service

### Filtering
Search and filter services by name to quickly find what you need.

## Monitored Services
- PSWebHost (main application)
- SQLite (database)
- Scheduler (background tasks)
- BackupService (automated backups)
- LogCollector (log aggregation)

## Access
This component requires `site_admin`, `system_admin`, or `admin` role.
