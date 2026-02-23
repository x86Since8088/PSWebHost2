# Feature Porting Guide: Text/Markdown Toggle

**Feature:** Text/Markdown View Toggle
**Source App:** WebHostHelpViewer
**Target:** Core help-viewer component
**Priority:** Medium
**Complexity:** Low

---

## Overview

The WebHostHelpViewer app includes a unique **text/markdown toggle feature** that allows users to switch between rendered markdown and raw text views. This feature is NOT present in the core help-viewer component and should be ported to maintain feature parity and improve usability.

---

## Current Implementation

### Location
- **Component:** `C:\SC\PsWebHost\apps\WebHostHelpViewer\public\elements\help-viewer\component.js`
- **Styles:** `C:\SC\PsWebHost\apps\WebHostHelpViewer\public\elements\help-viewer\style.css`

### Implementation Details

#### 1. State Management (Lines 9-10)
```javascript
const [viewMode, setViewMode] = React.useState('rendered'); // 'rendered' or 'text'
const [markdownItLoaded, setMarkdownItLoaded] = React.useState(false);
```

#### 2. Toolbar UI (Lines 127-166)
```javascript
React.createElement('div', {
    className: 'help-viewer-toolbar',
    style: { /* toolbar styles */ }
},
    React.createElement('span', { style: { fontSize: '13px', color: '#666' } }, 'View Mode:'),
    React.createElement('button', {
        className: viewMode === 'rendered' ? 'active' : '',
        onClick: () => setViewMode('rendered'),
        style: {
            padding: '4px 12px',
            border: '1px solid #ccc',
            background: viewMode === 'rendered' ? '#0078d4' : '#fff',
            color: viewMode === 'rendered' ? '#fff' : '#333',
            borderRadius: '4px',
            cursor: 'pointer',
            fontSize: '13px'
        }
    }, 'Markdown'),
    React.createElement('button', {
        className: viewMode === 'text' ? 'active' : '',
        onClick: () => setViewMode('text'),
        style: { /* similar styles */ }
    }, 'Text')
)
```

#### 3. Conditional Rendering (Lines 178-192)
```javascript
viewMode === 'rendered'
    ? React.createElement('div', {
        className: 'markdown-body',
        dangerouslySetInnerHTML: { __html: renderMarkdown(content) }
    })
    : React.createElement('pre', {
        style: {
            whiteSpace: 'pre-wrap',
            wordBreak: 'break-word',
            fontFamily: 'Consolas, Monaco, monospace',
            fontSize: '13px',
            lineHeight: '1.6',
            margin: 0
        }
    }, content)
```

#### 4. Markdown Rendering (Lines 87-100)
Uses markdown-it library with configuration:
```javascript
const md = markdownit({
    html: true,
    linkify: true,
    typographer: true,
    breaks: true
});
```

---

## Porting Instructions

### Target Files
- **Component:** `C:\SC\PsWebHost\public\elements\help-viewer\component.js`
- **Styles:** `C:\SC\PsWebHost\public\elements\help-viewer\style.css`

### Step-by-Step Port

#### Step 1: Add State Variables
Add to the component's state (near the top of the component):
```javascript
const [viewMode, setViewMode] = React.useState('rendered'); // 'rendered' or 'text'
```

#### Step 2: Load markdown-it Library
The app version uses markdown-it for client-side rendering, but the core version converts on the server.

**Option A:** Continue server-side rendering (simpler, recommended)
- Keep the current server-side conversion in `get.ps1`
- For text mode, still fetch the raw content from the API response
- API already returns both `html` and `content` fields

**Option B:** Switch to client-side rendering (matches app behavior)
- Add markdown-it library loading logic
- Move rendering to client-side
- More consistent with markdown-viewer component

**Recommendation:** Option A is simpler and maintains backward compatibility.

#### Step 3: Update API Response Handling
The core API at `C:\SC\PsWebHost\routes\cards\help-viewer\get.ps1` already returns both:
- `html` (converted markdown)
- `content` (raw markdown)

Ensure both are stored in state:
```javascript
const [htmlContent, setHtmlContent] = React.useState('');
const [rawContent, setRawContent] = React.useState('');

// In fetch handler:
const data = await response.json();
setHtmlContent(data.html || '');
setRawContent(data.content || '');
```

#### Step 4: Add Toolbar
Insert toolbar between the component wrapper and content area:
```javascript
// Toolbar with view mode toggle
React.createElement('div', {
    className: 'help-viewer-toolbar',
    style: {
        display: 'flex',
        alignItems: 'center',
        padding: '8px 16px',
        background: 'var(--bg-secondary, #f5f5f5)',
        borderBottom: '1px solid var(--border-color, #ddd)',
        gap: '8px',
        flexShrink: 0
    }
},
    React.createElement('span', {
        style: { fontSize: '13px', color: 'var(--text-muted, #666)' }
    }, 'View Mode:'),
    React.createElement('button', {
        className: viewMode === 'rendered' ? 'active' : '',
        onClick: () => setViewMode('rendered'),
        style: {
            padding: '4px 12px',
            border: '1px solid var(--border-color, #ccc)',
            background: viewMode === 'rendered' ? 'var(--accent-color, #0078d4)' : 'var(--bg-color, #fff)',
            color: viewMode === 'rendered' ? '#fff' : 'var(--text-color, #333)',
            borderRadius: '4px',
            cursor: 'pointer',
            fontSize: '13px',
            transition: 'all 0.2s'
        }
    }, 'Markdown'),
    React.createElement('button', {
        className: viewMode === 'text' ? 'active' : '',
        onClick: () => setViewMode('text'),
        style: {
            padding: '4px 12px',
            border: '1px solid var(--border-color, #ccc)',
            background: viewMode === 'text' ? 'var(--accent-color, #0078d4)' : 'var(--bg-color, #fff)',
            color: viewMode === 'text' ? '#fff' : 'var(--text-color, #333)',
            borderRadius: '4px',
            cursor: 'pointer',
            fontSize: '13px',
            transition: 'all 0.2s'
        }
    }, 'Text')
)
```

#### Step 5: Update Content Rendering
Replace the content area with conditional rendering:
```javascript
React.createElement('div', {
    className: 'help-content',
    style: {
        flex: 1,
        overflow: 'auto',
        padding: '16px',
        backgroundColor: 'var(--bg-color, #fff)',
        color: 'var(--text-color, #333)'
    }
},
    viewMode === 'rendered'
        ? React.createElement('div', {
            className: 'markdown-body',
            dangerouslySetInnerHTML: { __html: htmlContent }
        })
        : React.createElement('pre', {
            className: 'markdown-raw',
            style: {
                whiteSpace: 'pre-wrap',
                wordBreak: 'break-word',
                fontFamily: 'Consolas, Monaco, "Courier New", monospace',
                fontSize: '13px',
                lineHeight: '1.6',
                margin: 0,
                color: 'var(--text-color, #333)',
                backgroundColor: 'var(--bg-color, #fff)'
            }
        }, rawContent)
)
```

#### Step 6: Add CSS Styles (Optional)
Add to `C:\SC\PsWebHost\public\elements\help-viewer\style.css`:

```css
/* Toolbar styles */
.help-viewer-toolbar {
    flex-shrink: 0;
    user-select: none;
}

.help-viewer-toolbar button {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
}

.help-viewer-toolbar button:hover {
    opacity: 0.9;
}

.help-viewer-toolbar button:active {
    transform: translateY(1px);
}

/* Raw markdown view */
.markdown-raw {
    tab-size: 4;
    -moz-tab-size: 4;
}
```

---

## Testing Checklist

After porting, test the following:

- [ ] Toolbar renders correctly in both light and dark themes
- [ ] Markdown mode shows properly rendered HTML
- [ ] Text mode shows raw markdown content
- [ ] Toggle button switches between modes instantly
- [ ] Active state styling is correct (blue background, white text)
- [ ] Text mode preserves whitespace and line breaks
- [ ] Text mode uses monospace font
- [ ] Long markdown files scroll correctly in both modes
- [ ] Component works with all file types (.md, .markdown, .txt)
- [ ] No console errors when switching modes
- [ ] Browser back/forward buttons work correctly
- [ ] View mode persists during resize operations

---

## Benefits of This Feature

1. **Debugging:** Users can see raw markdown to troubleshoot formatting issues
2. **Learning:** Side-by-side comparison helps users learn markdown syntax
3. **Copying:** Easy to copy raw markdown content for reuse
4. **Transparency:** Shows exactly what's in the file without interpretation
5. **Verification:** Confirm content before making edits elsewhere

---

## Alternative Implementation: URL Parameter

Consider adding URL parameter support for default view mode:

```javascript
// Example: ?file=help.md&mode=text
const urlParams = new URLSearchParams(window.location.search);
const defaultMode = urlParams.get('mode') || 'rendered';
const [viewMode, setViewMode] = React.useState(defaultMode);
```

This allows:
- Deep linking to specific view modes
- User preference persistence via bookmarks
- Integration with other components

---

## Estimated Implementation Time

- **Basic port:** 30-45 minutes
- **Testing:** 15-30 minutes
- **CSS refinement:** 15 minutes
- **Total:** ~1.5 hours

---

## Notes

- The core help-viewer already has similar structure, making this port straightforward
- Use CSS variables for theming consistency
- Consider adding keyboard shortcut (e.g., Alt+T) to toggle modes
- May want to persist user preference in localStorage
- Consider adding copy button in text mode for quick content copying

---

**Port this feature before removing the WebHostHelpViewer app to maintain feature parity.**
