# MySQL Manager

MySQL database administration and monitoring

## Status
**This is a skeleton app** - only basic infrastructure is implemented. See Architecture.md for details.

## Category
**Databases** > **MySQL**

## Installation
This app is automatically loaded by PSWebHost when placed in the apps/ directory.

## Configuration
- **Route Prefix:** /apps/mysqlmanager
- **Required Roles:** admin, database_admin
- **Author:** test

## File Structure
```
MySQLManager/
├── app.json                 # App manifest
├── app_init.ps1             # Initialization script
├── menu.yaml                # Menu entries
├── Architecture.md          # Implementation status and roadmap
├── routes/api/v1/           # API endpoints
│   ├── status/             # Status endpoint
│   └── ui/elements/        # (Future UI endpoints)
├── routes/cards/           # Card-based UI routes
│   └── mysql-manager/      # Main manager UI (placeholder)
└── tests/twin/             # Twin test framework
    ├── MySQLManager.Tests.ps1
    ├── browser-tests.js
    └── README.md
```

## Development Status
This app is currently a **skeleton/template only**. To complete implementation:
1. Add MySQL connection logic
2. Create database browser endpoints
3. Build query editor UI components
4. Implement user management features
5. See Architecture.md for full roadmap

## API Endpoints
- `GET /apps/mysqlmanager/api/v1/status` - App status (working)
- `GET /apps/mysqlmanager/cards/mysql-manager` - Main UI (placeholder only)

## Version History
- **1.0.0** (2026-01-10) - Initial skeleton release
