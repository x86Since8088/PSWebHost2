# WebHost Realtime Events - Architecture

## File Structure

### Component Files (Frontend)

**Location**: `public/elements/realtime-events/component.js`

- This is where the React component **MUST** be located
- The PSWebHost SPA system loads components from `/public/elements/{elementId}/component.js`
- Even though this is an app, the component must be in the root public directory
- The app's copy at `apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js` is the source
- The public copy is deployed/copied during app installation

### API Endpoints (Backend)

**App Configuration**: `apps/WebhostRealtimeEvents/app.yaml`
- `routePrefix: /api/v1/events` - All app routes are prefixed with this

**App Routes**: `apps/WebhostRealtimeEvents/routes/`
- `logs/get.ps1` → `/api/v1/events/logs` (Main log retrieval)
- `status/get.ps1` → `/api/v1/events/status` (App status)

**Route Mapping**:
```
routePrefix + route file path = final URL
/api/v1/events + /logs = /api/v1/events/logs
/api/v1/events + /status = /api/v1/events/status
```

**UI Wrapper**: `routes/api/v1/ui/elements/realtime-events/get.ps1`
- Provides metadata for the card system
- Maps the menu URL to the component ID

### Menu Integration

**File**: `routes/api/v1/ui/elements/main-menu/main-menu.yaml`

```yaml
- url: /api/v1/ui/elements/realtime-events
  Name: Real-time Events
```

The URL format `/api/v1/ui/elements/{elementId}` tells the system:
1. This is a UI element/card
2. Look for component at `/public/elements/{elementId}/component.js`
3. The `elementId` is `realtime-events`

## Component Loading Flow

1. User clicks "Real-time Events" in menu
2. SPA extracts `elementId` from URL: `realtime-events`
3. SPA loads `/public/elements/realtime-events/component.js`
4. Babel transforms JSX to JavaScript
5. Component registers itself: `window.cardComponents['realtime-events'] = RealtimeEventsCard`
6. SPA renders the component in a card

## API Request Flow

1. Component makes request to `/api/v1/events/logs?timeRange=15`
2. PSWebHost routes to `apps/WebhostRealtimeEvents/routes/api/v1/logs/get.ps1`
3. Script calls `Read-PSWebHostLog` to query log file
4. Filters, sorts, and formats data
5. Returns JSON response to component
6. Component updates UI with log data

## Data Flow

```
User Action
    ↓
React Component (public/elements/realtime-events/component.js)
    ↓
HTTP GET /api/v1/events/logs
    ↓
Route Handler (apps/WebhostRealtimeEvents/routes/api/v1/logs/get.ps1)
    ↓
Read-PSWebHostLog (modules/PSWebHost_Support/PSWebHost_Support.psm1)
    ↓
Log File (Logs/PSWebHost.log)
    ↓
Filtered/Sorted Data
    ↓
JSON Response
    ↓
React Component (state update)
    ↓
UI Update
```

## Why Two Component Locations?

**Source**: `apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js`
- Part of the app's source code
- Versioned with the app
- Can be updated via app updates

**Deployed**: `public/elements/realtime-events/component.js`
- Where the SPA actually loads from
- Required by PSWebHost's component loading system
- Should be copied during app installation

**Note**: In development, manually copy changes:
```powershell
cp apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js public/elements/realtime-events/component.js
```

In production, app installation should handle this automatically.

## Component Registration

The component registers itself in the global registry:

```javascript
window.cardComponents['realtime-events'] = RealtimeEventsCard;
```

The key `'realtime-events'` must match:
- The `elementId` in the URL
- The directory name in `public/elements/`
- The component filename path

## State Management

### Component State
- `logs` - Array of log entries
- `autoRefresh` - Boolean for auto-refresh toggle
- `timeRange` - Selected time range (minutes)
- `filters` - Various filter values
- `sortBy` / `sortOrder` - Sort configuration
- `visibleColumns` - Column visibility settings
- `selectedLogs` - Set of selected log IDs for export

### Global State
None - component is self-contained

### Server State
- `Logs/PSWebHost.log` - Persistent log file
- `Read-PSWebHostLog` - Reads and parses logs on-demand
- No server-side caching (file-based, always fresh)

## Performance Considerations

### Client-Side
- Auto-refresh interval: 5 seconds
- Debouncing: None (small payloads, fast responses)
- Rendering: React handles efficiently (<1000 rows default)

### Server-Side
- File I/O: Streaming read with line limits
- Parsing: Stop at requested count
- Filtering: Early termination when count reached
- Sorting: In-memory (efficient for typical result sizes)

### Network
- Typical payload: 50-200 KB for 1000 events
- Compression: Gzip via HTTP
- Caching: None (real-time data)

## Security

### Authentication
All endpoints require `authenticated` role:
```json
{"Allowed_Roles":["authenticated"]}
```

### Authorization
- Read-only access to logs
- No write operations
- No log deletion
- No system modification

### Data Exposure
- Logs may contain sensitive information
- All fields are visible to authenticated users
- Consider row-level security for multi-tenant scenarios

## Testing

### Unit Tests
Location: `apps/WebhostRealtimeEvents/tests/twin/`

- `routes/api/v1/logs/get.Tests.ps1` - API endpoint tests
- `routes/api/v1/status/get.Tests.ps1` - Status endpoint tests

### Manual Testing
1. Open menu → Real-time Events
2. Verify component loads
3. Check default 15-minute time range
4. Test filters (category, severity, source, etc.)
5. Test sorting (click column headers)
6. Test time range selection
7. Test export (CSV/TSV)
8. Test auto-refresh toggle

### Browser Console Testing
```javascript
// Test API directly
fetch('/api/v1/events/logs?timeRange=30&severity=Error')
  .then(r => r.json())
  .then(d => console.log(d));

// Check component registration
console.log(window.cardComponents['realtime-events']);

// Force re-fetch
const component = document.querySelector('.realtime-events-container');
// Component has no exposed API, use UI buttons
```

## Troubleshooting

### Component Not Loading
**Symptom**: Menu click does nothing or shows error
**Check**:
1. Is component at `public/elements/realtime-events/component.js`?
2. Check browser console for 404 or syntax errors
3. Verify JSX syntax is valid (Babel can transform it)

### No Logs Displayed
**Symptom**: Component loads but shows "No logs found"
**Check**:
1. Does `Logs/PSWebHost.log` exist?
2. Are there logs in the selected time range?
3. Try increasing time range to 24 hours
4. Check filters - remove all filters to see all logs

### API Errors
**Symptom**: 500 errors or PowerShell exceptions
**Check**:
1. Is `Read-PSWebHostLog` available? (PSWebHost_Support module)
2. Check `Logs/PSWebHost.log` for error details
3. Verify log file permissions
4. Test endpoint directly: `curl http://localhost:8080/api/v1/events/logs`

### Sorting Not Working
**Symptom**: Clicking headers doesn't sort
**Check**:
1. Are query parameters being sent? (Check Network tab)
2. Is backend returning sorted data?
3. Check `sortBy` and `sortOrder` in API response

### Filters Not Working
**Symptom**: Filters don't reduce results
**Check**:
1. Are filters being sent to API? (Check Network tab)
2. Is backend applying filters? (Check API response)
3. Try exact match vs wildcard patterns
4. Check case sensitivity

## Future Enhancements

Possible improvements:
- WebSocket/SSE for true real-time streaming
- Server-side aggregation (counts by severity, category, etc.)
- Saved filter presets
- Alert rules (email/webhook on specific events)
- Log export to external systems (syslog, ELK, Splunk)
- Multi-node log aggregation
- Full-text search indexing
