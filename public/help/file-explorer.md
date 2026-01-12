# File Explorer

The File Explorer card provides a web-based interface for browsing and managing files on the server.

## Features

- **Directory Navigation**: Browse directories and subdirectories
- **File Preview**: View file contents (text files, images)
- **File Operations**: Upload, download, rename, and delete files
- **Path Breadcrumbs**: Easy navigation with clickable path components

## Supported Operations

| Operation | Description | Requirements |
|-----------|-------------|--------------|
| Browse | Navigate directories | Read permission |
| Download | Download files | Read permission |
| Upload | Upload new files | Write permission |
| Delete | Remove files/folders | Delete permission |
| Rename | Rename files/folders | Write permission |

## Security

- File access is restricted to configured paths
- Path traversal attacks are blocked
- All operations are logged

## Configuration

The file explorer's base path and permissions can be configured in the server settings.

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Enter` | Open selected item |
| `Backspace` | Go to parent directory |
| `Delete` | Delete selected item |
| `F2` | Rename selected item |
