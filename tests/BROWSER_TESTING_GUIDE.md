# Browser Testing Guide for PSWebHost

Comprehensive guide for testing JavaScript, web components, and UI modifications using MSEdge debugging sessions.

## Table of Contents

1. [Overview](#overview)
2. [Available Tools](#available-tools)
3. [Quick Start](#quick-start)
4. [Interactive Testing](#interactive-testing)
5. [Automated Testing](#automated-testing)
6. [Advanced Features](#advanced-features)
7. [Common Use Cases](#common-use-cases)
8. [Troubleshooting](#troubleshooting)

---

## Overview

PSWebHost includes powerful browser testing tools that leverage the Microsoft Edge DevTools Protocol (CDP) to:
- Forward `console.log()` messages to PowerShell
- Evaluate JavaScript in the browser context
- Inspect and modify DOM elements
- Capture screenshots
- Monitor network traffic (HAR files)
- Measure performance metrics

## Available Tools

### 1. **MSEdgeSessionDebugging.ps1** (Original)
Comprehensive HAR capture tool for network debugging.
- Captures all HTTP requests/responses
- Saves to HAR format
- Redacts sensitive data
- Best for: Network debugging, API testing

### 2. **MSEdgeSessionDebugging-Enhanced.ps1** (New)
Enhanced testing tool with JavaScript evaluation and console forwarding.
- Console.log forwarding
- JavaScript evaluation
- DOM manipulation
- Screenshots
- Performance metrics
- Interactive mode
- Best for: UI testing, component development

### 3. **Quick-BrowserTest.ps1** (Wrapper)
Simplified wrapper for common testing scenarios.
- Easy URL testing
- Element validation
- Quick screenshots
- Best for: Quick validation during development

---

## Quick Start

### Test a Specific Page

```powershell
# Test the bar chart component
.\Quick-BrowserTest.ps1 -TestUrl "/apps/uplot/api/v1/ui/elements/bar-chart?chartId=test1"

# Test with element selector
.\Quick-BrowserTest.ps1 -TestUrl "/apps/uplot/api/v1/ui/elements/bar-chart?chartId=test1" -ElementSelector ".bar-chart-container"

# Interactive mode
.\Quick-BrowserTest.ps1 -TestUrl "/apps/vault/api/v1/ui/elements/vault-manager" -Interactive
```

### Enhanced Testing Session

```powershell
# Start enhanced session
.\MSEdgeSessionDebugging-Enhanced.ps1 -Url "http://localhost:8888/apps/uplot/api/v1/ui/elements/time-series" -Interactive

# With HAR capture
.\MSEdgeSessionDebugging-Enhanced.ps1 -Url "http://localhost:8888" -CaptureHAR -ForwardConsole

# Custom timeout
.\MSEdgeSessionDebugging-Enhanced.ps1 -Url "http://localhost:8888" -TimeoutMinutes 60
```

---

## Interactive Testing

When you start an interactive session, you get a PowerShell prompt with access to the browser:

```powershell
.\MSEdgeSessionDebugging-Enhanced.ps1 -Url "http://localhost:8888" -Interactive
```

### Available Commands

```
eval <js>          - Evaluate JavaScript
click <selector>   - Click element
text <selector>    - Get element text
exists <selector>  - Check if element exists
wait <selector>    - Wait for element (30s timeout)
screenshot [path]  - Take screenshot
perf               - Show performance metrics
reload             - Reload page
console            - Show console messages
exit               - Exit interactive mode
```

### Example Interactive Session

```
Test> eval console.log('Hello from PowerShell!')
[Browser Log] Hello from PowerShell!

Test> exists .card-header
Exists: True

Test> text .card-title
Text: Role Management

Test> click button.settings-icon
Clicked: button.settings-icon

Test> screenshot test-screenshot.png
Screenshot saved: test-screenshot.png

Test> perf
{
  "domContentLoaded": 45,
  "loadComplete": 123,
  "domInteractive": 89,
  "totalTime": 234
}

Test> exit
```

---

## Automated Testing

### Using PowerShell Functions Directly

```powershell
# Start session (non-interactive)
.\MSEdgeSessionDebugging-Enhanced.ps1 -Url "http://localhost:8888/apps/uplot/api/v1/ui/elements/bar-chart"

# In the script, you can use these functions:
# - Invoke-JavaScript -Script "console.log('test')" -ReturnByValue
# - Test-ElementExists -Selector ".bar-chart-container"
# - Wait-ForElement -Selector ".chart-header" -TimeoutSeconds 10
# - Get-ElementText -Selector ".card-title"
# - Click-Element -Selector "button.refresh-btn"
# - Take-Screenshot -OutputPath "screenshot.png"
# - Get-PerformanceMetrics
```

### Example Test Script

Create a custom test script:

```powershell
# test-bar-chart.ps1
param([string]$BaseUrl = "http://localhost:8888")

$testUrl = "$BaseUrl/apps/uplot/api/v1/ui/elements/bar-chart?chartId=test1&source=metrics-db&metric=request_count"

# Dot-source the enhanced script to get functions
. "$PSScriptRoot\MSEdgeSessionDebugging-Enhanced.ps1" -Url $testUrl

# Wait for chart to load
if (Wait-ForElement -Selector ".bar-chart-container" -TimeoutSeconds 10) {
    Write-Host "Chart loaded successfully!" -ForegroundColor Green

    # Verify chart header
    $title = Get-ElementText -Selector ".chart-title"
    if ($title -eq "Bar Chart") {
        Write-Host "Title is correct: $title" -ForegroundColor Green
    }

    # Check for data
    $hasData = Invoke-JavaScript -Script "document.querySelector('#chartContainer canvas') !== null" -ReturnByValue
    if ($hasData) {
        Write-Host "Chart canvas exists" -ForegroundColor Green
    }

    # Take screenshot
    Take-Screenshot -OutputPath "bar-chart-test.png"

    # Get performance
    $perf = Get-PerformanceMetrics
    Write-Host "Load time: $($perf.totalTime)ms" -ForegroundColor Cyan
}
else {
    Write-Error "Chart failed to load"
}
```

---

## Advanced Features

### 1. Console Log Forwarding

All browser console messages are automatically forwarded to PowerShell:

```javascript
// In browser
console.log("Info message");
console.warn("Warning message");
console.error("Error message");
```

```
[Browser Log] Info message
[Browser Warning] Warning message
[Browser Error] Error message
```

### 2. JavaScript Evaluation

Execute any JavaScript in the browser context:

```powershell
# Simple evaluation
Invoke-JavaScript -Script "2 + 2" -ReturnByValue  # Returns: 4

# Access DOM
Invoke-JavaScript -Script "document.title" -ReturnByValue  # Returns page title

# Complex operations
$chartData = Invoke-JavaScript -Script @"
(function() {
    const chart = document.querySelector('area-chart');
    return {
        hasChart: chart !== null,
        chartType: chart?.chartConfig?.chartType
    };
})()
"@ -ReturnByValue
```

### 3. DOM Manipulation

```powershell
# Set attributes
Set-ElementAttribute -Selector ".card" -Attribute "data-test" -Value "true"

# Click elements
Click-Element -Selector "button.refresh-btn"

# Read text
$text = Get-ElementText -Selector ".card-title"

# Check existence
if (Test-ElementExists -Selector ".error-message") {
    Write-Warning "Error message displayed"
}
```

### 4. Screenshot Capture

```powershell
# Take screenshot
Take-Screenshot -OutputPath "screenshot.png"

# Screenshot without path (auto-generated name)
Take-Screenshot  # Saves as screenshot_20260112_143022.png
```

### 5. Performance Metrics

```powershell
$perf = Get-PerformanceMetrics
# Returns:
# {
#   "domContentLoaded": 45,
#   "loadComplete": 123,
#   "domInteractive": 89,
#   "totalTime": 234
# }
```

---

## Common Use Cases

### 1. Testing New Chart Components

```powershell
# Test bar chart implementation
.\Quick-BrowserTest.ps1 -TestUrl "/apps/uplot/api/v1/ui/elements/bar-chart?chartId=test1" -Interactive

# In interactive mode:
Test> wait .bar-chart-container
Test> exists #chartContainer
Test> eval document.querySelector('#chartContainer canvas').width
Test> screenshot bar-chart-loaded.png
Test> click button#refreshBtn
```

### 2. Testing Card Header Fix

```powershell
.\MSEdgeSessionDebugging-Enhanced.ps1 -Url "http://localhost:8888" -Interactive

Test> wait .card-header
Test> eval window.getComputedStyle(document.querySelector('.card-header')).display
Result: "flex"

Test> eval window.getComputedStyle(document.querySelector('.card-header')).justifyContent
Result: "space-between"

Test> exists .card-actions
Exists: True

Test> eval document.querySelector('.card-actions').parentElement.className
Result: "card-header"
```

### 3. Testing Console Logger

```powershell
.\MSEdgeSessionDebugging-Enhanced.ps1 -Url "http://localhost:8888/apps/uplot/api/v1/ui/elements/area-chart" -ForwardConsole

# Browser console.log messages will appear in PowerShell:
[Browser Log] Time Series Chart Component loaded for chart: test1
[Browser Info] Initializing area chart
[Browser Log] Chart created successfully
```

### 4. Validating Data Flow

```powershell
.\MSEdgeSessionDebugging-Enhanced.ps1 -Url "http://localhost:8888/apps/uplot/api/v1/ui/elements/time-series" -Interactive

Test> wait #chartContainer
Test> eval document.querySelector('time-series').chart.data
# Returns chart data array

Test> click button#refreshBtn
# Watch for console messages about data fetch

Test> eval document.querySelector('time-series').chart.data.length
# Verify data updated
```

### 5. Testing Error Handling

```powershell
.\MSEdgeSessionDebugging-Enhanced.ps1 -Url "http://localhost:8888/apps/uplot/api/v1/ui/elements/bar-chart?chartId=invalid" -ForwardConsole

# Watch for errors:
[Browser Error] Failed to fetch chart data
[Browser Exception] TypeError: Cannot read property 'data' of undefined at component.js:168:12
```

---

## Troubleshooting

### Edge Doesn't Launch

**Problem**: Edge fails to start or debugging port doesn't respond

**Solutions**:
- Ensure Edge is installed at standard location
- Check if port 9222 is already in use: `netstat -ano | findstr 9222`
- Kill existing Edge debug sessions: `Get-Process msedge | Stop-Process`
- Use different debug port: `-DebugPort 9223`

### WebSocket Connection Fails

**Problem**: Can't connect to DevTools WebSocket

**Solutions**:
- Increase wait time (Edge may be slow to start)
- Check firewall settings
- Verify Edge launched with `--remote-debugging-port`

### Console Messages Not Appearing

**Problem**: Browser console.log doesn't show in PowerShell

**Solutions**:
- Ensure `-ForwardConsole` is enabled
- Check if Runtime domain is enabled
- Verify WebSocket connection is active

### Element Not Found

**Problem**: `Test-ElementExists` returns false for existing element

**Solutions**:
- Use `Wait-ForElement` to allow time for rendering
- Check if element is in shadow DOM (not supported)
- Verify selector syntax
- Use browser DevTools to test selector first

### JavaScript Evaluation Errors

**Problem**: `Invoke-JavaScript` returns error

**Solutions**:
- Check JavaScript syntax
- Wrap code in IIFE: `(function() { ... })()`
- Use try/catch in JavaScript
- Check browser console for errors

---

## Best Practices

1. **Always Start WebHost First**
   ```powershell
   # Terminal 1
   .\WebHost.ps1

   # Terminal 2
   .\tests\Quick-BrowserTest.ps1 -TestUrl "/..."
   ```

2. **Use Wait-ForElement**
   ```powershell
   # Good
   Wait-ForElement -Selector ".chart-container"
   Click-Element -Selector "button.refresh-btn"

   # Bad (may fail if page not loaded)
   Click-Element -Selector "button.refresh-btn"
   ```

3. **Verify State Before Actions**
   ```powershell
   if (Test-ElementExists -Selector "button.settings-icon") {
       Click-Element -Selector "button.settings-icon"
   }
   ```

4. **Capture Screenshots for Evidence**
   ```powershell
   Take-Screenshot -OutputPath "before-click.png"
   Click-Element -Selector "button"
   Start-Sleep -Seconds 1
   Take-Screenshot -OutputPath "after-click.png"
   ```

5. **Use Verbose Mode for Debugging**
   ```powershell
   $VerbosePreference = 'Continue'
   .\MSEdgeSessionDebugging-Enhanced.ps1 -Url "..." -Verbose
   ```

---

## Integration with Twin Tests

You can integrate browser testing into twin test framework:

```powershell
# In apps/UI_Uplot/tests/twin/browser-tests.js
async testBarChartLoading() {
    // Use PowerShell to verify server-side
    const psTest = await this.apiCall('/apps/uplot/api/v1/test/bar-chart');

    // Continue with browser tests
    const chart = document.querySelector('bar-chart');
    if (!chart) throw new Error('Bar chart not loaded');

    return 'Bar chart loaded successfully';
}
```

---

## See Also

- [Twin Test Framework](../system/utility/templates/TWIN_TESTS_README.md)
- [UI_Uplot Architecture](../apps/UI_Uplot/Architecture.md)
- [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/)
