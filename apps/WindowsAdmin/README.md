# Windows Administration

Windows service and task scheduler management

## Category
**Operating Systems** > **Windows**

## Installation
This app is automatically loaded by PSWebHost when placed in the \pps/\ directory.

## Configuration
- **Route Prefix:** \$RoutePrefix\
- **Required Roles:** admin, system_admin
- **Author:** test

## File Structure
\\\
WindowsAdmin/
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
- \GET /apps/windowsadmin/api/v1/status\ - App status


## Version History
- **1.0.0** (2026-01-10) - Initial release

## Code Refactoring Notice

This app contains Linux-specific code that is planned for extraction to a shared cross-platform module (`PSCrossPlatformOSManagement.psm1`). This refactoring will eliminate code duplication with the LinuxAdmin app and improve maintainability.

See `LINUX_CODE_EXTRACTION_PLAN.md` for details.

Status: Pending coordination with LinuxAdmin agent.
