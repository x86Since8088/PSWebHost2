# DEPRECATION NOTICE: WebHostHelpViewer

**Status:** DEPRECATED
**Deprecation Date:** 2026-02-23
**Removal Date:** 2026-03-25 (30 days from deprecation)
**Replacement:** Core help-viewer (`/cards/help-viewer`) or markdown-viewer (`/cards/markdown-viewer`)

---

## Why This App is Deprecated

The **WebHostHelpViewer** app is **100% duplicate functionality** of the core PSWebHost help-viewer component. This violates the DRY (Don't Repeat Yourself) principle and creates unnecessary maintenance overhead.

### Functionality Comparison

| Feature | WebHostHelpViewer (App) | Core help-viewer | Core markdown-viewer |
|---------|------------------------|------------------|---------------------|
| Markdown rendering | Yes | Yes | Yes |
| File search (multiple paths) | Yes | Yes | Yes |
| Security (path sanitization) | Yes | Yes | Yes |
| Text/Markdown toggle | **YES** | **NO** | No |
| Mermaid diagrams | No | No | Yes |
| Edit capability | No | No | Yes (with auth) |
| markdown-it library | Yes | No (basic converter) | Yes |

---

## Migration Path

### For Basic Help Viewing

**Old URL:**
```
/apps/WebHostHelpViewer/cards/help-viewer?file=help-viewer.md
```

**New URL (Core Help-Viewer):**
```
/cards/help-viewer?file=help-viewer.md
```

### For Advanced Markdown Viewing

**New URL (Core Markdown-Viewer):**
```
/cards/markdown-viewer?file=help-viewer.md
```

The markdown-viewer provides:
- Mermaid diagram support
- TOAST UI Editor integration
- Editing capabilities for authorized users

### For JavaScript Integration

**Old Code:**
```javascript
window.psweb.loadCard('/apps/WebHostHelpViewer/cards/help-viewer?file=topic.md');
```

**New Code:**
```javascript
// Option 1: Core help-viewer
window.psweb.loadCard('/cards/help-viewer?file=topic.md');

// Option 2: Core markdown-viewer (recommended)
window.psweb.loadCard('/cards/markdown-viewer?file=topic.md');
```

### For PowerShell Integration

**Old Code:**
```powershell
Launch-DebugCard -CardUrl '/apps/WebHostHelpViewer/cards/help-viewer' -Params @{ file = 'topic.md' }
```

**New Code:**
```powershell
# Option 1: Core help-viewer
Launch-DebugCard -CardUrl '/cards/help-viewer' -Params @{ file = 'topic.md' }

# Option 2: Core markdown-viewer (recommended)
Launch-DebugCard -CardUrl '/cards/markdown-viewer' -Params @{ file = 'topic.md' }
```

---

## Unique Feature: Text/Markdown Toggle

The WebHostHelpViewer app includes a **text/markdown toggle feature** that allows users to switch between:
1. **Markdown Mode:** Rendered HTML with full markdown formatting
2. **Text Mode:** Raw markdown content in a monospace font

### Feature Details

This feature is implemented in `/apps/WebHostHelpViewer/public/elements/help-viewer/component.js`:

- **State Management:** Uses React state `viewMode` ('rendered' or 'text')
- **UI:** Toolbar with two buttons to toggle between modes
- **Rendering:**
  - **Rendered mode:** Uses markdown-it library to render HTML
  - **Text mode:** Displays raw markdown in a `<pre>` element with monospace font

### Porting Recommendation

This feature should be ported to the **core help-viewer** component at `/public/elements/help-viewer/component.js` to provide users with the ability to view raw markdown source when needed.

**Use Cases for Text/Markdown Toggle:**
- Debugging markdown syntax issues
- Copying raw markdown content
- Learning markdown syntax by comparing rendered and raw views
- Troubleshooting formatting problems

See `FEATURE_PORT_DOCUMENTATION.md` for detailed implementation guide.

---

## Timeline

| Date | Action |
|------|--------|
| 2026-02-23 | App disabled (`enabled: false`) |
| 2026-02-23 to 2026-03-25 | 30-day grace period for migration |
| 2026-03-25 | App directory will be removed from codebase |

---

## Migration Checklist

- [ ] Audit all code referencing `/apps/WebHostHelpViewer/`
- [ ] Update all direct URL references to use `/cards/help-viewer` or `/cards/markdown-viewer`
- [ ] Update JavaScript code using `window.psweb.loadCard()`
- [ ] Update PowerShell scripts using `Launch-DebugCard`
- [ ] Update any documentation or help files referencing this app
- [ ] Test all help viewer functionality with core components
- [ ] Remove any app-specific configuration or customizations

---

## Questions or Issues?

If you encounter any problems during migration or have questions:

1. Check the core help-viewer documentation at `/docs/help-viewer.md`
2. Review the markdown-viewer documentation at `/docs/markdown-viewer.md`
3. Contact the PSWebHost administrator
4. Review system logs for any errors

---

**This app will be completely removed after 2026-03-25. Please migrate immediately.**
