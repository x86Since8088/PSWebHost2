# Real-time Events

The Event Stream card provides real-time visibility into system events and activities.

## Features

- **Live Event Feed**: Events appear automatically as they occur
- **Time-based Filtering**: Filter events by date/time range
- **Text Search**: Search across event data
- **Event Count Control**: Limit the number of displayed events

## Query Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `filter` | Text search filter | `filter=error` |
| `count` | Maximum events to show | `count=100` |
| `earliest` | Start date/time | `earliest=2024-01-01T00:00:00` |
| `latest` | End date/time | `latest=2024-12-31T23:59:59` |

## Event Properties

Each event contains:
- **Date**: When the event occurred
- **State**: Current state of the event
- **UserID**: User associated with the event
- **Provider**: Source system or component
- **Data**: Additional event details

## Authentication Required

This card requires authentication. You must be logged in with the `authenticated` role.

## Troubleshooting

If no events appear:
1. Check that you are logged in
2. Verify the WebHost is running and processing requests
3. Check the log tail job status in Admin Tools > Job Status
