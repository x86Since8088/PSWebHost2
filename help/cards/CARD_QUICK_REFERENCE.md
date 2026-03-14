# PSWebHost Card System - Quick Reference

**For:** Developers creating or debugging cards
**See Also:** CARD_SYSTEM_DOCUMENTATION.md (comprehensive guide)

---

## Card Checklist

Creating a new card? Follow this checklist:

- [ ] Create endpoint: `routes/cards/[name]/get.ps1`
- [ ] Create component: `public/elements/[name]/component.js`
- [ ] Endpoint returns JSON with `scriptPath` field
- [ ] Component registers: `window.cardComponents['name'] = Component`
- [ ] Add to menu: `routes/cards/main-menu/main-menu.yaml`
- [ ] Test: `window.openCard('/cards/name', 'Title')`

---

## Minimum Viable Card

### Endpoint: `routes/cards/my-card/get.ps1`

```powershell
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    $cardInfo = @{
        component = 'my-card'
        scriptPath = '/public/elements/my-card/component.js'
        title = 'My Card'
    }
    context_response -Response $Response -String ($cardInfo | ConvertTo-Json) -ContentType "application/json"
} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'CardLoad' -Message $_.Exception.Message
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
```

### Component: `public/elements/my-card/component.js`

```javascript
const MyCard = ({ url, element }) => {
    return React.createElement('div', { style: { padding: '16px' } },
        React.createElement('h2', null, 'My Card'),
        React.createElement('p', null, 'Hello from my card!')
    );
};

window.cardComponents = window.cardComponents || {};
window.cardComponents['my-card'] = MyCard;
```

---

## Common Patterns

### Fetch Data in Component

```javascript
const MyCard = ({ url, element }) => {
    const [data, setData] = React.useState(null);
    const [loading, setLoading] = React.useState(true);

    React.useEffect(() => {
        fetch('/api/v1/my-data')
            .then(res => res.json())
            .then(data => {
                setData(data);
                setLoading(false);
            })
            .catch(err => console.error(err));
    }, []);

    if (loading) return React.createElement('div', null, 'Loading...');

    return React.createElement('div', { style: { padding: '16px' } },
        React.createElement('pre', null, JSON.stringify(data, null, 2))
    );
};
```

### Pass Data from Endpoint

```powershell
# In endpoint get.ps1
$cardInfo = @{
    scriptPath = '/public/elements/my-card/component.js'
    myData = @{
        value1 = 'Hello'
        value2 = 123
    }
}
context_response -Response $Response -String ($cardInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"
```

```javascript
// In component.js - access via element.myData
const MyCard = ({ url, element }) => {
    console.log(element.myData); // { value1: 'Hello', value2: 123 }

    return React.createElement('div', null,
        React.createElement('p', null, element.myData.value1)
    );
};
```

### Add Menu Entry

```yaml
# In routes/cards/main-menu/main-menu.yaml
- Name: My Section
  roles:
  - authenticated
  children:
  - Name: My Card
    url: /cards/my-card
    hover_description: My card description
    tags:
    - custom
```

---

## Debugging Commands

### Browser Console

```javascript
// Check if component registered
console.log(window.cardComponents['card-name']);

// List all registered components
console.log(Object.keys(window.cardComponents));

// Open a card programmatically
window.openCard('/cards/system-log', 'System Log');

// Check current layout
console.log(window.appData?.gridLayout);

// Find cards by element ID
window.findCardsByElementId('system-log');

// Scroll to specific card
window.scrollToCard('system-log-1234567890');
```

### Test Endpoint

```bash
# Test endpoint response
curl http://localhost:8080/cards/my-card

# Should return JSON like:
# {"component":"my-card","scriptPath":"/public/elements/my-card/component.js","title":"My Card"}
```

---

## Common Errors

### "No component path found for [name]"

**Cause:** Endpoint doesn't return `scriptPath`

**Fix:** Add to endpoint:
```powershell
$cardInfo = @{
    scriptPath = '/public/elements/[name]/component.js'
}
```

### "window.cardComponents[...] is undefined"

**Cause:** Component didn't register

**Fix:** Add to component:
```javascript
window.cardComponents['card-name'] = ComponentName;
```

### Card loads but shows blank

**Causes:**
1. Component has JavaScript error (check console)
2. Component returns null/undefined
3. Component not using React.createElement

**Debug:**
```javascript
// Check for errors
console.error.bind(console);

// Verify component function exists
typeof window.cardComponents['card-name'] === 'function'
```

### Endpoint returns 404

**Causes:**
1. File doesn't exist at expected path
2. Routing not configured
3. Server needs restart

**Check:**
- File exists: `routes/cards/[name]/get.ps1`
- Path matches URL: `/cards/[name]` → `routes/cards/[name]/get.ps1`

---

## Card Sizing Guide

**Grid System:**
- 12 columns wide
- ~15px per height unit
- Position: `{x, y, w, h}`

**Recommended Sizes:**

| Type | Width | Height | Use Case |
|------|-------|--------|----------|
| Small | 3 | 8 | Compact info widget |
| Medium | 6 | 12 | Standard card |
| Large | 12 | 14 | Full-width content |
| Tall | 6 | 20 | Scrollable lists |
| Chart | 8-12 | 12-16 | Data visualization |

**Example:**
```javascript
// In endpoint - suggest default size
$cardInfo = @{
    scriptPath = '/public/elements/my-card/component.js'
    width = 12   # Full width
    height = 14  # ~210px tall
}
```

---

## File Locations

```
PSWebHost/
├── routes/cards/
│   └── [card-name]/
│       └── get.ps1                    # Card endpoint
├── public/elements/
│   └── [card-name]/
│       ├── component.js               # Card component
│       └── style.css                  # Optional styles
├── apps/
│   └── [AppName]/
│       ├── routes/cards/
│       │   └── [card-name]/get.ps1    # App card endpoint
│       └── public/elements/
│           └── [card-name]/
│               └── component.js       # App card component
└── routes/cards/main-menu/
    └── main-menu.yaml                 # Menu structure
```

---

## Card Props Reference

Components receive these props:

```javascript
const MyCard = ({ url, element }) => {
    // url: Original endpoint URL (e.g., "/cards/my-card")
    // element: Card metadata object

    console.log(element);
    // {
    //   Element_Id: 'my-card',
    //   Title: 'My Card',
    //   url: '/cards/my-card',
    //   backgroundColor: '#ff0000',  // if set
    //   ...any custom fields from endpoint
    // }
};
```

---

## Layout URL Format

Share card layouts via URL:

**Format:**
```
?layout=<base64-encoded-json>
```

**Structure:**
```json
{
  "version": 2,
  "cards": [
    {
      "id": "system-log-1234567890",
      "elementId": "system-log",
      "x": 0, "y": 0, "w": 6, "h": 12,
      "title": "System Log",
      "endpoint": "/cards/system-log"
    }
  ]
}
```

**Programmatic Access:**
```javascript
// Get current layout URL
const url = window.location.href;

// Parse layout from URL
const params = new URLSearchParams(window.location.search);
const layoutParam = params.get('layout');
```

---

## Best Practices

### ✅ DO

- Use `React.createElement` for React components
- Register component in `window.cardComponents`
- Return JSON with `scriptPath` from endpoint
- Handle loading states in component
- Use try/catch in endpoint
- Log errors with `Write-PSWebHostLog`
- Test endpoint directly with curl/browser
- Check browser console for errors

### ❌ DON'T

- Don't use JSX without Babel transform
- Don't forget to register component
- Don't use duplicate keys in PowerShell hashtables
- Don't hardcode server URLs (use relative paths)
- Don't ignore error states
- Don't return 200 OK for errors

---

## Testing Workflow

1. **Create endpoint** → Test with curl
2. **Create component** → Check registration in console
3. **Open card** → `window.openCard('/cards/name', 'Title')`
4. **Check console** → Look for errors
5. **Verify layout** → Card should appear in grid
6. **Test resize** → Drag to resize
7. **Test URL** → Layout should persist in URL

---

## Performance Tips

- **Lazy load data** in useEffect, not inline
- **Cache responses** when possible
- **Debounce API calls** for user input
- **Use React.memo** for expensive renders
- **Minimize re-renders** with proper deps arrays
- **Clean up effects** with return cleanup function

---

## Need Help?

1. **Check documentation:** `CARD_SYSTEM_DOCUMENTATION.md`
2. **Check investigation report:** `CARD_SYSTEM_INVESTIGATION_REPORT.md`
3. **Look at examples:** Browse `public/elements/*/component.js`
4. **Test in console:** Use debugging commands above
5. **Check logs:** Server logs in PSWebHost output

---

**Quick Reference Maintained By:** Agent_PSWebhost_Cards
**Last Updated:** 2026-02-23
