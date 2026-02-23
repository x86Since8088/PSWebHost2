# Redis Manager

Redis cache and data structure management

## Category
**Databases** > **Redis**

## Installation
This app is automatically loaded by PSWebHost when placed in the apps/ directory.

## Configuration
- **Route Prefix:** /apps/redismanager
- **Required Roles:** admin, database_admin
- **Author:** test

## File Structure
```
RedisManager/
├── app.json                 # App manifest
├── app_init.ps1             # Initialization script
├── menu.yaml                # Menu entries
├── data/                    # App data storage
├── public/                  # Public assets
├── routes/                  # API endpoints and cards
│   ├── api/v1/              # API endpoints
│   └── cards/               # Card components
└── tests/twin/              # Twin test framework
```

## Development
To add new features:
1. Create routes in `routes/api/v1/`
2. Add card components in `routes/cards/`
3. Update `menu.yaml` for menu integration
4. Update this README

## API Endpoints
- `GET /apps/redismanager/api/v1/status` - App status
- `GET /apps/redismanager/cards/redis-manager` - Redis Manager card component

## Version History
- **1.0.0** (2026-01-10) - Initial release
