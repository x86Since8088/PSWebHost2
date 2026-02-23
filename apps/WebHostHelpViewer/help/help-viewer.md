# Help Viewer

A markdown-based documentation viewer for PSWebHost.

## Features

- **Markdown Rendering**: Full markdown support with syntax highlighting
- **Dynamic Loading**: Load help files on demand
- **Search Capability**: Find documentation quickly
- **Multiple Locations**: Searches public/help, docs/, and app-specific help directories

## Usage

### View Help Content

The Help Viewer automatically renders markdown files from various locations:

```
public/help/
docs/
apps/{AppName}/help/
apps/{AppName}/docs/
```

### Loading a Help File

Call the endpoint with a file parameter:

```
GET /apps/WebHostHelpViewer/cards/help-viewer?file=path/to/file.md
```

**Example:**
```
GET /apps/WebHostHelpViewer/cards/help-viewer?file=architecture.md
```

### Security

- Path traversal is prevented (`..` sequences are removed)
- Files must exist in authorized directories
- Only `.md` files are recommended

## API Response

### Card Metadata (No Parameters)

When called without parameters, returns card metadata:

```json
{
  "component": "help-viewer",
  "scriptPath": "/apps/WebHostHelpViewer/public/elements/help-viewer/component.js",
  "stylePath": "/apps/WebHostHelpViewer/public/elements/help-viewer/style.css",
  "title": "Help Viewer",
  "width": 12,
  "height": 600,
  "features": {
    "resize": true,
    "minimize": true
  }
}
```

### Help Content (With File Parameter)

When called with `?file=path.md`, returns markdown content:

```json
{
  "status": "success",
  "file": "help-viewer.md",
  "content": "# Markdown Content...",
  "path": "/full/path/to/file.md"
}
```

## Error Handling

### File Not Found (404)
```json
{
  "status": "error",
  "message": "Help file not found: filename.md",
  "searched": [
    "/path1/filename.md",
    "/path2/filename.md"
  ]
}
```

### Read Error (500)
```json
{
  "status": "error",
  "message": "Error reading help file: {error details}"
}
```

## Creating Help Documentation

### For Core Features

Place files in:
```
public/help/{topic}.md
docs/{topic}.md
```

### For Apps

Place files in:
```
apps/{AppName}/help/{topic}.md
apps/{AppName}/docs/{topic}.md
```

### Markdown Best Practices

- Use descriptive headings (`#`, `##`, `###`)
- Include code examples with language tags
- Add navigation links where appropriate
- Keep files focused on single topics
- Use relative links for cross-references

## Integration

The Help Viewer integrates with the PSWebHost card system and can be embedded in other views or opened as a standalone card.

### Opening via JavaScript

```javascript
// Open help viewer card
window.psweb.loadCard('/apps/WebHostHelpViewer/cards/help-viewer?file=topic.md');
```

### Opening via PowerShell

```powershell
# Launch help viewer card
Launch-DebugCard -CardUrl '/apps/WebHostHelpViewer/cards/help-viewer' -Params @{ file = 'topic.md' }
```

## Available Help Topics

- architecture.md - System architecture overview
- help-viewer.md - This file
- [Add more topics as needed]

## Troubleshooting

### "Help file not found"

**Solution**: Check that the file exists in one of the searched directories. The error response includes all paths that were checked.

### Markdown Not Rendering

**Solution**: Ensure the file has valid markdown syntax. Check for malformed headers, code blocks, or links.

### Access Denied

**Solution**: Verify authentication and that the file is in an authorized directory.

## Support

For issues or feature requests, contact your PSWebHost administrator or check the system logs.

---

**App**: WebHostHelpViewer v1.0.0
**Last Updated**: 2026-02-02
