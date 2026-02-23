# WebHost App Manager

**Version:** 1.0.0
**Category:** Administration > System
**Author:** PSWebHost Team

## Overview

WebHost App Manager is a system administration tool for managing PSWebHost applications. It provides a visual interface to view all installed apps, their status, configuration, and metadata.

## Features

- **View Installed Apps** - See all apps currently loaded in the PSWebHost instance
- **App Status Display** - Shows whether each app is enabled or disabled
- **Metadata Viewer** - Display app name, version, description, and loaded timestamp
- **Role Requirements** - View which roles are required to access each app
- **Node GUID Display** - Shows the unique identifier for this PSWebHost instance
- **Interactive UI** - Modern card-based interface with grid layout

## Access Requirements

**Required Roles:** `site_admin`

This app is restricted to site administrators only, as it provides sensitive information about the PSWebHost installation.

## Endpoints

### Main UI Endpoint

**URL:** `/apps/WebHostAppManager/cards/apps-manager`
**Method:** GET
**Security:** Requires `site_admin` role
**Returns:** JSON card metadata for loading React component

### API Endpoint

**URL:** `/api/v1/apps/list`
**Method:** GET
**Security:** Requires `site_admin` role
**Returns:** JSON with apps list and node information

## Installation

This app is part of the core PSWebHost distribution and should be enabled by default.

### Manual Installation

1. Ensure the app directory exists at `apps/WebHostAppManager/`
2. Verify `app.yaml` is configured correctly
3. Restart PSWebHost to load the app

## Configuration

Configuration is set in `app.yaml`:

```yaml
config:
  enableAppActions: true       # Enable app action buttons (future)
  showLoadTimestamps: true     # Display when apps were loaded
  showNodeGuid: true           # Display the node GUID
```

## Menu Integration

The app is accessible from the main menu:

**Path:** System Management → WebHost → Apps

## UI Components

### React Component

The app uses a React-based component (`public/elements/apps-manager/component.js`) that:

- Fetches app data from `/api/v1/apps/list` endpoint
- Renders a grid of app cards with modern styling
- Each app card displays:
  - **Name and Version** - App identifier and version number
  - **Status Badge** - Green (Enabled) or Red (Disabled)
  - **Description** - Brief description of the app's purpose
  - **Metadata Grid:**
    - Required Roles
    - Load Timestamp
    - App Path
  - **Action Buttons:**
    - Open (navigates to app)
    - Details (shows full app info via alert)

### Node GUID Display

Shows the unique GUID for the current PSWebHost node, useful for:
- Multi-node deployments
- Cluster management
- Node identification

## Technical Details

### Data Source

The API endpoint (`/api/v1/apps/list`) reads directly from `$Global:PSWebServer.Apps`, which contains:
- App manifests (from `app.yaml` files)
- Load timestamps
- Configuration data

### Architecture

The app follows PSWebHost's modern card-based architecture:

1. **Card Metadata Endpoint** (`routes/cards/apps-manager/get.ps1`):
   - Returns JSON metadata about the card
   - Specifies component path, title, description, features

2. **React Component** (`public/elements/apps-manager/component.js`):
   - Loaded dynamically by the card framework
   - Handles all UI rendering and interactions
   - Uses `window.psweb_fetchWithAuthHandling()` for API calls

3. **API Endpoint** (`routes/api/v1/apps/list/get.ps1`):
   - Provides JSON data for the component
   - Returns app list and node GUID

### Styling

Styles are defined in `public/elements/apps-manager/style.css`:
- Grid layout (auto-fill, minmax 350px)
- Card-based UI with hover effects
- Status badges with color coding
- Monospace font for technical data
- Responsive design with modern aesthetics

## Future Enhancements

Planned features:
- **Enable/Disable Apps** - Toggle app status without restart
- **App Settings** - Configure app-specific settings
- **Reload App** - Hot-reload individual apps
- **Install/Uninstall** - Add/remove apps via UI
- **App Marketplace** - Browse and install apps from repository
- **Update Checker** - Check for app updates
- **Dependencies Viewer** - Show app dependency tree

## Troubleshooting

### "No Apps Installed" Message

**Cause:** No apps found in `$Global:PSWebServer.Apps`

**Solutions:**
1. Verify apps exist in `apps/` directory
2. Check `app.yaml` files are valid
3. Ensure `enabled: true` in app manifests
4. Restart PSWebHost

### Access Denied

**Cause:** User lacks `site_admin` role

**Solutions:**
1. Verify user has `site_admin` role assigned
2. Check `get.security.json` configuration
3. Ensure authentication is working properly

### Apps Not Displaying Correctly

**Cause:** JavaScript error or data format issue

**Solutions:**
1. Check browser console for errors
2. Verify `$Global:PSWebServer.Apps` structure
3. Ensure app manifests have required fields

## Development

### Adding New Features

To add functionality:

1. **For UI changes:** Edit `public/elements/apps-manager/component.js` and `style.css`
2. **For API changes:** Edit `routes/api/v1/apps/list/get.ps1`
3. **For card metadata:** Edit `routes/cards/apps-manager/get.ps1`
4. Test with various app configurations
5. Update this README

### Testing

Test scenarios:
- Zero apps installed
- Single app installed
- Multiple apps (enabled/disabled mix)
- Apps with missing fields
- Apps with long descriptions

## Related Documentation

- [PSWebHost Apps Architecture](../../docs/APPS_SUMMARY.md)
- [App Development Guide](../../docs/APP_DEVELOPMENT.md)
- [Security Model](../../docs/SECURITY.md)

## License

Part of PSWebHost - see main LICENSE file.

---

**Last Updated:** 2026-02-23
**Architecture:** Modern React-based card component
**Status:** ✅ Production Ready
