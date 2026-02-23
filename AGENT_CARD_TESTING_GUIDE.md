# Agent-Based Card Testing System

## Quick Start

### Option 1: Run Automated Test Script

```powershell
cd C:\SC\PsWebHost
.\test_all_cards_automated.ps1 -FixIssues -ExportReport
```

### Option 2: Spawn Testing Agent

Use Claude's Task tool to spawn an agent that will continuously test and fix cards:

```
Launch an agent to systematically test all 50 UI cards in PSWebHost. For each card:
1. Open the card using window.cardManager.openCard()
2. Validate DOM rendering
3. Check for UI elements (headers, buttons, inputs)
4. Test for JavaScript errors
5. Verify interactive elements work
6. Fix any issues found
7. Report results

Use the test_all_cards_automated.ps1 script as a starting point, and enhance it to:
- Run tests in parallel where possible
- Take screenshots of failed cards
- Automatically fix common issues
- Generate detailed HTML report with visual comparisons
```

---

## System Architecture

```
┌─────────────────────────────────────────┐
│   Test Orchestrator                     │
│   (test_all_cards_automated.ps1)        │
└─────────────────┬───────────────────────┘
                  │
        ┌─────────┴─────────┐
        │                   │
        ▼                   ▼
┌──────────────────┐  ┌──────────────────┐
│  Debug Command   │  │  HTTP Endpoints  │
│  System          │  │  /api/v1/ui      │
└────────┬─────────┘  └─────────┬────────┘
         │                      │
         └───────────┬──────────┘
                     │
         ┌───────────▼───────────┐
         │   Browser Session     │
         │   - cardManager       │
         │   - DOM Inspector     │
         │   - Event Handlers    │
         └───────────────────────┘
```

---

## What Gets Tested

### 50 UI Cards Discovered:

**Core Cards (14):**
- main-menu, system-status, database-status, job-status
- system-log, event-stream, help-viewer, markdown-viewer
- nodes-manager, site-settings, memory-explorer, apps-manager

**App Cards (36):**
- **File Explorer:** file-explorer, text-editor, hex-editor, file-sharing-modal
- **Task Management:** task-manager
- **Metrics:** memory-histogram, server-heatmap
- **Debug Tools:** debug-console, debug-variables
- **Databases:** sqlite-manager, sqlite-query-editor, mysql-manager, redis-manager, sqlserver-manager
- **System Admin:** service-control, task-scheduler, docker-manager, kubernetes-status, linux-services, linux-cron, wsl-manager
- **Charts:** uplot-home, time-series, area-chart, bar-chart, scatter-plot, multi-axis, heatmap
- **Misc:** vault-manager, world-map, unit-test-runner, realtime-events

---

## Test Process Per Card

### Phase 1: Endpoint Validation ✅
```powershell
GET /api/v1/ui/elements/{card-name}
Authorization: Bearer <api-key>

Expected:
- 200 OK
- HTML/JavaScript response
- Component definition present
```

### Phase 2: Code Analysis ✅
- Check for `window.cardComponents` registration
- Verify component class/function definition
- Scan for error patterns (TODO, FIXME, console.error)
- Validate syntax structure

### Phase 3: DOM Rendering ✅
```javascript
// Open card in browser
await window.cardManager.openCard('card-name');

// Validate structure
const card = document.querySelector('.card[data-card-name="card-name"]');
- Has header? ✓
- Has body? ✓
- Has close button? ✓
- No runtime errors? ✓
- Visible content? ✓
```

### Phase 4: UI Element Validation ✅
```javascript
// Count interactive elements
- Buttons: document.querySelectorAll('button').length
- Inputs: document.querySelectorAll('input').length
- Selects: document.querySelectorAll('select').length
- Clickable: document.querySelectorAll('[onclick], .btn').length
```

### Phase 5: Interaction Testing 🔧
- Click buttons (verify no errors)
- Fill inputs (verify validation)
- Submit forms (verify AJAX calls)
- Test keyboard shortcuts
- Verify responsive behavior

### Phase 6: Issue Detection & Fixing 🔧
**Common Issues:**
- Missing component registration → Add pattern
- No close button → Inject standard button
- Missing header → Add default header
- Empty body → Add placeholder content
- JavaScript errors → Wrap in try-catch
- Missing styles → Inject base styles

---

## Automated Testing Script

### Features

**Discovery:**
- Automatically finds all 50 cards
- Filters by pattern: `-CardFilter "*file*"`
- Groups by app

**Testing:**
- ✅ Endpoint response validation
- ✅ Component registration check
- ✅ DOM rendering verification
- ✅ UI element counting
- ✅ Error detection
- ✅ Visual content validation

**Reporting:**
- Pass/Fail/Warning status per card
- Detailed issue list
- Execution time tracking
- JSON export: `-ExportReport`

**Auto-Fixing:**
- Enable with `-FixIssues` flag
- Patches common problems
- Logs all fixes made
- Validates fixes work

### Usage Examples

**Test all cards:**
```powershell
.\test_all_cards_automated.ps1
```

**Test specific cards:**
```powershell
.\test_all_cards_automated.ps1 -CardFilter "*file*"
.\test_all_cards_automated.ps1 -CardFilter "task-manager"
```

**Test with auto-fix:**
```powershell
.\test_all_cards_automated.ps1 -FixIssues
```

**Full diagnostic with export:**
```powershell
.\test_all_cards_automated.ps1 -FixIssues -ExportReport
```

**Output:**
```
========================================
PSWebHost Card Testing System
========================================

Setup: Creating temporary API key...
✅ API key created

Discovering UI cards...
Found 50 cards matching filter '*'

========================================
Testing Cards
========================================

  Testing: file-explorer
    App: WebhostFileExplorer
    Endpoint: /api/v1/ui/elements/file-explorer
    ✅ Endpoint responds (200 OK)
    ✅ Component registration found
    ✅ Component definition found
    → Opening card in browser...
    ✅ Card rendered in DOM
      Elements: 247
      ✅ Has header
      ✅ Has body/content
      ✅ Has close button
      ✅ No runtime errors
      ✅ Has visible content
    → Testing UI interactions...
      ✅ Has 15 interactive elements
         Buttons: 8
         Inputs: 5
         Selects: 2

[... 49 more cards ...]

========================================
Test Summary
========================================
Cards Tested: 50
  ✅ Passed: 45
  ❌ Failed: 3
  ⚠️  Warnings: 2

Total Tests Run: 350
  ✅ Passed: 320
  ❌ Failed: 15
  ⚠️  Warnings: 15

🔧 Issues Fixed: 8

📄 Report exported: card_test_report_20260201_203045.json

========================================
Failed Cards
========================================

old-broken-card (Legacy)
  Endpoint: /api/v1/ui/elements/old-broken-card
  Issues:
    - No component definition found
    - Card did not render in DOM
    - Runtime error: Cannot read property 'map' of undefined

========================================
Testing Complete
========================================
```

---

## Agent-Based Continuous Testing

### Setup Continuous Agent

Create an agent that runs tests periodically:

**1. Create Agent Task:**
```
I need you to set up continuous card testing for PSWebHost. Use the test_all_cards_automated.ps1 script to:

1. Test all 50 cards every 30 minutes
2. Automatically fix common issues (-FixIssues)
3. Export reports to timestamped files (-ExportReport)
4. Alert if failure rate exceeds 10%
5. Track issues over time
6. Generate trend analysis

Run the first test now and show me the results.
```

**2. Agent Will:**
- Execute `.\test_all_cards_automated.ps1 -FixIssues -ExportReport`
- Parse results
- Create summary
- Schedule next run
- Monitor trends

### Manual Agent Invocation

From Claude interface:
```
/task Run comprehensive card testing using test_all_cards_automated.ps1 with auto-fix enabled. Report any cards that fail multiple tests.
```

Or use Task tool in code:
```powershell
# Example: Spawn testing agent
$agentPrompt = @"
Test all PSWebHost UI cards using test_all_cards_automated.ps1.
For each failing card:
1. Identify the root cause
2. Apply fixes automatically
3. Re-test to verify fix
4. Document changes made

Prioritize cards with missing DOM elements or JavaScript errors.
"@

# This would be called from within Claude Code
Task -subagent_type "general-purpose" -prompt $agentPrompt -description "Card testing agent"
```

---

## Advanced: Custom Testing Agent

### Create Specialized Testing Agent

**File:** `.claude/agents/card-tester.md`

```markdown
# Card Testing Agent

## Purpose
Systematically test and fix all UI cards in PSWebHost.

## Capabilities
- Execute test_all_cards_automated.ps1
- Parse test results
- Identify failure patterns
- Apply automated fixes
- Generate visual reports
- Track trends over time

## Tools Available
- Bash (run PowerShell scripts)
- Edit (fix card code)
- Read (analyze card files)
- Grep (find patterns)
- WebFetch (check external dependencies)

## Testing Protocol
1. Run test_all_cards_automated.ps1
2. Parse JSON report
3. For each failed card:
   - Read card source file
   - Identify issue type
   - Apply appropriate fix
   - Re-run test
   - Verify fix
4. Generate summary report
5. Track metrics

## Fix Strategies

### Missing Component Registration
```javascript
// Add at end of file:
window.cardComponents = window.cardComponents || {};
window.cardComponents['card-name'] = ComponentName;
```

### Missing Close Button
```javascript
// Add to render method:
React.createElement('button', {
    className: 'card-close',
    onClick: () => window.cardManager.closeCard('card-name')
}, '×')
```

### Runtime Errors
```javascript
// Wrap unsafe code:
try {
    // existing code
} catch (error) {
    console.error('Card error:', error);
    return React.createElement('div', { className: 'error' },
        'Failed to load card: ' + error.message
    );
}
```

## Success Criteria
- 95%+ pass rate
- No critical failures
- All cards render in DOM
- Interactive elements functional
- No JavaScript errors
```

---

## Integration with CI/CD

### Pre-Commit Hook
```powershell
# .git/hooks/pre-commit (PowerShell)
cd C:\SC\PsWebHost
.\test_all_cards_automated.ps1 -CardFilter "*"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Card tests failed! Fix issues before committing." -ForegroundColor Red
    exit 1
}
```

### GitHub Actions
```yaml
name: Card Tests
on: [push, pull_request]

jobs:
  test-cards:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v2
      - name: Start PSWebHost
        run: Start-Process pwsh -ArgumentList "-File WebHost.ps1"
      - name: Wait for server
        run: Start-Sleep -Seconds 10
      - name: Run card tests
        run: .\test_all_cards_automated.ps1 -ExportReport
      - name: Upload report
        uses: actions/upload-artifact@v2
        with:
          name: card-test-report
          path: card_test_report_*.json
```

---

## Monitoring Dashboard

### Real-Time Status

**Create monitoring card:**
```javascript
// apps/Testing/routes/api/v1/ui/elements/card-test-status/get.ps1

const CardTestStatus = () => {
    const [results, setResults] = useState(null);

    useEffect(() => {
        // Load latest test report
        fetch('/api/v1/testing/card-test-results')
            .then(r => r.json())
            .then(data => setResults(data));
    }, []);

    return React.createElement('div', { className: 'card-test-status' },
        React.createElement('h3', null, 'Card Test Status'),
        results && React.createElement('div', null,
            `✅ Passed: ${results.PassedCards} / ${results.TotalCards}`,
            `❌ Failed: ${results.FailedCards}`,
            `⚠️  Warnings: ${results.WarningCards}`
        )
    );
};
```

---

## Troubleshooting

### "cardManager not available"
**Cause:** Browser doesn't have card management system loaded

**Fix:**
```javascript
// Ensure cardManager is initialized
if (!window.cardManager) {
    console.error('cardManager not loaded - check psweb_spa.js');
}
```

### "Card element not found in DOM"
**Causes:**
1. Card didn't render (JavaScript error)
2. Wrong selector used
3. Card rendered but with different structure

**Fix:**
```javascript
// Debug: Log what's actually in DOM
console.log('Cards in DOM:', document.querySelectorAll('.card'));
console.log('Card bodies:', document.querySelectorAll('.card-body, .card-content'));
```

### Tests timeout
**Causes:**
1. Card takes too long to render
2. Network requests hanging
3. Infinite loops in card code

**Fix:**
```powershell
# Increase timeout
.\test_all_cards_automated.ps1 -TimeoutSeconds 30
```

---

## Best Practices

### 1. Run Tests Regularly
- Before commits
- After major changes
- Daily via scheduled task
- Before releases

### 2. Fix Issues Immediately
- Don't let failures accumulate
- Fix root causes, not symptoms
- Document fixes in CHANGELOG

### 3. Monitor Trends
- Track pass rate over time
- Identify problematic cards
- Measure fix effectiveness

### 4. Keep Reports
- Archive JSON reports
- Compare over time
- Identify regressions

### 5. Automate Fixes
- Build fix library
- Apply common patterns
- Validate fixes work

---

## Summary

**System Created:**
- ✅ Automated test script (`test_all_cards_automated.ps1`)
- ✅ Tests 50 UI cards automatically
- ✅ Validates rendering, DOM, UI elements
- ✅ Auto-fixes common issues
- ✅ Exports detailed reports
- ✅ Agent-friendly design

**To Launch Agent:**
```
Launch a general-purpose agent to run continuous card testing using test_all_cards_automated.ps1. Test all 50 cards, fix issues automatically, and report results.
```

**Status:** Ready for automated testing!
