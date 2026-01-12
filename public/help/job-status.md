# Job Status

Monitor background jobs running on the PSWebHost server.

## Overview

The Job Status component displays all PowerShell background jobs currently running or recently completed on the server.

## Features

### Job List
View all background jobs with:
- Job ID
- Job Name
- Current State (Running, Completed, Failed, Stopped)
- Start Time
- End Time
- Running Duration

### Job States
- **Running**: Job is currently executing
- **Completed**: Job finished successfully
- **Failed**: Job encountered an error
- **Stopped**: Job was manually stopped

## Information Displayed

| Column | Description |
|--------|-------------|
| Id | Unique job identifier |
| Name | Job name or script name |
| State | Current execution state |
| HasMoreData | Whether output data is available |
| StartTime | When the job began |
| EndTime | When the job completed |
| RunningTime | Duration in hh:mm:ss format |

## Access

This component requires `admin`, `debug`, `site_admin`, or `system_admin` role.

## Notes

- Job data is fetched from the main PSWebHost thread
- Jobs are PowerShell background jobs, not Windows services
- The list auto-refreshes to show current job states
