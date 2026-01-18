# Migration from Old Event Stream to WebHost Realtime Events

**Date**: 2026-01-16
**Version**: 1.0.0

## Overview

The Real-time Events card has been migrated from a simple UI element to a full-featured PSWebHost app with enhanced capabilities.

## What Changed

### Old Implementation
- **Location**: `public/elements/event-stream/component.js`
- **API**: `/api/v1/ui/elements/event-stream`
- **Data Source**: `$Global:LogHistory` (in-memory buffer)
- **Capabilities**: Basic event listing with simple text filter

### New Implementation
- **App Location**: `apps/WebhostRealtimeEvents/`
- **Component**: `public/elements/realtime-events/component.js`
- **API**: `/api/v1/events/logs`
- **Data Source**: `Logs/PSWebHost.log` via `Read-PSWebHostLog`
- **Enhanced Capabilities**:
  - ✨ Time range filtering (5 min to 24 hours)
  - ✨ Custom date/time range selection
  - ✨ Advanced filtering (category, severity, source, user, session)
  - ✨ Sortable columns (click headers to sort)
  - ✨ Enhanced 12-column log format support
  - ✨ Improved CSV/TSV export
  - ✨ Better column management
  - ✨ More reliable data (file-based vs memory buffer)

## Migration Steps Performed

### 1. Created App Structure
```
apps/WebhostRealtimeEvents/
├── app.yaml
├── README.md
├── MIGRATION_NOTES.md
├── routes/
│   └── api/
│       └── v1/
│           ├── logs/
│           │   ├── get.ps1
│           │   └── get.security.json
│           └── status/
│               ├── get.ps1
│               └── get.security.json
├── public/
│   └── elements/
│       └── realtime-events/
│           └── component.js
└── tests/
    └── twin/
        └── routes/
            └── api/
                └── v1/
                    ├── logs/
                    │   └── get.Tests.ps1
                    └── status/
                        └── get.Tests.ps1
```

### 2. Enhanced API Endpoint
**New**: `/api/v1/events/logs`

Replaces the old `/api/v1/ui/elements/event-stream` with:
- Time range parameters (`timeRange`, `earliest`, `latest`)
- Advanced filter parameters (`category`, `severity`, `source`, `userID`, `sessionID`, `activityName`, `runspaceID`)
- Sort parameters (`sortBy`, `sortOrder`)
- Structured response with metadata

### 3. Updated Menu Configuration
**File**: `routes/api/v1/ui/elements/main-menu/main-menu.yaml`

Changed:
```yaml
# Old
- url: /api/v1/ui/elements/event-stream
  Name: Real-time Events

# New
- url: /api/v1/ui/elements/realtime-events
  Name: Real-time Events
```

### 4. Created UI Wrapper
**File**: `routes/api/v1/ui/elements/realtime-events/get.ps1`

Provides metadata for the card system to load the component.

### 5. Enhanced React Component
**Features Added**:
- Time range dropdown (5 min, 15 min, 30 min, 1 hr, 4 hrs, 24 hrs, custom)
- Custom date/time picker for precise time ranges
- Separate filter inputs for category, severity, source, user, session
- Click-to-sort on column headers
- Sort indicators (▲/▼) on active column
- Severity color coding
- Progress percentage display
- Loading indicator during fetch
- Better error handling

### 6. Integration with Enhanced Logging
The app fully supports the new 12-column log format:
- **Source**: Script/function path (auto-detected)
- **ActivityName**: Function name (auto-detected)
- **PercentComplete**: Progress tracking
- **UserID**: Session user (auto-detected)
- **SessionID**: Session ID (auto-detected)
- **RunspaceID**: PowerShell runspace (auto-detected)

### 7. Created Comprehensive Tests
- `/api/v1/events/logs` - 30+ test cases
- `/api/v1/events/status` - Status endpoint validation
- Authentication, filtering, sorting, time range tests

## Backwards Compatibility

### Old Endpoint Status
The old `/api/v1/ui/elements/event-stream` endpoint is **deprecated but still functional**.

**Recommendation**: Update any custom integrations to use `/api/v1/events/logs` for better functionality.

### Log Format Compatibility
The app automatically detects and handles both:
- **8-column format** (legacy): UTCTime, LocalTime, Severity, Category, Message, SessionID, UserID, Data
- **12-column format** (enhanced): Adds Source, ActivityName, PercentComplete, RunspaceID

## Default Behavior Changes

| Feature | Old Behavior | New Behavior |
|---------|--------------|--------------|
| Data Source | `$Global:LogHistory` buffer | `Logs/PSWebHost.log` file |
| Default Range | Last 1000 events | Last 15 minutes |
| Time Filter | None | Selectable range |
| Sorting | None | Click column headers |
| Advanced Filters | Text search only | Category, Severity, Source, User, Session |
| Auto-Refresh | 5 seconds | 5 seconds (same) |
| Export | CSV/TSV of selected | CSV/TSV of selected (same) |

## User-Visible Changes

### UI Improvements
1. **Time Range Selector**: Dropdown at top of card
2. **More Filter Inputs**: Dedicated fields for common filters
3. **Sortable Headers**: Click to sort, click again to reverse
4. **Sort Indicator**: Visual arrow showing sort column and direction
5. **Color-Coded Severity**: Errors in red, warnings in orange, etc.
6. **Loading Indicator**: Spinner shows when fetching data
7. **Progress Column**: Shows percentage for long-running operations

### Performance Improvements
1. **File-based querying**: More reliable than memory buffer
2. **Time-indexed filtering**: Faster queries with time range
3. **Server-side filtering**: Less data transferred
4. **Optimized rendering**: Better handling of large result sets

## Developer Notes

### Using the New API

**Basic Query**:
```javascript
fetch('/api/v1/events/logs?timeRange=30')
  .then(res => res.json())
  .then(data => console.log(data.logs));
```

**Advanced Query**:
```javascript
const params = new URLSearchParams({
  timeRange: '60',
  severity: 'Error',
  category: 'Database',
  sortBy: 'Date',
  sortOrder: 'desc',
  count: '100'
});

fetch(`/api/v1/events/logs?${params}`)
  .then(res => res.json())
  .then(data => {
    console.log(`Found ${data.totalCount} errors in last hour`);
    data.logs.forEach(log => console.log(log.Message));
  });
```

### Custom Time Range
```javascript
const params = new URLSearchParams({
  earliest: '2026-01-16T10:00:00.000Z',
  latest: '2026-01-16T12:00:00.000Z',
  severity: 'Warning'
});

fetch(`/api/v1/events/logs?${params}`)
  .then(res => res.json())
  .then(data => console.log(data));
```

## Testing

Run the twin tests:
```powershell
# Test logs endpoint
Invoke-Pester apps/WebhostRealtimeEvents/tests/twin/routes/api/v1/logs/get.Tests.ps1

# Test status endpoint
Invoke-Pester apps/WebhostRealtimeEvents/tests/twin/routes/api/v1/status/get.Tests.ps1
```

## Rollback Plan

If issues arise, the old endpoint remains available:

1. Revert menu configuration:
   ```yaml
   - url: /api/v1/ui/elements/event-stream
     Name: Real-time Events (Legacy)
   ```

2. Old component still exists at:
   - Frontend: `public/elements/event-stream/component.js`
   - Backend: `routes/api/v1/ui/elements/event-stream/get.ps1`

## Future Enhancements

Possible future additions:
- [ ] Real-time SSE (Server-Sent Events) streaming
- [ ] Log level statistics/charts
- [ ] Saved filter presets
- [ ] Email/webhook alerts on specific events
- [ ] Log aggregation across multiple PSWebHost nodes
- [ ] Full-text search indexing for faster queries
- [ ] Export to syslog/ELK/Splunk format

## Conclusion

The migration is complete and provides significant improvements:
- ✅ More reliable data source (file vs memory)
- ✅ Better time range control
- ✅ Advanced filtering capabilities
- ✅ Sortable results
- ✅ Enhanced log format support
- ✅ Comprehensive testing
- ✅ Full documentation

Users should see improved functionality with no breaking changes to existing workflows.
