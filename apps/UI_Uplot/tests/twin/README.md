# UI_Uplot Twin Tests

Comprehensive tests for the UI_Uplot app.

## Description

Comprehensive test suite for the UI_Uplot app, covering CLI functionality, browser components, and API integration.

## Running Tests

### All Tests
```powershell
.\UI_Uplot.Tests.ps1 -TestMode All
```

### CLI Tests Only
```powershell
.\UI_Uplot.Tests.ps1 -TestMode CLI
```

### Integration Tests Only
```powershell
.\UI_Uplot.Tests.ps1 -TestMode Integration
```

### Browser Tests
1. Start PSWebHost: `pwsh WebHost.ps1`
2. Navigate to: http://localhost:8888/apps/UnitTests/cards/unit-test-runner
3. Select "UI_Uplot Browser Tests"
4. Click "Run Tests"

## Test Coverage

### CLI Tests
- [ ] Module loading
- [ ] Function availability
- [ ] Business logic
- [ ] Data transformations
- [ ] Error handling

### Browser Tests
- [ ] Component loading
- [ ] UI rendering
- [ ] Event handling
- [ ] API integration
- [ ] Local storage

### Integration Tests
- [ ] Status endpoint
- [ ] UI element endpoints
- [ ] CRUD operations
- [ ] Authentication
- [ ] Authorization

## Adding Tests

### PowerShell Test
Edit UI_Uplot.Tests.ps1:
```powershell
function Test-CLIFunctionality {
    Test-Assert -TestName "Your New Test"
        -Condition ($actual -eq $expected)
        -Message "Should do something"
}
```

### Browser Test
Edit browser-tests.js:
```javascript
async testYourFeature() {
    const result = await this.apiCall('/endpoint');
    if (!result.success) {
        throw new Error('Should succeed');
    }
    return 'Feature works';
}
```

## Documentation
See [Twin Test Framework README](../../../system/utility/templates/TWIN_TESTS_README.md)
