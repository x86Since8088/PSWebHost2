# DockerManager Twin Tests

Comprehensive tests for the DockerManager app.

## Description
Docker container and image management

## Running Tests

### All Tests
```powershell
.\DockerManager.Tests.ps1 -TestMode All
```

### CLI Tests Only
```powershell
.\DockerManager.Tests.ps1 -TestMode CLI
```

### Integration Tests Only
```powershell
.\DockerManager.Tests.ps1 -TestMode Integration
```

### Browser Tests
1. Start PSWebHost: pwsh WebHost.ps1
2. Navigate to: http://localhost:8888/apps/unittests/api/v1/ui/elements/unit-test-runner
3. Select "DockerManager Browser Tests"
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
Edit $AppName.Tests.ps1:
```powershell
function Test-CLIFunctionality {
    Test-Assert -TestName "Your New Test" 
        -Condition (\ -eq \) 
        -Message "Should do something"
}
```

### Browser Test
Edit rowser-tests.js:
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
