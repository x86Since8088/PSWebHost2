# Iframe Loader System - DOM Inspection for Iframe Cards

**Date**: 2026-02-03
**Purpose**: Solve iframe DOM isolation problem by injecting inspection script

---

## 🎯 Problem Solved

**Issue**: Parent document cannot inspect iframe content due to browser security (same-origin policy)
- `iframe.contentDocument` returns null or restricted
- Cannot run `document.querySelector()` into iframe
- Validation fails for all iframe-based cards (24 cards affected)

**Solution**: Inject loader script INTO the iframe that reports DOM status back to parent via `logToServer()`

---

## 🔧 How It Works

### 1. Iframe Component Enhanced

**Location**: `public/psweb_spa.js` (IFrameComponent)

**What it does**:
- Detects when iframe finishes loading
- Injects `iframe-loader.js` script into iframe's document
- Script runs inside iframe context (has full DOM access)
- Reports back to parent via `window.parent.logToServer()`

```javascript
const IFrameComponent = ({ element }) => {
    const iframeRef = React.useRef(null);

    React.useEffect(() => {
        const iframe = iframeRef.current;

        const onLoad = () => {
            // Inject loader script into iframe
            const script = iframe.contentDocument.createElement('script');
            script.src = '/apps/WebHostDebugExtensions/public/iframe-loader.js';
            iframe.contentDocument.head.appendChild(script);
        };

        iframe.addEventListener('load', onLoad);
    }, []);

    return React.createElement('iframe', { ref: iframeRef, src: element.url });
};
```

### 2. Iframe Loader Script

**Location**: `apps/WebHostDebugExtensions/public/iframe-loader.js`

**What it analyzes**:
- Total elements count
- Error elements (`.error`, `.error-message`)
- Loading indicators (`.loading`, `.spinner`)
- React root detection
- Console errors
- Page load timing
- Content presence
- DOM stability (waits for no new elements)

**What it reports**:
```javascript
window.reportCardDom(cardPath, {
    totalElements: 150,
    totalDivs: 45,
    hasErrorElements: false,
    errorElementCount: 0,
    hasLoadingElements: false,
    bodyTextLength: 1234,
    loadTime: 456,
    timestamp: "2026-02-03T..."
});
```

**Logs to**: Category `IframeCardLoad` via `window.parent.logToServer()`

### 3. Global Reporting Function

**Location**: `public/psweb_spa.js`

**Available globally**:
```javascript
window.reportCardDom(cardPath, domInfo)
```

**Can be used by**:
- Iframe loader (automatic)
- Component cards (manual)
- Custom validation scripts

### 4. Validation Logging

**Location**: `apps/WebHostDebugExtensions/public/elements/debug-console/commands.js`

**validateCard command now logs**:
- Category: `CardValidation`
- Level: `Info`, `Warning` based on results
- Data: Full validation object with DOM counts, error detection

---

## 📊 What Gets Logged

### IframeCardLoad Category

**Logged by**: iframe-loader.js inside iframe

**Data includes**:
```json
{
    "cardPath": "/apps/vault/api/v1/audit",
    "location": "http://localhost:8080/apps/vault/api/v1/audit",
    "totalElements": 150,
    "totalDivs": 45,
    "totalScripts": 3,
    "totalStyles": 2,
    "hasTitle": true,
    "title": "Audit Log",
    "bodyHasContent": true,
    "bodyTextLength": 1234,
    "hasErrorElements": false,
    "errorElementCount": 0,
    "errorTexts": [],
    "hasLoadingElements": false,
    "loadingElementCount": 0,
    "hasReactRoot": true,
    "reactRootIds": ["root"],
    "consoleErrors": [],
    "loadTime": 456,
    "domContentLoadedTime": 234,
    "timestamp": "2026-02-03T..."
}
```

### CardValidation Category

**Logged by**: validateCard command

**Data includes**:
```json
{
    "exists": true,
    "cardId": "docker-manager-1234567890",
    "elementId": "docker-manager",
    "title": "Docker Manager",
    "url": "/apps/dockermanager/cards/docker-manager",
    "hasDOM": true,
    "hasComponent": true,
    "hasError": false,
    "errorCount": 0,
    "domNodeCount": 14,
    "hasContent": true,
    "isValid": true,
    "foundBy": "title-match",
    "timestamp": "2026-02-03T..."
}
```

### CardDomReport Category

**Logged by**: Custom card components using `window.reportCardDom()`

**Data**: User-defined QA information

---

## 🚀 Testing Scripts

### Test Iframe Loader
```powershell
.\test_iframe_loader.ps1
```
**Tests**: Coverage Report, Process Tracking, Audit Log, Vault Status
**Verifies**: Loader injection and DOM reporting

### Continuous Testing with Logging
```powershell
.\test_cards_continuous.ps1 -MaxCards 10 -DelayBetweenCards 5
```
**Tests**: All cards sequentially
**Logs**: Every validation result and DOM report

### Quick 3-Card Test
```powershell
.\test_cards_continuous.ps1 -MaxCards 3 -DelayBetweenCards 4
```

---

## 👀 Viewing Logs

### In System Log Card

1. Open **System Log** card from main menu
2. Filter by category:
   - `IframeCardLoad` - See iframe DOM analysis
   - `CardValidation` - See validation results
   - `CardDomReport` - See custom QA reports
3. Review data for errors, warnings, QA info

### Example Filters
- Show only errors: Filter by level = `Warning` or `Error`
- Show specific card: Filter message contains card name
- Show iframe reports: Category = `IframeCardLoad`
- Show validations: Category = `CardValidation`

---

## 💡 Best Practices for Card Developers

### Component-Based Cards (Recommended)

**Return JSON metadata**:
```json
{
    "component": "my-card",
    "scriptPath": "/apps/myapp/public/elements/my-card/component.js",
    "title": "My Card"
}
```

**Use window.logToServer() for QA**:
```javascript
window.cardComponents['my-card'] = function MyCard({ cardId }) {
    React.useEffect(() => {
        // Log when card mounts
        window.logToServer('My Card mounted', 'MyCard', 'Info', {
            cardId: cardId,
            timestamp: new Date().toISOString()
        });

        // Log data loading
        fetchData().then(data => {
            window.logToServer('Data loaded', 'MyCard', 'Info', {
                recordCount: data.length,
                loadTime: Date.now() - startTime
            });
        }).catch(error => {
            window.logToServer('Data load failed', 'MyCard', 'Error', {
                error: error.message
            });
        });
    }, []);

    return React.createElement('div', null, 'Content');
};
```

**Report DOM status**:
```javascript
// When card is fully rendered
window.reportCardDom('/apps/myapp/api/v1/ui/elements/my-card', {
    dataLoaded: true,
    recordCount: 150,
    renderTime: 234
});
```

### Iframe-Based Cards

**Loader is automatic** - No code changes needed!

**Optional: Enhanced reporting**:
```html
<!DOCTYPE html>
<html>
<head>
    <title>My Card</title>
</head>
<body>
    <div id="app">Loading...</div>

    <script>
        // Your card logic here

        // When ready, report additional QA info
        window.addEventListener('load', () => {
            if (window.reportCardDom) {
                window.reportCardDom(window.location.pathname, {
                    customData: 'your QA data here',
                    apiCallsMade: 3,
                    cachesUsed: ['users', 'settings']
                });
            }
        });
    </script>
</body>
</html>
```

---

## 🔍 DOM Analysis Details

### What Loader Checks

**Element Counts**:
- Total elements in document
- Divs, scripts, styles
- React root elements

**Error Detection**:
- Elements with `.error` or `.error-message` classes
- Elements with `error` in class name
- Captures error text content (first 200 chars)

**Loading State**:
- Elements with `.loading` or `.spinner` classes
- Waits for loading indicators to disappear

**Content Verification**:
- Body text length
- Meaningful content threshold
- Title presence

**Console Errors**:
- Captures `console.error()` calls
- Includes in report

**Timing**:
- Load event timing
- DOM content loaded timing
- Custom performance marks

### Stability Detection

**Waits for stable DOM**:
- Checks element count every 200ms
- Requires 3 consecutive checks with same count
- Requires no loading indicators
- Max wait time: 5 seconds
- Reports current state if timeout

---

## 📈 Benefits

### For QA

✅ **Comprehensive Data**: Every card reports detailed DOM info
✅ **Error Detection**: Automatic error element detection
✅ **Timing Data**: Load performance metrics
✅ **Historical Logs**: All reports saved to server
✅ **Centralized View**: System Log card shows everything

### For Developers

✅ **Easy Integration**: Just use `window.logToServer()`
✅ **No Boilerplate**: Iframe loader is automatic
✅ **Flexible**: Log any custom QA data
✅ **Debuggable**: All logs visible in System Log

### For Testing

✅ **Automated**: Continuous testing script runs unattended
✅ **Reliable**: Waits for DOM stability before reporting
✅ **Complete**: Tests both component and iframe cards
✅ **Fast**: Configurable delays between cards

---

## 🎯 Use Cases

### Development

**Test new card**:
```powershell
# Open card and check logs
window.openCard("/apps/myapp/api/v1/ui/elements/new-card")
# Wait 5 seconds
# Check System Log for IframeCardLoad or CardValidation
```

### QA Testing

**Run full suite**:
```powershell
.\test_cards_continuous.ps1
# Review logs for errors
# Filter by Warning/Error level
```

### Debugging

**Investigate card issue**:
1. Open problematic card
2. Check System Log for errors
3. Review DOM analysis data
4. Check console errors captured
5. Review timing data

### Monitoring

**Periodic health checks**:
```powershell
# Run in scheduled task
.\test_cards_continuous.ps1 -MaxCards 5
# Alert if failures detected
```

---

## 🔄 Future Enhancements

**Planned**:
- [ ] Role-based loader injection (only for debug role)
- [ ] Screenshot capture on errors
- [ ] Network request logging
- [ ] Memory usage tracking
- [ ] Accessibility validation
- [ ] Performance budgets
- [ ] Automated regression detection

---

## 📚 Related Files

**Core System**:
- `public/psweb_spa.js` - IFrameComponent with injection
- `apps/WebHostDebugExtensions/public/iframe-loader.js` - Loader script
- `apps/WebHostDebugExtensions/public/elements/debug-console/commands.js` - validateCard with logging

**Testing**:
- `test_iframe_loader.ps1` - Iframe-specific testing
- `test_cards_continuous.ps1` - Comprehensive testing with logs
- `test_card_validation_page.ps1` - HTML-based validation

**Documentation**:
- `QUICK_REFERENCE.md` - Quick command reference
- `DESIGN_PATTERNS_ANALYSIS.md` - Component vs iframe patterns
- `AUTOMATION_SUMMARY_2026-02-03.md` - Full session summary

---

**Status**: ✅ Fully implemented and tested
**Coverage**: Iframe DOM inspection now working for all iframe-based cards
