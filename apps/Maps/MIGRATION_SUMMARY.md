# World Map Migration to Maps App

## Overview
The world-map functionality has been migrated from global `/public/elements/` to a dedicated Maps app following PSWebHost's app structure conventions.

## Migration Date
2026-01-19

## Changes Made

### 1. Created Maps App Structure
```
apps/Maps/
├── app.yaml                                           # App configuration
├── public/
│   ├── elements/world-map/
│   │   ├── component.js                               # React component (updated paths)
│   │   ├── element.html                               # HTML container
│   │   ├── map-definition.json                        # Map metadata
│   │   └── world-map.png                              # Map image
│   └── help/
│       └── world-map.md                               # Documentation
└── routes/api/v1/ui/elements/world-map/
    ├── get.ps1                                        # API endpoint
    └── get.security.json                              # Security config
```

### 2. Updated Component Paths
Updated `component.js` to use new app paths:
- Map definition: `/public/elements/world-map/map-definition.json` → `/apps/Maps/public/elements/world-map/map-definition.json`
- API endpoint: `/api/v1/ui/elements/world-map` → `/apps/Maps/api/v1/ui/elements/world-map`
- Image path: `/public/elements/world-map/world-map.png` → `/apps/Maps/public/elements/world-map/world-map.png`

### 3. Updated External References

**File: `public/layout.json`**
- Changed `componentPath` from `/public/elements/world-map/component.js` to `/apps/Maps/public/elements/world-map/component.js`

**File: `routes/api/v1/ui/elements/main-menu/main-menu.yaml`**
- Changed world-map menu URL from `/api/v1/ui/elements/world-map` to `/apps/Maps/api/v1/ui/elements/world-map`

**File: `tests/Test-AllEndpoints.ps1`**
- Updated test endpoint path to `/apps/Maps/api/v1/ui/elements/world-map`

**File: `tests/twin/routes/spa/card_settings/get.Tests.ps1`**
- Updated test comment to reference new path

**File: `tests/twin/routes/spa/card_settings/post.Tests.ps1`**
- Updated test comment to reference new path

### 4. Removed Old Files
Deleted original files after successful migration:
- `public/elements/world-map/` (entire directory)
- `routes/api/v1/ui/elements/world-map/` (entire directory)
- `public/help/world-map.md`

## App Configuration

**Category:** visualization
**Subcategory:** maps
**Required Roles:** authenticated
**Route Prefix:** /apps/Maps

## Features
- Interactive world map with equirectangular projection
- Location markers with status indicators (Operational, Degraded, Outage)
- Geographic data visualization
- Pan and zoom capabilities
- Customizable map pins and overlays

## Testing
After migration, verify:
1. World Map appears in main menu
2. Clicking "World Map" loads the component
3. Map image loads correctly
4. Location pins display with correct coordinates
5. API endpoint returns pin data at `/apps/Maps/api/v1/ui/elements/world-map`

## Backward Compatibility
⚠️ **Breaking Change**: Old paths (`/api/v1/ui/elements/world-map`, `/public/elements/world-map/`) are no longer valid. All clients must use new paths.

## Related Documentation
- App configuration: `apps/Maps/app.yaml`
- Map help: `apps/Maps/public/help/world-map.md`
- Component source: `apps/Maps/public/elements/world-map/component.js`
