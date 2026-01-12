#Requires -Version 7

<#
.SYNOPSIS
    Scaffolds twin test files for a PSWebHost app

.DESCRIPTION
    Creates CLI and browser test files from templates for the specified app.
    Automatically customizes templates with app-specific information.

.PARAMETER AppName
    Name of the app to create tests for

.PARAMETER Force
    Overwrite existing test files

.EXAMPLE
    .\New-TwinTests.ps1 -AppName "Vault"
    Creates twin tests for the Vault app

.EXAMPLE
    .\New-TwinTests.ps1 -AppName "UI_Uplot" -Force
    Recreates twin tests for UI_Uplot, overwriting existing files
#>

param(
    [Parameter(Mandatory)]
    [string]$AppName,

    [switch]$Force
)

# Determine project root
$ProjectRoot = $PSScriptRoot -replace '[/\\]system[/\\].*'

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Twin Test Scaffolder" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Validate app exists
$appPath = Join-Path $ProjectRoot "apps\$AppName"
if (-not (Test-Path $appPath)) {
    Write-Host "ERROR: App not found: $appPath" -ForegroundColor Red
    exit 1
}

Write-Host "App: $AppName" -ForegroundColor White
Write-Host "Path: $appPath" -ForegroundColor Gray
Write-Host ""

# Create tests directory
$testsDir = Join-Path $appPath "tests\twin"
if (-not (Test-Path $testsDir)) {
    New-Item -Path $testsDir -ItemType Directory -Force | Out-Null
    Write-Host "[Created] $testsDir" -ForegroundColor Green
} else {
    Write-Host "[Exists] $testsDir" -ForegroundColor Yellow
}

# Load app metadata
$appYamlPath = Join-Path $appPath "app.yaml"
$appMetadata = @{
    Name = $AppName
    Description = "PSWebHost App"
    Version = "1.0.0"
    RoutePrefix = "/apps/$($AppName.ToLower())"
}

if (Test-Path $appYamlPath) {
    $yamlContent = Get-Content $appYamlPath -Raw
    if ($yamlContent -match 'version:\s*(.+)') {
        $appMetadata.Version = $matches[1].Trim()
    }
    if ($yamlContent -match 'description:\s*(.+)') {
        $appMetadata.Description = $matches[1].Trim()
    }
    if ($yamlContent -match 'routePrefix:\s*(.+)') {
        $appMetadata.RoutePrefix = $matches[1].Trim()
    }
}

Write-Host "Metadata:" -ForegroundColor Cyan
Write-Host "  Version: $($appMetadata.Version)" -ForegroundColor Gray
Write-Host "  Description: $($appMetadata.Description)" -ForegroundColor Gray
Write-Host "  Route Prefix: $($appMetadata.RoutePrefix)" -ForegroundColor Gray
Write-Host ""

# Generate PowerShell twin test
$psTestPath = Join-Path $testsDir "$AppName.Tests.ps1"
if ((Test-Path $psTestPath) -and -not $Force) {
    Write-Host "[Skip] $psTestPath (already exists, use -Force to overwrite)" -ForegroundColor Yellow
} else {
    $templatePath = Join-Path $ProjectRoot "system\utility\templates\twin-test-template.ps1"
    $template = Get-Content $templatePath -Raw

    # Customize template
    $template = $template -replace 'YourAppName', $AppName
    $template = $template -replace 'YourModuleName', "PSWeb$AppName"
    $template = $template -replace 'Your-Function', "Get-$AppName"
    $template = $template -replace '\$AppName\.ToLower\(\)', $AppName.ToLower()

    # Save
    Set-Content -Path $psTestPath -Value $template -Encoding UTF8
    Write-Host "[Created] $psTestPath" -ForegroundColor Green
}

# Generate JavaScript browser test
$jsTestPath = Join-Path $testsDir "browser-tests.js"
if ((Test-Path $jsTestPath) -and -not $Force) {
    Write-Host "[Skip] $jsTestPath (already exists, use -Force to overwrite)" -ForegroundColor Yellow
} else {
    $templatePath = Join-Path $ProjectRoot "system\utility\templates\browser-test-template.js"
    $template = Get-Content $templatePath -Raw

    # Customize template
    $template = $template -replace 'AppNameBrowserTests', "${AppName}BrowserTests"
    $template = $template -replace 'YourAppName', $AppName
    $template = $template -replace 'yourappname', $AppName.ToLower()
    $template = $template -replace 'your-component', "$($AppName.ToLower())-home"

    # Save
    Set-Content -Path $jsTestPath -Value $template -Encoding UTF8
    Write-Host "[Created] $jsTestPath" -ForegroundColor Green
}

# Generate README
$readmePath = Join-Path $testsDir "README.md"
if ((Test-Path $readmePath) -and -not $Force) {
    Write-Host "[Skip] $readmePath (already exists, use -Force to overwrite)" -ForegroundColor Yellow
} else {
    $readme = @"
# $AppName Twin Tests

Comprehensive tests for the $AppName app.

## Description
$($appMetadata.Description)

## Running Tests

### All Tests
``````powershell
.\$AppName.Tests.ps1 -TestMode All
``````

### CLI Tests Only
``````powershell
.\$AppName.Tests.ps1 -TestMode CLI
``````

### Integration Tests Only
``````powershell
.\$AppName.Tests.ps1 -TestMode Integration
``````

### Browser Tests
1. Start PSWebHost: `pwsh WebHost.ps1`
2. Navigate to: http://localhost:8888/apps/unittests/api/v1/ui/elements/unit-test-runner
3. Select "$AppName Browser Tests"
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
Edit `$AppName.Tests.ps1`:
``````powershell
function Test-CLIFunctionality {
    Test-Assert -TestName "Your New Test" `
        -Condition (\$result -eq \$expected) `
        -Message "Should do something"
}
``````

### Browser Test
Edit `browser-tests.js`:
``````javascript
async testYourFeature() {
    const result = await this.apiCall('/endpoint');
    if (!result.success) {
        throw new Error('Should succeed');
    }
    return 'Feature works';
}
``````

## Documentation
See [Twin Test Framework README](../../../system/utility/templates/TWIN_TESTS_README.md)
"@

    Set-Content -Path $readmePath -Value $readme -Encoding UTF8
    Write-Host "[Created] $readmePath" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Scaffolding Complete!" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Edit $psTestPath" -ForegroundColor White
Write-Host "2. Edit $jsTestPath" -ForegroundColor White
Write-Host "3. Run tests: .\$AppName.Tests.ps1" -ForegroundColor White
Write-Host ""
Write-Host "Test directory: $testsDir" -ForegroundColor Cyan
Write-Host ""
