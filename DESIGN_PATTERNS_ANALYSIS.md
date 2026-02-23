# PSWebHost Card Design Patterns - Best Practices Analysis

**Date**: 2026-02-03

---

## 🎯 Executive Summary

**Working Pattern**: Component-based cards that return JSON with `scriptPath` and `component` fields
**Pass Rate**: 100% for component-based cards, 0% for iframe/HTML-based cards
**Key Issue**: Iframe isolation prevents DOM inspection and validation

---

## ✅ Best Practice: Component-Based Card Pattern

### What Works Well

**8 Cards with 100% Success Rate:**
1. Docker Manager
2. SQLite Manager
3. Debug Console
4. File Explorer
5. Real-time Events
6. Windows Services
7. Task Scheduler
8. WSL Manager

### Pattern Specification

**Endpoint Response (JSON):**
```json
{
    "component": "file-explorer",
    "scriptPath": "/apps/WebhostFileExplorer/public/elements/file-explorer/component.js",
    "title": "File Explorer",
    "description": "User file management interface",
    "version": "1.0.0",
    "width": 12,
    "height": 600,
    "features": ["feature1", "feature2"]
}
```

**Required Fields:**
- ✅ `component` - Component identifier/name
- ✅ `scriptPath` - Path to React component JavaScript file
- ✅ `title` - Card title
- ⚠️ `width` - Recommended (default: 12)
- ⚠️ `height` - Recommended (default: 400)

**File Structure:**
```
apps/MyApp/
├── routes/
│   └── api/v1/ui/elements/my-card/
│       └── get.ps1          # Returns JSON metadata
├── public/
│   └── elements/my-card/
│       └── component.js      # React component
```

**Example Endpoint (get.ps1):**
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
        scriptPath = '/apps/MyApp/public/elements/my-card/component.js'
        title = 'My Card'
        description = 'Card description'
        version = '1.0.0'
        width = 12
        height = 600
    }

    context_response -Response $Response `
        -String ($cardInfo | ConvertTo-Json -Depth 10) `
        -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'MyApp' -Message $_.Exception.Message
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
```

**Example Component (component.js):**
```javascript
// Register component in global registry
window.cardComponents = window.cardComponents || {};

window.cardComponents['my-card'] = function MyCardComponent({ cardId, cardData }) {
    const [data, setData] = React.useState(null);
    const [loading, setLoading] = React.useState(true);

    React.useEffect(() => {
        // Fetch data and render
        loadData();
    }, []);

    const loadData = async () => {
        try {
            const response = await fetch('/api/v1/my-data');
            const result = await response.json();
            setData(result);
        } catch (error) {
            console.error('Error loading data:', error);
        } finally {
            setLoading(false);
        }
    };

    if (loading) return React.createElement('div', null, 'Loading...');

    return React.createElement('div', { className: 'my-card' },
        React.createElement('h2', null, 'My Card Title'),
        React.createElement('pre', null, JSON.stringify(data, null, 2))
    );
};
```

### Why This Pattern Works

**Advantages:**
1. ✅ **DOM Accessible**: Component renders in parent document, full DOM inspection available
2. ✅ **Validation Works**: Can detect errors, count DOM nodes, check for content
3. ✅ **React Integration**: Uses shared React instance, efficient rendering
4. ✅ **Shared Context**: Access to `window.appData`, global functions, shared state
5. ✅ **Fast Loading**: No iframe overhead, direct rendering
6. ✅ **Debugging**: React DevTools work, console logging visible
7. ✅ **Styling**: Can use global CSS, theme integration
8. ✅ **Event Handling**: Direct access to parent window events

---

## ❌ Anti-Pattern: Iframe-Based Cards

### What Doesn't Work

**24 Cards Failed DOM Validation:**
- Kubernetes Status, Linux Services, MySQL Manager, Redis Manager
- All UPlot charts (7 cards)
- Unit Test Runner, Coverage Report, Process Tracking
- Vault cards (3 cards)
- Memory Explorer, Debug Variables, Server Metrics, Task Management

### Problem: Iframe Isolation

**Why Iframes Fail Validation:**

```javascript
// Parent page tries to inspect iframe content
const cardElement = document.getElementById('iframe-card-123');
const content = cardElement.querySelector('.card-body'); // NULL!

// Iframe content is isolated in separate document
const iframe = cardElement.querySelector('iframe');
const iframeDoc = iframe.contentDocument; // May be null (cross-origin) or restricted
```

**Browser Security Restrictions:**

1. **Same-Origin Policy**: If iframe loads from different origin, `contentDocument` is blocked
2. **Sandboxing**: Iframes can be sandboxed, preventing script access
3. **Document Isolation**: Even same-origin iframes have separate DOM trees
4. **No Direct Access**: Parent cannot query `document.getElementById()` into iframe

### Current Iframe Patterns

**Pattern 1: HTML Response**
```powershell
# Endpoint returns HTML directly
$html = @"
<!DOCTYPE html>
<html><body>
<div id="content">Hello</div>
</body></html>
"@

context_response -Response $Response -String $html -ContentType "text/html"
```

**Pattern 2: Data-Only JSON (No scriptPath)**
```powershell
# Returns data without component metadata
$result = @{
    totalRoutes = 150
    testedRoutes = 75
    coveragePercent = 50.0
}

context_response -Response $Response -String ($result | ConvertTo-Json) -ContentType "application/json"
```

**Pattern 3: Non-Standard URL**
```
/apps/unittests/api/v1/coverage
# Doesn't match /api/v1/ui/elements/{id} pattern
# System defaults to iframe-card
```

### Why Iframes Were Used

**Legacy Reasons:**
- Existed before React component pattern
- Quick solution for existing HTML pages
- Isolation desired for security or style conflicts
- External content embedding

**Technical Reasons:**
- Complex standalone applications
- Third-party content
- Multiple document contexts needed

---

## 🔧 Migration Strategy: Iframe → Component

### Step-by-Step Migration

**1. Analyze Current Iframe Card**

Check what the endpoint returns:
```powershell
Invoke-RestMethod -Uri "http://localhost:8080/apps/vault/api/v1/audit"
```

**2. Create Component Metadata Endpoint**

Update `get.ps1` to return component metadata:
```powershell
# OLD (returns data or HTML)
$data = @{ logs = Get-AuditLogs }
context_response -Response $Response -String ($data | ConvertTo-Json) -ContentType "application/json"

# NEW (returns component metadata)
$cardInfo = @{
    component = 'audit-log'
    scriptPath = '/apps/vault/public/elements/audit-log/component.js'
    title = 'Audit Log'
    width = 12
    height = 600
}
context_response -Response $Response -String ($cardInfo | ConvertTo-Json) -ContentType "application/json"
```

**3. Create Data API Endpoint**

Separate data endpoint:
```powershell
# New file: apps/vault/routes/api/v1/audit/data/get.ps1
$data = @{
    logs = Get-AuditLogs
    total = 150
}
context_response -Response $Response -String ($data | ConvertTo-Json) -ContentType "application/json"
```

**4. Create React Component**

New file: `apps/vault/public/elements/audit-log/component.js`
```javascript
window.cardComponents = window.cardComponents || {};

window.cardComponents['audit-log'] = function AuditLog({ cardId, cardData }) {
    const [logs, setLogs] = React.useState([]);
    const [loading, setLoading] = React.useState(true);

    React.useEffect(() => {
        loadLogs();
    }, []);

    const loadLogs = async () => {
        try {
            const response = await fetch('/apps/vault/api/v1/audit/data');
            const data = await response.json();
            setLogs(data.logs);
        } catch (error) {
            console.error('Error loading audit logs:', error);
        } finally {
            setLoading(false);
        }
    };

    if (loading) {
        return React.createElement('div', { className: 'loading' }, 'Loading audit logs...');
    }

    return React.createElement('div', { className: 'audit-log' },
        React.createElement('h2', null, 'Audit Log'),
        React.createElement('table', null,
            React.createElement('thead', null,
                React.createElement('tr', null,
                    React.createElement('th', null, 'Timestamp'),
                    React.createElement('th', null, 'User'),
                    React.createElement('th', null, 'Action')
                )
            ),
            React.createElement('tbody', null,
                logs.map((log, idx) =>
                    React.createElement('tr', { key: idx },
                        React.createElement('td', null, log.timestamp),
                        React.createElement('td', null, log.user),
                        React.createElement('td', null, log.action)
                    )
                )
            )
        )
    );
};
```

**5. Update URL Pattern (if needed)**

Ensure URL matches standard pattern:
```
OLD: /apps/vault/api/v1/audit
NEW: /apps/vault/api/v1/ui/elements/audit-log
```

Or update routing to recognize custom patterns.

**6. Test**

```powershell
.\test_card_validation_page.ps1
```

---

## 📊 Comparison Matrix

| Feature | Component Pattern | Iframe Pattern |
|---------|------------------|----------------|
| **DOM Inspection** | ✅ Full access | ❌ Blocked |
| **Validation** | ✅ Works perfectly | ❌ Cannot detect |
| **Performance** | ✅ Fast, direct render | ⚠️ Slower, overhead |
| **Debugging** | ✅ React DevTools | ⚠️ Separate context |
| **Styling** | ✅ Global CSS | ⚠️ Isolated styles |
| **Security** | ⚠️ Shares context | ✅ Isolated |
| **Migration Effort** | ⚠️ Requires refactor | ✅ Already done |
| **Third-party Content** | ❌ Not suitable | ✅ Perfect use case |
| **Pass Rate** | ✅ 100% | ❌ 0% |

---

## 🎯 Recommendations

### Immediate Actions

1. **Audit All Cards**: Identify which cards use iframes
2. **Prioritize Migration**: Focus on internal cards first (vault, metrics, etc.)
3. **Keep Iframes For**: Truly external content or legacy standalone pages
4. **Standardize URLs**: Use `/api/v1/ui/elements/{component-id}` pattern
5. **Update Templates**: Create component boilerplate for new cards

### Migration Priority

**High Priority (Internal Apps):**
- ✅ Vault cards (Audit Log, Status, Credential Manager)
- ✅ Metrics cards (Server Heatmap)
- ✅ Debug Variables
- ✅ Memory Explorer
- ✅ Task Management

**Medium Priority (Complex Apps):**
- ⚠️ UPlot charts (7 cards) - May need custom rendering
- ⚠️ Unit Test Runner
- ⚠️ Database managers (MySQL, Redis, SQL Server)

**Low Priority (Keep as Iframe):**
- ⚠️ Coverage Report - May be complex standalone page
- ⚠️ Process Tracking - May need real-time terminal
- ⚠️ External integrations

**Don't Migrate:**
- ✅ Third-party embeds
- ✅ Full standalone applications
- ✅ Security-isolated components

### Long-term Strategy

1. **Component-First Architecture**: Make component pattern the default
2. **Generator Tool**: Create script to scaffold new component cards
3. **Migration Guide**: Document step-by-step process
4. **Testing Suite**: Automated validation for all cards
5. **Performance Monitoring**: Track load times and errors

---

## 🔍 Technical Deep Dive: Iframe DOM Isolation

### Why JavaScript Cannot Inspect Iframes

**Scenario:**
```html
<!-- Parent page -->
<div id="card-123" class="card">
    <iframe src="/apps/vault/api/v1/audit"></iframe>
</div>
```

**Problem:**
```javascript
// Parent JavaScript tries to validate
const card = document.getElementById('card-123');
const content = card.querySelector('.audit-log'); // Returns NULL!

// The iframe is a separate document
const iframe = card.querySelector('iframe');
console.log(iframe.contentDocument); // May be null or restricted
```

**Why:**
1. **Separate DOM Tree**: Iframe has its own `document` object
2. **Security Boundary**: Browser enforces same-origin policy
3. **Cross-Context**: `document.getElementById()` only searches current document
4. **No Traversal**: Cannot query across document boundaries

**Workarounds (All have limitations):**

```javascript
// 1. PostMessage (requires iframe cooperation)
iframe.contentWindow.postMessage({ action: 'validate' }, '*');
// ❌ Requires iframe to implement message handler

// 2. ContentDocument (same-origin only)
const iframeDoc = iframe.contentDocument || iframe.contentWindow.document;
const content = iframeDoc.querySelector('.audit-log');
// ❌ Returns null for cross-origin or sandboxed iframes

// 3. Custom Events (complex)
// ❌ Requires bidirectional communication setup
```

**Best Solution**: Don't use iframes for cards that need validation. Use component pattern instead.

---

## 📝 Checklist for New Cards

When creating a new card, follow this checklist:

### Component Pattern (Recommended)
- [ ] Create `routes/api/v1/ui/elements/{component-id}/get.ps1`
- [ ] Return JSON with `component` and `scriptPath` fields
- [ ] Create `public/elements/{component-id}/component.js`
- [ ] Register component in `window.cardComponents`
- [ ] Use React hooks for state management
- [ ] Fetch data from separate API endpoint
- [ ] Handle loading and error states
- [ ] Add proper error messages
- [ ] Test with `test_card_validation_page.ps1`
- [ ] Verify 100% pass rate

### Iframe Pattern (Only if Required)
- [ ] Document why iframe is necessary
- [ ] Return HTML with `Content-Type: text/html`
- [ ] Include full HTML document structure
- [ ] Handle loading states within iframe
- [ ] Consider postMessage for parent communication
- [ ] Accept that validation will fail (expected)
- [ ] Test manually in browser

---

## 🎓 Key Learnings

1. **Component pattern = 100% validation success**
2. **Iframe pattern = 0% validation success (by design)**
3. **DOM isolation is a security feature, not a bug**
4. **Migration is straightforward: metadata + component file**
5. **Separate UI endpoint from data endpoint**
6. **Standard URL pattern improves consistency**
7. **React component registry is simple and effective**

---

## 📚 References

- **Working Example**: `apps/WebhostFileExplorer/routes/api/v1/ui/elements/file-explorer/get.ps1`
- **Component Example**: `apps/WebhostFileExplorer/public/elements/file-explorer/component.js`
- **Testing**: `test_card_validation_page.ps1`
- **Validation Results**: User-provided JSON with 18 cards tested
- **Load Logic**: `public/psweb_spa.js` lines 2248-2350 (loadComponentScript)
- **Open Logic**: `public/psweb_spa.js` lines 2568-2650 (window.openCard)

---

**Conclusion**: The component-based pattern is the clear winner for internal cards. Migrate iframe-based cards systematically to achieve 100% validation coverage and improved maintainability.
