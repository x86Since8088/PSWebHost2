# SQLite Manager

SQLite database file management

## Category
**Databases** > **SQLite**

## Installation
This app is automatically loaded by PSWebHost when placed in the apps/ directory.

## Configuration
- **Route Prefix:** /apps/sqlitemanager
- **Required Roles:** admin, database_admin
- **Author:** PSWebHost Team

## File Structure
```
SQLiteManager/
├── app.json                 # App manifest
├── app_init.ps1             # Initialization script
├── menu.yaml                # Menu entries
├── data/                    # App data storage
├── routes/                  # API routes and cards
│   ├── api/v1/             # API endpoints
│   │   ├── status/         # Status endpoint
│   │   └── sqlite/query/   # Query execution endpoint
│   └── cards/              # Card routes
│       ├── sqlite-manager/ # Database manager card
│       └── sqlite-query-editor/ # Query editor card
└── tests/twin/             # Twin tests (CLI + Browser)
```

## Development
To add new features:
1. Create routes in routes/api/v1/
2. Add UI components in public/elements/sqlite-manager/ or public/elements/sqlite-query-editor/
3. Update menu.yaml for menu integration
4. Update this README

## API Endpoints
- GET /apps/sqlitemanager/api/v1/status - App status
- POST /apps/sqlitemanager/api/v1/sqlite/query - Execute SQL queries

## Card Routes
- GET /apps/sqlitemanager/cards/sqlite-manager - Database manager card
- GET /apps/sqlitemanager/cards/sqlite-query-editor - Query editor card

## Components
- /public/elements/sqlite-manager/component.js - Database overview component
- /public/elements/sqlite-query-editor/component.js - Query editor component (to be created)

## Version History
- **1.0.0** (2026-01-10) - Initial release
