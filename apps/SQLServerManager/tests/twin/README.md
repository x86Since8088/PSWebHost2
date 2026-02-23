# SQLServerManager Twin Tests

Comprehensive tests for the SQLServerManager app.

## Description
Microsoft SQL Server administration

## Running Tests

### All Tests
```powershell
.\SQLServerManager.Tests.ps1 -TestMode All
```

### CLI Tests Only
```powershell
.\SQLServerManager.Tests.ps1 -TestMode CLI
```

### Integration Tests Only
```powershell
.\SQLServerManager.Tests.ps1 -TestMode Integration
```

### Browser Tests
1. Start PSWebHost: `pwsh WebHost.ps1`
2. Navigate to: http://localhost:8888/apps/UnitTests/cards/unit-test-runner
3. Select "SQLServerManager Browser Tests"
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
Edit SQLServerManager.Tests.ps1:
```powershell
function Test-CLIFunctionality {
    Test-Assert -TestName "Your New Test"
        -Condition ($result -eq $expected)
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
