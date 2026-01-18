# Content-Type Aware Card Loading

**Date:** 2026-01-17
**Status:** ✅ Implemented

---

## Overview

The card loading system now automatically detects and handles different content types based on HTTP Content-Type headers. This enables direct HTML injection, proper title handling, and better support for diverse endpoint types.

---

## Key Features

### 1. Content-Type Detection

The system now checks the `Content-Type` header from endpoint responses:

- **text/html** - HTML content injected directly into cards
- **application/json** - Standard component metadata (scriptPath)
- **application/javascript** - Direct JavaScript component files

### 2. HTML Injection

When an endpoint returns `Content-Type: text/html`:

- HTML is injected directly into the card
- No React component loading needed
- Full HTML page displayed within card
- Styles and scripts from HTML are preserved

### 3. Smart Title Extraction

Card titles are automatically determined using this priority:

1. **HTML `<title>` tag** - Extracted from HTML content
2. **Metadata title** - From JSON response `{ title: "...", ... }`
3. **Menu title** - From the menu item that opened the card
4. **URL path** - Last segment of the URL as fallback

**Format for HTML content:** `HTML - [extracted title]`

### 4. Direct File URL Support

You can now use direct URLs to files in menu items:

- **`.html` files** - Displayed as HTML content
- **`.js` files** - Loaded as React components

**Example:**
```yaml
- Name: Help Page
  url: /public/help/user-guide.html

- Name: Chart Component
  url: /public/elements/chart/component.js
```

### 5. Content-Type Logging

All content types are automatically logged to the server:

```javascript
window.logToServer('Info', 'ContentType',
    `Endpoint ${url} returned HTML`,
    { elementId: id, contentType: 'text/html', hasTitle: true }
);
```

This helps administrators track what content type each endpoint returns.

---

## Technical Implementation

### Content-Type Flow

```
┌─────────────────┐
│  openCard(url)  │
└────────┬────────┘
         │
         ▼
┌──────────────────────────┐
│ loadComponentScript()    │
│ - Fetch endpoint         │
│ - Check Content-Type     │
└────────┬─────────────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌──────┐  ┌────────┐
│ HTML │  │  JSON  │
│      │  │ +      │
│      │  │ .js    │
└──┬───┘  └───┬────┘
   │          │
   │          ▼
   │    ┌──────────────┐
   │    │ Load Script  │
   │    │ Transform    │
   │    │ Register     │
   │    └──────────────┘
   │
   ▼
┌───────────────────┐
│ Card Component    │
│ - Inject HTML OR  │
│ - Render Component│
└───────────────────┘
```

### Code Changes

#### 1. Enhanced `loadComponentScript()`

**Location:** `public/psweb_spa.js` (lines 1565-1795)

```javascript
const loadComponentScript = async (elementId, explicitPath = null, endpointUrl = null) => {
    // ...

    // Get Content-Type header
    contentType = metadataRes.headers.get('Content-Type') || 'application/json';

    // Handle HTML responses directly
    if (contentType.includes('text/html')) {
        htmlContent = await metadataRes.text();

        // Extract title from HTML
        const titleMatch = htmlContent.match(/<title[^>]*>(.*?)<\/title>/i);
        htmlTitle = titleMatch ? titleMatch[1] : null;

        return {
            success: true,
            type: 'html',
            contentType: contentType,
            htmlContent: htmlContent,
            htmlTitle: htmlTitle
        };
    }

    // Handle JSON metadata (standard component pattern)
    const metadata = await metadataRes.json();
    if (metadata.scriptPath) {
        componentPath = metadata.scriptPath;
    }

    // Handle direct .html or .js files
    if (componentPath.endsWith('.html')) {
        // Load as HTML
    } else {
        // Load as JavaScript component
    }
};
```

#### 2. HTML Rendering in Card Component

**Location:** `public/psweb_spa.js` (lines 978-993)

```javascript
// Check if there's HTML content to inject directly
if (element.htmlContent) {
    cardContent = (
        <div
            style={{
                width: '100%',
                height: '100%',
                overflow: 'auto',
                padding: 0,
                margin: 0
            }}
            dangerouslySetInnerHTML={{ __html: element.htmlContent }}
        />
    );
}
```

#### 3. Title Generation

**Location:** `public/psweb_spa.js` (lines 1825-1831)

```javascript
// Determine final title based on content type
let finalTitle = title;
if (loadResult.success && loadResult.type === 'html') {
    const htmlTitlePart = loadResult.htmlTitle || title || elementUrl.split('/').pop() || 'Content';
    finalTitle = `HTML - ${htmlTitlePart}`;
}
```

---

## Usage Examples

### Example 1: HTML Endpoint

**Endpoint:** `routes/api/v1/ui/elements/dashboard/get.ps1`

```powershell
param($Context, $Request, $Response, $sessiondata)

$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>System Dashboard</title>
    <style>
        body { font-family: Arial; padding: 20px; }
        .metric { margin: 10px; padding: 15px; background: #f0f0f0; }
    </style>
</head>
<body>
    <h1>Dashboard</h1>
    <div class="metric">CPU: 45%</div>
    <div class="metric">Memory: 2.5GB / 8GB</div>
</body>
</html>
"@

$Response.ContentType = "text/html"
$buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
$Response.OutputStream.Write($buffer, 0, $buffer.Length)
$Response.Close()
```

**Result:**
- Card title: `HTML - System Dashboard`
- HTML content injected directly
- No component script needed

### Example 2: Direct HTML File

**Menu Item:** `main-menu.yaml`

```yaml
- Name: User Guide
  url: /public/help/user-guide.html
  roles:
    - authenticated
  tags:
    - help
    - documentation
```

**Result:**
- Loads `/public/help/user-guide.html` directly
- Title extracted from `<title>` tag
- Card displays full HTML page

### Example 3: Direct Component File

**Menu Item:**

```yaml
- Name: Chart Viewer
  url: /public/elements/chart-viewer/component.js
  roles:
    - authenticated
```

**Result:**
- Loads and transforms JavaScript file
- Registers as React component
- Normal component rendering

### Example 4: Standard JSON Metadata

**Endpoint Response:**

```json
{
  "scriptPath": "/apps/MyApp/public/elements/my-component/component.js",
  "title": "My Component",
  "version": "1.0.0"
}
```

**Result:**
- Loads script from `scriptPath`
- Uses `title` as card title
- Standard component workflow

---

## Menu YAML Enhancement

Menu items can now optionally include content-type hints:

```yaml
- Name: Apps Manager
  url: /apps/WebHostAppManager/api/v1/ui/elements/apps-manager
  roles:
    - site_admin
  tags:
    - apps
    - management
  # Optional: Document observed content type
  contentType: text/html
  # Optional: Add notes about the endpoint
  notes: Returns full HTML page with app grid
```

**Benefits:**
- Documentation for developers
- Planning aid when designing menu structure
- Quick reference for content type expectations

**Note:** The `contentType` field is purely informational and not used by the loading system. It serves as documentation.

---

## Content-Type Logging

All content-type observations are logged to the server automatically:

### Log Categories

1. **HTML Endpoint:**
   ```
   Category: ContentType
   Message: Endpoint /api/v1/ui/elements/dashboard returned HTML
   Data: { elementId: 'dashboard', contentType: 'text/html', hasTitle: true }
   ```

2. **Direct HTML File:**
   ```
   Category: ContentType
   Message: Direct HTML file loaded: /public/help/guide.html
   Data: { elementId: 'help-guide', contentType: 'text/html', hasTitle: true }
   ```

3. **JavaScript Component:**
   ```
   Category: ContentType
   Message: JavaScript component loaded: /public/elements/chart/component.js
   Data: { elementId: 'chart', contentType: 'application/javascript' }
   ```

4. **JSON Metadata:**
   ```
   Category: ContentType
   Message: Endpoint /api/v1/ui/elements/system-log returned JSON with scriptPath
   Data: { elementId: 'system-log', contentType: 'application/json', scriptPath: '...' }
   ```

### Viewing Logs

Access via Debug Variables endpoint:
```
/api/v1/debug/vars
```

Look for `PSWebHostLogs` or server console output.

---

## File Extension Handling

### Supported Extensions

| Extension | Content-Type | Handling |
|-----------|-------------|----------|
| `.html` | text/html | Direct HTML injection |
| `.htm` | text/html | Direct HTML injection |
| `.js` | application/javascript | Babel transform, React component |
| `.jsx` | application/javascript | Babel transform, React component |
| (none) | *from headers* | Content-Type header determines handling |

### Extension Priority

1. **Content-Type header** (highest priority)
2. **File extension**
3. **Default assumption** (application/json)

---

## Security Considerations

### HTML Injection Safety

HTML content uses `dangerouslySetInnerHTML`:

**Safe scenarios:**
- Endpoints you control
- Trusted content sources
- Internal tools and dashboards

**Unsafe scenarios:**
- User-generated content (without sanitization)
- External/untrusted sources
- Content with unknown origin

**Recommendation:** Only use HTML injection for internal, trusted endpoints.

### Content Security Policy

If your PSWebHost instance has CSP headers, ensure they allow:
- Inline scripts (for injected HTML with `<script>` tags)
- Inline styles (for injected HTML with `<style>` tags)

### Script Execution

Injected HTML can execute JavaScript:
```html
<script>
    console.log('This will execute!');
    // Can access parent window, DOM, etc.
</script>
```

**Note:** Scripts in injected HTML run in the same context as the main app.

---

## Troubleshooting

### Issue: HTML Not Displaying

**Symptoms:**
- Card shows "Loading component..."
- HTML content not visible

**Solutions:**
1. Check endpoint returns `Content-Type: text/html`
2. Verify HTML is valid
3. Check browser console for errors
4. Ensure endpoint returns 200 status

### Issue: Title Shows as "HTML - undefined"

**Cause:** No `<title>` tag in HTML

**Solutions:**
1. Add `<title>` tag to HTML:
   ```html
   <head>
       <title>My Page Title</title>
   </head>
   ```

2. Pass title in menu item:
   ```yaml
   - Name: Dashboard
     url: /api/v1/ui/elements/dashboard
   ```

### Issue: Styles Not Applying

**Cause:** CSS specificity or scope issues

**Solutions:**
1. Use more specific selectors
2. Add `!important` flags (sparingly)
3. Inline styles for critical styling
4. Check browser DevTools for CSS conflicts

### Issue: Scripts Not Executing

**Cause:** CSP or script placement

**Solutions:**
1. Check Content Security Policy headers
2. Place scripts at end of `<body>`
3. Use inline event handlers carefully
4. Check browser console for errors

---

## Best Practices

### For HTML Endpoints

1. **Include Complete HTML:**
   ```html
   <!DOCTYPE html>
   <html>
   <head>
       <title>Page Title</title>
       <style>/* styles */</style>
   </head>
   <body>
       <!-- content -->
       <script>/* scripts */</script>
   </body>
   </html>
   ```

2. **Use Relative Units:**
   - Use `%`, `vh`, `vw` for sizing
   - Avoid fixed pixel dimensions
   - Card size is dynamic

3. **Test Responsiveness:**
   - Cards can be resized
   - Test at different sizes
   - Use flexible layouts

4. **Namespace CSS:**
   ```css
   .my-dashboard { /* component-specific */ }
   .my-dashboard .metric { /* scoped */ }
   ```

5. **Return Proper Content-Type:**
   ```powershell
   $Response.ContentType = "text/html"
   ```

### For Menu Items

1. **Document Content Type:**
   ```yaml
   - Name: My Component
     url: /api/v1/ui/elements/my-component
     contentType: text/html  # For reference
     notes: Returns full HTML dashboard
   ```

2. **Use Clear Names:**
   ```yaml
   # Good
   - Name: System Dashboard
     url: /api/v1/ui/elements/dashboard

   # Less clear
   - Name: Dashboard
     url: /some/endpoint
   ```

3. **Add Descriptive Hover Text:**
   ```yaml
   - Name: Apps Manager
     url: /apps/WebHostAppManager/api/v1/ui/elements/apps-manager
     hover_description: Manage installed PSWebHost apps - view status, configuration, and metadata
   ```

---

## Future Enhancements

Potential improvements:

1. **Auto-detect Content-Type from Menu:**
   - Pre-fetch URL to determine content type
   - Cache content type in menu data
   - Show icon/badge indicating type

2. **Content-Type Icons:**
   - 📄 for HTML pages
   - ⚙️ for JavaScript components
   - 📊 for data endpoints

3. **Content Sanitization:**
   - Option to sanitize untrusted HTML
   - Remove potentially dangerous scripts
   - CSP enforcement per-card

4. **Template Support:**
   - HTML templates with variable substitution
   - Mustache/Handlebars-style templates
   - Server-side rendering

5. **Live Reload:**
   - Detect HTML content changes
   - Auto-refresh HTML cards
   - WebSocket-based updates

---

## Related Documentation

- [Card Error Display](./CARD_ERROR_DISPLAY.md) - Error handling in cards
- [Card Pause and Contrast](./CARD_PAUSE_AND_CONTRAST.md) - Card control features
- [High Contrast Auto-Fix](./HIGH_CONTRAST_AUTO_FIX.md) - Accessibility features

---

## Summary

✅ **Content-Type aware card loading implemented**

**Key Capabilities:**
- Automatic Content-Type detection from headers
- Direct HTML injection for `text/html` responses
- Smart title extraction from HTML/metadata/URL
- Support for direct `.html` and `.js` file URLs
- Comprehensive content-type logging
- Flexible loading strategy

**Benefits:**
- Simplified HTML endpoint creation
- No React component needed for simple pages
- Better title management
- Enhanced debugging with logging
- Flexible content delivery

---

**Last Updated:** 2026-01-17
**Author:** PSWebHost Development Team
**Status:** ✅ Production Ready
