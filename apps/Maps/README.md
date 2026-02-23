# Maps App

An interactive geographic visualization app for PSWebHost that provides world map functionality with location markers and status indicators.

## Overview

The Maps app provides an interactive world map visualization system with support for location markers, status indicators, and geographic data overlays. It uses an equirectangular projection for displaying global data and allows users to pan, zoom, and interact with location-based information.

## Version

1.0.0

## Category

- **Category**: visualization
- **Subcategory**: maps

## Features

- **Interactive World Map**: Equirectangular projection with pan and zoom capabilities
- **Location Markers**: Display points of interest with geographic coordinates
- **Status Indicators**: Color-coded markers showing operational status (Operational, Degraded, Outage)
- **Geographic Data Visualization**: Visual representation of data across global locations
- **Customizable Pins and Overlays**: Flexible marker system for various use cases

## Architecture

### Directory Structure

```
apps/Maps/
├── app.yaml                                      # App configuration
├── app_init.ps1                                  # App initialization script
├── menu.yaml                                     # Menu configuration
├── README.md                                     # This file
├── MIGRATION_SUMMARY.md                          # Migration history
├── public/
│   ├── elements/world-map/
│   │   ├── component.js                          # React component
│   │   ├── element.html                          # HTML container
│   │   ├── map-definition.json                   # Map metadata and projection config
│   │   └── world-map.png                         # Map image (2048x1024)
│   └── help/
│       └── world-map.md                          # User documentation
└── routes/
    └── cards/world-map/
        ├── get.ps1                               # Card data endpoint
        └── get.security.json                     # Security configuration
```

## Configuration

### Map Settings (app.yaml)

```yaml
config:
  defaultProjection: equirectangular
  imageWidth: 2048
  imageHeight: 1024
  maxMarkers: 100
```

### Map Definition (map-definition.json)

The map projection is defined in `public/elements/world-map/map-definition.json`:

- **Projection**: Equirectangular (flat/linear coordinate mapping)
- **Image Dimensions**: 2048x1024 pixels
- **Coordinate Range**: Latitude: -85.0511 to 85.0511, Longitude: -180 to 180
- **Curvature**: 0.0 (Euclidean, no spherical adjustment)

## Usage

### Accessing the Map

1. Navigate to the main menu
2. Click on "World Map" (requires 'authenticated' role)
3. The map will load with default location markers

### Adding Location Markers

Location markers are defined in `routes/cards/world-map/get.ps1`. Each marker requires:

```powershell
@{
    id = 'unique-id'
    title = 'Location Name'
    status = 'Operational'  # or 'Degraded', 'Outage'
    lat = 40.7128           # Latitude (-85.0511 to 85.0511)
    lng = -74.0060          # Longitude (-180 to 180)
}
```

### Status Indicators

- **Operational** (Green): Location is functioning normally
- **Degraded** (Orange): Location has reduced functionality
- **Outage** (Red): Location is offline or unavailable

## API Endpoints

### GET /apps/Maps/cards/world-map

Returns card configuration and location marker data.

**Response**:
```json
{
  "component": "world-map",
  "scriptPath": "/apps/Maps/public/elements/world-map/component.js",
  "title": "World Map",
  "description": "Interactive world map with location markers and geographic data visualization",
  "version": "1.0.0",
  "width": 12,
  "height": 14,
  "features": [...],
  "mapPins": [
    {
      "id": "ny",
      "title": "New York",
      "status": "Operational",
      "lat": 40.7128,
      "lng": -74.0060
    },
    ...
  ]
}
```

**Security**: Requires 'authenticated' role (see `get.security.json`)

## Dependencies

- **PSWebHost_Support**: Core PSWebHost support module
- **React**: Frontend component rendering
- **SVG**: Map and marker rendering

## Required Roles

- `authenticated`: Access to world map functionality

## Technical Details

### Coordinate Conversion

The app converts latitude/longitude coordinates to pixel positions using the equirectangular projection formula:

```javascript
normalizedX = (lng - topLeft.lng) / (bottomRight.lng - topLeft.lng)
normalizedY = (lat - topLeft.lat) / (bottomRight.lat - topLeft.lat)
pixelX = normalizedX * imageWidth
pixelY = normalizedY * imageHeight
```

### Component Integration

The React component is loaded via the card system and registered as `window.cardComponents['world-map']`.

## Migration History

This app was migrated from global `/public/elements/` to a dedicated app structure on 2026-01-19. See `MIGRATION_SUMMARY.md` for complete migration details.

### Breaking Changes

Old paths are no longer valid:
- `/api/v1/ui/elements/world-map` → `/apps/Maps/cards/world-map`
- `/public/elements/world-map/` → `/apps/Maps/public/elements/world-map/`

## Testing

To verify the Maps app is working correctly:

1. Check that "World Map" appears in the main menu
2. Click "World Map" and verify the map loads
3. Verify that the map image displays correctly
4. Confirm that location pins appear at the correct coordinates
5. Click on markers to view location details
6. Test pan and zoom functionality

## Development

### Adding New Map Types

To add additional map visualizations:

1. Create a new component in `public/elements/[map-name]/`
2. Add map definition JSON with projection parameters
3. Create route handler in `routes/cards/[map-name]/`
4. Update `menu.yaml` with new menu entry
5. Document the new map in `public/help/`

### Customizing Markers

Marker appearance can be customized in `component.js` by modifying the SVG circle attributes:

```javascript
circle.setAttribute('r', '8');        // Radius
circle.setAttribute('fill', color);   // Color
circle.setAttribute('stroke', 'white');
circle.setAttribute('stroke-width', '2');
```

## Support

For issues or questions about the Maps app, refer to:
- User documentation: `public/help/world-map.md`
- App configuration: `app.yaml`
- Component source: `public/elements/world-map/component.js`

## Author

PSWebHost Team

## License

Part of PSWebHost project
