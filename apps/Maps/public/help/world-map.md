# World Map

The World Map card provides an interactive geographic visualization system with location markers and status indicators using an equirectangular projection.

## Features

- **Interactive Map**: Responsive SVG-based world map with pan and zoom capabilities
- **Location Markers**: Display points of interest with precise latitude/longitude coordinates
- **Status Indicators**: Color-coded markers showing real-time operational status
  - Green: Operational (functioning normally)
  - Orange: Degraded (reduced functionality)
  - Red: Outage (offline or unavailable)
- **Equirectangular Projection**: Flat coordinate mapping covering latitude -85.0511 to 85.0511 and longitude -180 to 180
- **High-Resolution Map**: 2048x1024 pixel base image for detailed visualization

## Usage

### Accessing the Map

1. Navigate to the main menu in PSWebHost
2. Click on "World Map" (requires authenticated role)
3. The map will load with current location markers

### Interacting with the Map

- **View Details**: Click on any marker to see location information and status
- **Pan**: The map scales automatically to fit your viewport
- **Responsive Design**: Map adapts to different screen sizes while maintaining aspect ratio

### Understanding Markers

Each marker on the map represents a monitored location and displays:
- **Location Name**: The title of the monitored site
- **Status**: Current operational state (Operational, Degraded, or Outage)
- **Geographic Position**: Precise coordinates on the world map

## Example Locations

The map comes pre-configured with sample locations:
- **New York**: Operational (40.7128 N, 74.0060 W)
- **London**: Operational (51.5074 N, 0.1278 W)
- **Tokyo**: Degraded (35.6895 N, 139.6917 E)
- **Sydney**: Outage (33.8688 S, 151.2093 E)
- **Rio de Janeiro**: Operational (22.9068 S, 43.1729 W)

## Data Sources

The map can display data from various sources:
- **Server Locations**: Monitor data center and server status globally
- **Service Endpoints**: Track API and service availability by region
- **Infrastructure Monitoring**: Display operational status of distributed systems
- **Geographic Metrics**: Visualize regional performance and statistics

## Technical Details

### Projection
- **Type**: Equirectangular (simple cylindrical projection)
- **Curvature**: 0.0 (Euclidean, no spherical adjustment)
- **Image**: 2048x1024 pixels

### Coordinate System
- **Latitude Range**: -85.0511 to 85.0511 degrees
- **Longitude Range**: -180 to 180 degrees
- **Mapping**: Linear transformation from lat/lng to pixel coordinates

## Customization

Map markers and data can be customized by modifying the endpoint at:
`/apps/Maps/routes/cards/world-map/get.ps1`

Each marker requires:
- **id**: Unique identifier
- **title**: Display name
- **status**: One of 'Operational', 'Degraded', or 'Outage'
- **lat**: Latitude coordinate (-85.0511 to 85.0511)
- **lng**: Longitude coordinate (-180 to 180)

## Troubleshooting

### Map Not Loading
- Verify you are authenticated and have the required role
- Check that the map image exists at `/apps/Maps/public/elements/world-map/world-map.png`
- Ensure the API endpoint `/apps/Maps/cards/world-map` is accessible

### Markers Not Appearing
- Verify marker coordinates are within valid ranges
- Check the console for JavaScript errors
- Confirm the API endpoint is returning `mapPins` data

### Image Display Issues
- Clear browser cache and reload
- Verify the map definition JSON is accessible
- Check browser console for image loading errors

## Related Documentation

- App README: `/apps/Maps/README.md`
- App Configuration: `/apps/Maps/app.yaml`
- Migration History: `/apps/Maps/MIGRATION_SUMMARY.md`
