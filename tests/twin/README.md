# PSWebHost Twin Test Structure

This directory contains tests organized in a "twin" structure that mirrors the main project's functional folders. Each test file corresponds to a specific component, route, or system script.

## Directory Structure

```
tests/twin/
├── routes/              # Tests for HTTP route handlers
│   ├── api/            # API endpoint tests
│   │   └── v1/
│   │       ├── auth/
│   │       │   └── sessionid/
│   │       │       └── get.Tests.ps1
│   │       └── ui/
│   │           └── elements/
│   │               └── main-menu/
│   │                   └── get.Tests.ps1
│   └── spa/            # SPA endpoint tests
│       └── card_settings/
│           ├── get.Tests.ps1
│           └── post.Tests.ps1
├── system/             # Tests for system scripts
│   ├── Functions.Tests.ps1
│   └── validateInstall.Tests.ps1
├── modules/            # Tests for PowerShell modules
│   └── PSWebHost_Authentication.Tests.ps1
└── public/             # Tests for public assets (future)
```

## Test File Naming Convention

- Test files follow Pester convention: `*.Tests.ps1`
- Route tests are named after the HTTP method: `get.Tests.ps1`, `post.Tests.ps1`, etc.
- Module and system tests are named after the component: `ModuleName.Tests.ps1`

## Test File Template

Every test file must start with this initialization block:

```powershell
# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript
```

This pattern:
1. Calculates the project root by removing everything after `/tests/`
2. Sources the `system/init.ps1` script
3. Ensures all tests have access to project configuration and functions

## Writing Tests

### Basic Structure

```powershell
# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "Component Name" {
    BeforeAll {
        # Setup: Import modules, prepare test data
        $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'
        Import-Module (Join-Path $ProjectRoot 'modules\ModuleName') -DisableNameChecking
    }

    Context "Feature being tested" {
        It "Should behave in expected way" {
            # Test implementation
            $result = Test-Something
            $result | Should -Be $expected
        }
    }

    AfterAll {
        # Cleanup if needed
    }
}
```

### Route Tests

Route tests should validate:
- HTTP status codes
- Response headers (Content-Type, Cache-Control, etc.)
- Response body structure and content
- Authentication requirements
- Error handling

Example:
```powershell
Context "Response validation" {
    It "Should return 200 status code" {
        # Test implementation
    }

    It "Should set Content-Type to application/json" {
        # Test implementation
    }

    It "Should require authentication" {
        # Test implementation
    }
}
```

### Module Tests

Module tests should validate:
- Exported functions exist
- Function parameters are correct
- Functions behave as expected
- Error handling works properly

Example:
```powershell
Context "Module exports" {
    It "Should export Get-Something function" {
        Get-Command Get-Something -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

Context "Function behavior" {
    It "Should accept required parameters" {
        (Get-Command Get-Something).Parameters.ContainsKey('ParamName') | Should -Be $true
    }
}
```

## Running Tests

### Run all tests in twin structure
```powershell
Invoke-Pester -Path C:\SC\PsWebHost\tests\twin -Output Detailed
```

### Run tests for specific component
```powershell
# Run all route tests
Invoke-Pester -Path C:\SC\PsWebHost\tests\twin\routes -Output Detailed

# Run tests for specific endpoint
Invoke-Pester -Path C:\SC\PsWebHost\tests\twin\routes\spa\card_settings -Output Detailed

# Run single test file
Invoke-Pester -Path C:\SC\PsWebHost\tests\twin\routes\spa\card_settings\get.Tests.ps1 -Output Detailed
```

### Run with coverage
```powershell
$config = New-PesterConfiguration
$config.Run.Path = 'C:\SC\PsWebHost\tests\twin'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = 'C:\SC\PsWebHost\routes', 'C:\SC\PsWebHost\system', 'C:\SC\PsWebHost\modules'
Invoke-Pester -Configuration $config
```

## Test Status

Current test files are templates with placeholder assertions (`$true | Should -Be $true`). These need to be replaced with actual test implementations that:

1. Set up test conditions
2. Execute the code being tested
3. Assert expected outcomes
4. Clean up test artifacts

## Migration from Old Tests

Tests from `/tests` folder should be:
1. Reviewed for relevance
2. Refactored to match twin structure
3. Updated to use new initialization pattern
4. Moved to appropriate location in `/tests/twin`

## Best Practices

1. **Isolation**: Each test should be independent and not rely on other tests
2. **Cleanup**: Always clean up test data in `AfterAll` or `AfterEach` blocks
3. **Descriptive Names**: Use clear, descriptive test names that explain what is being tested
4. **Fast Tests**: Keep tests fast by mocking external dependencies
5. **Meaningful Assertions**: Avoid placeholder assertions; test actual behavior
6. **Error Cases**: Test both success and failure scenarios

## Contributing

When adding new features to PSWebHost:
1. Create corresponding test file in twin structure
2. Mirror the project directory structure
3. Use the initialization template
4. Write tests before or alongside implementation
5. Ensure tests pass before committing

## Future Improvements

- [ ] Implement actual test logic (replace placeholders)
- [ ] Add integration tests that start web server
- [ ] Add performance benchmarks
- [ ] Add API contract tests
- [ ] Add security tests (injection, XSS, etc.)
- [ ] Add load tests for critical endpoints
- [ ] Set up CI/CD pipeline for automatic test execution
