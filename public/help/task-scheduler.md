# Task Scheduler

Manage scheduled tasks and automated jobs.

## Platform Support

### Windows
Integrates with Windows Task Scheduler for task management.

### Linux  
Manages cron jobs and systemd timers.

## Features

### Task List
View all scheduled tasks with:
- Task name
- Schedule (cron expression or Windows schedule)
- Last run timestamp
- Next scheduled run
- Status (enabled/disabled)
- Last result (success/failed/skipped)

### Schedule Format
Uses cron-style expressions:
```
* * * * *
│ │ │ │ └── Day of week (0-7)
│ │ │ └──── Month (1-12)
│ │ └────── Day of month (1-31)
│ └──────── Hour (0-23)
└────────── Minute (0-59)
```

### Actions
- **Run Now**: Execute a task immediately
- **Edit**: Modify task schedule or command
- **View Logs**: See task execution history
- **Enable/Disable**: Toggle task scheduling

## Common Tasks
- Daily Backup (database and files)
- Log Cleanup (remove old log entries)
- Database Maintenance (vacuum and analyze)
- Certificate Renewal (SSL/TLS updates)

## Access
This component requires `site_admin`, `system_admin`, or `admin` role.
