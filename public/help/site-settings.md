# Site Settings

The Site Settings component provides centralized configuration management for the PSWebHost application.

## Features

### General Settings
- **Site Name**: The display name of your application
- **Site Description**: A brief description shown in metadata
- **Default Language**: The primary language for the interface
- **Timezone**: Server timezone for date/time display

### Security Settings
- **Session Timeout**: Duration before inactive sessions expire
- **Max Login Attempts**: Failed login attempts before lockout
- **Require HTTPS**: Force secure connections
- **CORS Enabled**: Allow cross-origin requests

### Appearance Settings
- **Theme**: Light or dark mode preference
- **Accent Color**: Primary color for UI elements
- **Logo URL**: Path to custom logo image

### Performance Settings
- **Cache Enabled**: Toggle response caching
- **Cache Duration**: How long to cache responses (seconds)
- **Compression Enabled**: Enable gzip/deflate compression
- **Max Request Size**: Maximum upload size in bytes

## Access
This component requires `site_admin`, `system_admin`, or `admin` role.
