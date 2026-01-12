# PSWebHost Twin Test Framework

Comprehensive testing framework for PSWebHost apps supporting both CLI (PowerShell) and Browser (JavaScript) testing.

## Overview

**Twin Tests** provide complete coverage for PSWebHost apps by testing:
- **CLI Tests**: Backend PowerShell logic, modules, and functions
- **Browser Tests**: Frontend JavaScript components and UI
- **Integration Tests**: API endpoints and data flow
- **End-to-End Tests**: Complete user workflows

## Quick Start

### 1. Generate Tests for Your App

```powershell
# From project root
.\system\utility\New-TwinTests.ps1 -AppName "YourApp"
```

This creates:
```
apps/YourApp/tests/twin/
├── YourApp.Tests.ps1       # PowerShell twin tests
├── browser-tests.js         # JavaScript browser tests
└── README.md                # App-specific test documentation
```

### 2. Run Tests

#### Run All Twin Tests (All Apps)
```powershell
.\tests\twin\Run-AllTwinTests.ps1
```

#### Run Specific App Tests
```powershell
cd apps/YourApp/tests/twin
.\YourApp.Tests.ps1 -TestMode All
```

#### Run Only CLI Tests
```powershell
.\YourApp.Tests.ps1 -TestMode CLI
```

#### Run Only Integration Tests
```powershell
.\YourApp.Tests.ps1 -TestMode Integration
```

#### Run Browser Tests
1. Start PSWebHost server
2. Navigate to: `http://localhost:8888/apps/unittests/api/v1/ui/elements/unit-test-runner`
3. Select your app's test suite
4. Click "Run Tests"

## Test Structure

### PowerShell Twin Tests (AppName.Tests.ps1)

```powershell
#Requires -Version 7

param(
    [ValidateSet('CLI', 'Browser', 'Integration', 'All')]
    [string]$TestMode = 'All',
    [string]$BaseUrl = 'http://localhost:8888'
)

# Test CLI functionality
function Test-CLIFunctionality {
    # Test modules, functions, logic
    Test-Assert -TestName "Module Loads" `
        -Condition (Get-Module MyModule) `
        -Message "Module should load"
}

# Test API integration
function Test-IntegrationFunctionality {
    Invoke-ApiTest -TestName "Status Endpoint" `
        -Endpoint "/apps/myapp/api/v1/status" `
        -ExpectedStatusCode 200
}
```

### Browser Twin Tests (browser-tests.js)

```javascript
const MyAppBrowserTests = {
    suiteName: 'MyApp Browser Tests',

    async setup() {
        // Initialize test environment
    },

    async testComponentLoading() {
        // Test component initialization
    },

    async testAPIEndpoint() {
        // Test API from browser
    },

    async teardown() {
        // Cleanup
    }
};

// Register with UnitTests framework
window.TestSuites.register(MyAppBrowserTests);
```

## Helper Functions

### PowerShell Helpers

#### Test-Assert
```powershell
Test-Assert -TestName "Descriptive Name" `
    -Condition ($result -eq $expected) `
    -Message "Should return expected value"
```

#### Invoke-ApiTest
```powershell
Invoke-ApiTest -TestName "Create Item" `
    -Endpoint "/apps/myapp/api/v1/items" `
    -Method 'POST' `
    -Body @{ name = "Test" } `
    -ExpectedStatusCode 201
```

### JavaScript Helpers

#### apiCall
```javascript
const data = await this.apiCall('/apps/myapp/api/v1/data', {
    method: 'POST',
    body: { name: 'Test' }
});
```

#### loadScript
```javascript
await this.loadScript('/public/lib/mylib.js');
```

## Test Categories

### 1. CLI Tests
Test backend PowerShell code:
- Module imports
- Function availability
- Business logic
- Data transformations
- File operations
- Database queries (via mocks)

### 2. Browser Tests
Test frontend JavaScript code:
- Component loading
- DOM manipulation
- Event handling
- Local storage
- Async operations
- Error handling

### 3. Integration Tests
Test API endpoints:
- HTTP status codes
- Response formats
- Authentication
- Authorization
- Data validation
- Error responses

### 4. End-to-End Tests
Test complete workflows:
- User registration → login → action → logout
- Create → read → update → delete
- File upload → process → download
- Multi-step wizards

## Best Practices

### 1. Test Naming
Use descriptive, actionable names:
- ✅ "Module Loads Successfully"
- ✅ "API Returns 404 for Missing Item"
- ❌ "Test 1"
- ❌ "Check thing"

### 2. Test Independence
Each test should:
- Setup its own data
- Not depend on other tests
- Clean up after itself
- Be runnable in isolation

### 3. Test Coverage
Aim for:
- **CLI**: 80%+ code coverage
- **Browser**: All components tested
- **Integration**: All endpoints tested
- **E2E**: Critical user paths covered

### 4. Fast Tests
- Use mocks for external dependencies
- Parallel test execution where possible
- Skip slow tests in quick runs
- Cache setup data

### 5. Clear Assertions
```powershell
# ✅ Good - specific assertion
Test-Assert -TestName "Returns 3 items" `
    -Condition ($result.Count -eq 3) `
    -Message "Should return exactly 3 items"

# ❌ Bad - vague assertion
Test-Assert -TestName "Works" `
    -Condition ($result) `
    -Message "Should work"
```

## Test Fixtures

### Creating Test Data
```powershell
# Setup test fixtures
$testData = @{
    Users = @(
        @{ Id = 1; Name = "Test User 1" }
        @{ Id = 2; Name = "Test User 2" }
    )
    Settings = @{
        Feature1 = $true
        Feature2 = $false
    }
}
```

### Using Mocks
```powershell
# Mock external API call
Mock Invoke-RestMethod {
    return @{ Success = $true; Data = "Mocked" }
}

# Test function that uses the mocked API
$result = Get-ExternalData
Test-Assert "Uses Mocked API" ($result.Data -eq "Mocked")
```

## Continuous Integration

### Running Tests in CI/CD
```yaml
# GitHub Actions example
- name: Run Twin Tests
  run: |
    pwsh ./tests/twin/Run-AllTwinTests.ps1
```

### Test Output Formats
```powershell
# JSON output for CI parsing
.\YourApp.Tests.ps1 | ConvertTo-Json > test-results.json

# JUnit XML for Jenkins/Azure DevOps
.\YourApp.Tests.ps1 -OutputFormat JUnit > test-results.xml
```

## Troubleshooting

### Tests Fail Locally But Pass in CI
- Check for hardcoded paths
- Verify environment variables
- Check for timezone dependencies
- Look for race conditions

### Browser Tests Don't Run
1. Ensure PSWebHost server is running
2. Check browser console for errors
3. Verify UnitTests app is enabled
4. Clear browser cache

### Slow Test Execution
- Use `-TestMode CLI` to skip integration tests
- Reduce test data size
- Use mocks instead of real APIs
- Run tests in parallel

## Examples

### Complete App Test Example

See `apps/vault/tests/twin/Vault.Tests.ps1` for a production example covering:
- PSWebVault module loading
- Credential CRUD operations
- DPAPI encryption/decryption
- API endpoint testing
- Browser component testing
- Audit log verification

### Integration Test Example

```powershell
function Test-IntegrationFunctionality {
    # Test app status
    Invoke-ApiTest "App Status" `
        "/apps/myapp/api/v1/status" -ExpectedStatusCode 200

    # Test authentication required
    Invoke-ApiTest "Auth Required" `
        "/apps/myapp/api/v1/protected" -ExpectedStatusCode 401

    # Test CRUD workflow
    $item = Invoke-ApiTest "Create Item" `
        -Endpoint "/apps/myapp/api/v1/items" `
        -Method POST `
        -Body @{ name = "Test" } `
        -ExpectedStatusCode 201

    $itemId = ($item.Content | ConvertFrom-Json).id

    Invoke-ApiTest "Read Item" `
        "/apps/myapp/api/v1/items/$itemId" -ExpectedStatusCode 200

    Invoke-ApiTest "Update Item" `
        -Endpoint "/apps/myapp/api/v1/items/$itemId" `
        -Method PUT `
        -Body @{ name = "Updated" } `
        -ExpectedStatusCode 200

    Invoke-ApiTest "Delete Item" `
        -Endpoint "/apps/myapp/api/v1/items/$itemId" `
        -Method DELETE `
        -ExpectedStatusCode 204
}
```

## Contributing

When adding new tests:
1. Follow naming conventions
2. Add documentation
3. Ensure tests are idempotent
4. Clean up test data
5. Update README with new patterns

## Resources

- [Pester Documentation](https://pester.dev)
- [PSWebHost Testing Guide](../../docs/testing.md)
- [JavaScript Testing Best Practices](https://javascript.info/testing)
- [HTTP Status Codes](https://httpstatuses.com)

## Support

For issues or questions:
- Check existing tests in `apps/*/tests/twin/`
- Review troubleshooting section above
- Ask in #testing channel
- Create issue with `[twin-tests]` tag
