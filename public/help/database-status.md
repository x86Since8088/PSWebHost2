# Database Status

Monitor and maintain the SQLite database that powers PSWebHost.

## Overview

Displays real-time information about database health, storage usage, and performance metrics.

## Features

### Status Indicators
- **Healthy**: All systems operational
- **Warning**: Performance degradation detected
- **Error**: Database issues requiring attention

### Information Displayed
- Database type and version
- File location and size
- Last backup timestamp
- Active connections

### Table Statistics
View all database tables with:
- Row counts
- Storage size
- Growth trends

### Performance Metrics
- Average query execution time
- Queries per second
- Cache hit rate
- Connection pool status

## Maintenance Actions

### Backup Now
Create an immediate database backup.

### Vacuum
Reclaim unused space and optimize file size.

### Analyze
Update query planner statistics for better performance.

## Access
This component requires `site_admin`, `system_admin`, or `admin` role.
