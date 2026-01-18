# WebHost Realtime Events

Real-time event monitoring and log viewer for PSWebHost with advanced filtering, sorting, and time range controls.

## Features

### Time Range Filtering
- **Preset Ranges**: 5 min, 15 min, 30 min, 1 hour, 4 hours, 24 hours
- **Custom Range**: Specify exact start and end timestamps
- **Default**: Last 15 minutes of logs

### Advanced Filtering
- **Text Search**: Search across all log fields simultaneously
- **Category Filter**: Filter by log category (e.g., Auth, Database, API)
- **Severity Filter**: Filter by severity (Critical, Error, Warning, Info, Verbose, Debug)
- **Source Filter**: Filter by source script/function path
- **User ID Filter**: Filter by specific user
- **Session ID Filter**: Filter by session identifier

### Sortable Columns
Click any sortable column header to sort:
- **Time** (LocalTime) - Default sort, descending
- **Severity**
- **Category**
- **Source**
- **User ID**
- **Session ID**

Toggle sort direction by clicking the same column again.

### Display Options
- **Column Visibility**: Show/hide columns via the Columns menu
- **Word Wrap**: Toggle text wrapping in table cells
- **Column Resizing**: Drag column borders to resize
- **Max Events**: Limit number of displayed logs (10-10000)
- **Auto-Refresh**: Updates every 5 seconds (can be paused)

### Export Capabilities
- **CSV Export**: Export selected logs to CSV file
- **TSV Copy**: Copy selected logs to clipboard as TSV

### Enhanced Log Format Support
Supports the new 12-column log format with:
- Source (auto-detected script/function path)
- ActivityName (function name)
- PercentComplete (progress tracking)
- UserID (session user)
- SessionID (session identifier)
- RunspaceID (PowerShell runspace)
- Plus legacy 8-column format

## API Endpoints

### GET /api/v1/events/logs
Main log retrieval endpoint with comprehensive filtering.

**Query Parameters:**
- `timeRange` - Time range in minutes (default: 15)
- `earliest` - Start timestamp (ISO 8601)
- `latest` - End timestamp (ISO 8601)
- `filter` - Text search filter
- `category` - Category filter (supports wildcards)
- `severity` - Severity filter
- `source` - Source filter
- `userID` - User ID filter
- `sessionID` - Session ID filter
- `activityName` - Activity name filter
- `runspaceID` - Runspace ID filter
- `sortBy` - Sort field (Date, Severity, Category, Source, UserID, SessionID)
- `sortOrder` - Sort order (asc/desc, default: desc)
- `count` - Max events to return (default: 1000)

**Example:**
```
GET /api/v1/events/logs?timeRange=30&severity=Error&sortBy=Date&sortOrder=desc
```

**Response:**
```json
{
  "status": "success",
  "timeRange": {
    "earliest": "2026-01-16T14:45:00.000Z",
    "latest": "2026-01-16T15:15:00.000Z",
    "minutes": 30
  },
  "filters": { ... },
  "sorting": { ... },
  "totalCount": 245,
  "requestedCount": 1000,
  "logs": [ ... ]
}
```

### GET /api/v1/events/status
App status and capabilities endpoint.

**Response:**
```json
{
  "status": "healthy",
  "appName": "WebHost Realtime Events",
  "appVersion": "1.0.0",
  "features": {
    "timeRangeFiltering": true,
    "textSearch": true,
    "categoryFiltering": true,
    "sortable": true,
    "exportCSV": true,
    "enhancedLogFormat": true
  },
  "logFile": {
    "exists": true,
    "sizeMB": 15.3
  },
  "defaultTimeRange": 15,
  "maxEvents": 10000
}
```

## Architecture

### Component Location
- **Frontend**: `public/elements/realtime-events/component.js`
- **React Component**: `RealtimeEventsCard`
- **Global Registration**: `window.cardComponents['realtime-events']`

### Backend Integration
- Uses `Read-PSWebHostLog` from PSWebHost_Support module
- Reads from `Logs/PSWebHost.log` with automatic format detection
- Supports both 8-column (legacy) and 12-column (enhanced) formats

### Auto-Refresh
- Polls `/api/v1/events/logs` every 5 seconds when enabled
- Automatically pauses on user interaction
- Preserves selections across refreshes

## Usage

### Basic Monitoring
1. Open **Real-time Events** from the main menu
2. View last 15 minutes of logs by default
3. Auto-refresh keeps view current

### Troubleshooting Specific Issues
1. Select appropriate time range
2. Enter severity filter (e.g., "Error")
3. Optionally filter by category or source
4. Sort by time to see chronological sequence

### Auditing User Activity
1. Enter User ID in filter
2. Expand time range as needed
3. Export selected logs to CSV for analysis

### Monitoring Long Operations
1. Filter by ActivityName or Source
2. View PercentComplete column
3. Watch progress updates in real-time

## Migration from Old Event Stream

The previous `/api/v1/ui/elements/event-stream` endpoint provided basic event viewing from `$Global:LogHistory`. This app provides:

1. **File-based log reading** instead of memory buffer (more reliable, persistent)
2. **Time range controls** instead of just "last N events"
3. **Enhanced filtering** with dedicated fields for common searches
4. **Sortable columns** for better analysis
5. **Support for new 12-column log format** with Source, Activity, Progress, etc.

The old endpoint remains available for backwards compatibility but is deprecated in favor of this app.

## Performance

- **Fast queries**: Indexes on time range for quick filtering
- **Efficient parsing**: Auto-detects log format to avoid unnecessary processing
- **Smart refresh**: Only updates when visible and enabled
- **Lazy rendering**: Large result sets render smoothly

## Security

- **Authentication required**: All endpoints require `authenticated` role
- **Session-aware**: Filters can be user-specific
- **No write access**: Read-only view of logs
- **Sanitized output**: Prevents injection attacks

## Version History

### 1.0.0 (2026-01-16)
- Initial release
- Time range filtering (5 min to 24 hours)
- Custom date/time range selection
- Advanced filtering (category, severity, source, user, session)
- Sortable columns
- CSV/TSV export
- Column visibility toggle
- Word wrap option
- Auto-refresh with pause
- Enhanced 12-column log format support
- Backwards compatible with 8-column format
