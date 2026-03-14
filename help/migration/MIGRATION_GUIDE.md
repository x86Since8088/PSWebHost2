# PSWebHost Migration Tools - Quick Reference Guide

This guide provides step-by-step instructions for migrating components to apps.

---

## Prerequisites

1. Ensure you have the migration tools installed:
   - `system/utility/Analyze-Dependencies.ps1`
   - `system/utility/New-PSWebHostApp.ps1`
   - `system/utility/Move-ComponentToApp.ps1`

2. Run dependency analysis (if not already done):
   ```powershell
   .\system\utility\Analyze-Dependencies.ps1
   ```
   This creates `PsWebHost_Data\system\utility\Analyze-Dependencies.json`

---

## Step 1: Analyze Components

### View Extractability Scores
```powershell
# View top extraction candidates
.\system\utility\Analyze-Dependencies.ps1 -OutputFormat Table

# Export to CSV for detailed analysis
.\system\utility\Analyze-Dependencies.ps1 -OutputFormat CSV -ExportPath "analysis.csv"

# Find components with external tools (platform-specific)
$data = Get-Content PsWebHost_Data\system\utility\Analyze-Dependencies.json | ConvertFrom-Json
$data.Results | Where-Object { $_.ExternalToolCount -gt 0 } |
  Format-Table FilePath, ExternalTools, ExtractabilityScore
```

### Check Component Dependencies
```powershell
# Find all files in a component
$data = Get-Content PsWebHost_Data\system\utility\Analyze-Dependencies.json | ConvertFrom-Json
$data.Results | Where-Object { $_.FilePath -like '*component-name*' } |
  Format-List FilePath, CoreFunctionsUsed, DatabaseAccess, ExtractabilityScore
```

---

## Step 2: Create App

### Basic App Creation
```powershell
.\system\utility\New-PSWebHostApp.ps1 `
  -AppName "MyApp" `
  -DisplayName "My Application" `
  -Description "Application description" `
  -Category "Category Name" `
  -SubCategory "SubCategory Name" `
  -RequiredRoles @('admin')
```

### With Sample Files
```powershell
.\system\utility\New-PSWebHostApp.ps1 `
  -AppName "MyApp" `
  -DisplayName "My Application" `
  -Description "Application description" `
  -Category "Category Name" `
  -SubCategory "SubCategory Name" `
  -CreateSampleRoute `
  -CreateSampleElement
```

### Common Categories

| Category | SubCategory Examples |
|----------|---------------------|
| Operating Systems | Windows, Linux, macOS |
| Containers | Docker, Kubernetes, WSL |
| Databases | MySQL, Redis, SQLite, SQL Server, MongoDB, Vault |
| Monitoring | Metrics, Logs, Health |
| Admin | Users, Roles, Settings |
| Utilities | Tools, Helpers, Documentation |

---

## Step 3: Migrate Components

### Single Component Migration

#### Dry Run (Preview)
```powershell
.\system\utility\Move-ComponentToApp.ps1 `
  -ComponentPath "routes/api/v1/ui/elements/my-component" `
  -TargetApp "MyApp" `
  -WhatIf
```

#### Live Migration
```powershell
.\system\utility\Move-ComponentToApp.ps1 `
  -ComponentPath "routes/api/v1/ui/elements/my-component" `
  -TargetApp "MyApp"
```

#### With Tests and Help
```powershell
.\system\utility\Move-ComponentToApp.ps1 `
  -ComponentPath "routes/api/v1/ui/elements/my-component" `
  -TargetApp "MyApp" `
  -IncludeTests `
  -IncludeHelp
```

### Batch Migration Script Template

Create `migrate-my-category-apps.ps1`:

```powershell
param([switch]$WhatIf)

$projectRoot = $PSScriptRoot
Set-Location $projectRoot

$migrations = @(
    @{
        App = "AppName1"
        Components = @(
            "routes/api/v1/feature1",
            "public/elements/feature1"
        )
    },
    @{
        App = "AppName2"
        Components = @(
            "routes/api/v1/feature2",
            "public/elements/feature2"
        )
    }
)

foreach ($migration in $migrations) {
    Write-Host "`n========== $($migration.App) ==========" -ForegroundColor Cyan

    foreach ($component in $migration.Components) {
        $params = @{
            ComponentPath = $component
            TargetApp = $migration.App
        }
        if ($WhatIf) { $params.WhatIf = $true }

        & ".\system\utility\Move-ComponentToApp.ps1" @params
    }
}
```

Run with:
```powershell
# Preview
.\migrate-my-category-apps.ps1 -WhatIf

# Execute
.\migrate-my-category-apps.ps1
```

---

## Step 4: Update Menu Configuration

### Manual Menu Update

Edit `apps/MyApp/menu.yaml`:

```yaml
# Menu entries for My Application
# These will be integrated into the main PSWebHost menu under:
# Category Name > SubCategory Name

- Name: Feature Name
  url: /api/v1/ui/elements/my-feature
  hover_description: Description of the feature
  icon: icon-name
  tags:
    - category-tag
    - feature-tag
```

### Bulk Menu Update Script

Create `update-my-menus.ps1`:

```powershell
$menus = @{
    "App1" = @"
- Name: Feature 1
  url: /api/v1/ui/elements/feature1
  hover_description: Feature 1 description
  icon: settings
  tags:
    - tag1
"@

    "App2" = @"
- Name: Feature 2
  url: /api/v1/ui/elements/feature2
  hover_description: Feature 2 description
  icon: database
  tags:
    - tag2
"@
}

foreach ($app in $menus.Keys) {
    $menuPath = "apps\$app\menu.yaml"
    $menus[$app] | Out-File $menuPath -Encoding UTF8
    Write-Host "Updated $menuPath" -ForegroundColor Green
}
```

---

## Step 5: Cleanup

### Remove Empty Directories
```powershell
# Find empty directories
find routes/api/v1/ui/elements routes/api/v1/system public/elements -type d -empty

# Remove specific directories
rmdir routes/api/v1/ui/elements/old-component
rmdir public/elements/old-component
```

### Verify Migration
```powershell
# List files in app
Get-ChildItem -Path "apps\MyApp" -Recurse -File |
  Where-Object { $_.Extension -in @('.ps1', '.js', '.json') } |
  Select-Object FullName

# Count migrated files
(Get-ChildItem -Path "apps\MyApp" -Recurse -File -Include *.ps1,*.js).Count
```

---

## Step 6: Test

### Restart PSWebHost
```powershell
# Stop current instance (if running)
# Then start with:
.\WebHost.ps1 -Port 8888 -Async
```

### Test Endpoints
```powershell
# Test route
Invoke-RestMethod -Uri "http://localhost:8888/api/v1/ui/elements/my-feature"

# Test with authentication
$headers = @{ Authorization = "Bearer YOUR_API_KEY" }
Invoke-RestMethod -Uri "http://localhost:8888/api/v1/ui/elements/my-feature" -Headers $headers
```

### Verify Menu Integration
1. Navigate to main menu
2. Check category appears correctly
3. Verify subcategory grouping
4. Test feature links

---

## Troubleshooting

### Issue: Files Not Found During Migration

**Symptom:** "SKIP (not found)" messages

**Solutions:**
1. Check if file was already moved:
   ```powershell
   Get-ChildItem -Path "apps\MyApp" -Recurse -Filter "filename.ps1"
   ```

2. Verify component path:
   ```powershell
   Test-Path "routes/api/v1/ui/elements/component-name"
   ```

3. Check dependency analysis includes the file:
   ```powershell
   $data = Get-Content PsWebHost_Data\system\utility\Analyze-Dependencies.json | ConvertFrom-Json
   $data.Results | Where-Object { $_.FilePath -like '*component-name*' }
   ```

### Issue: Path Separator Errors

**Symptom:** Files not matched despite existing

**Solution:** Use forward slashes in ComponentPath parameter:
```powershell
# Correct
-ComponentPath "routes/api/v1/feature"

# Incorrect
-ComponentPath "routes\api\v1\feature"
```

### Issue: Duplicate Files in Migration

**Symptom:** Same file listed twice in WOULD MOVE

**Solution:** Deduplication is working - only one copy will be moved. Verify with:
```powershell
# After migration, check for duplicates
Get-ChildItem -Path "apps\MyApp" -Recurse -File |
  Group-Object Name |
  Where-Object { $_.Count -gt 1 }
```

### Issue: Menu Not Appearing

**Solutions:**
1. Check menu.yaml syntax (YAML is whitespace-sensitive)
2. Verify app.json has correct category/subcategory
3. Restart PSWebHost to reload apps
4. Check app is enabled: `"enabled": true` in app.json

### Issue: Routes Not Working

**Solutions:**
1. Verify route file location matches URL structure
2. Check security.json has correct format:
   ```json
   {
     "Allowed_Roles": ["role1", "role2"]
   }
   ```
3. Ensure app route prefix in app.json
4. Check app initialization in server logs

---

## Best Practices

### 1. Always Preview First
```powershell
# Always run WhatIf before actual migration
.\migrate-script.ps1 -WhatIf
```

### 2. Check Extractability Scores
- **80-100:** Safe to extract
- **60-79:** Review dependencies first
- **<60:** May need core framework changes

### 3. Migrate Related Files Together
```powershell
# Include tests and help files
-IncludeTests -IncludeHelp
```

### 4. Document Changes
- Update app README.md
- Update CHANGELOG if maintaining one
- Add migration notes

### 5. Test Incrementally
- Migrate one category at a time
- Test after each migration
- Commit working state before next migration

### 6. Maintain Consistent Structure
Each app should have:
```
MyApp/
├── app.json           # Manifest
├── app_init.ps1       # Initialization
├── menu.yaml          # Menu entries
├── README.md          # Documentation
├── data/              # App data
├── modules/           # App-specific modules
├── public/            # UI assets
│   └── elements/      # UI components
└── routes/            # API routes
    └── api/v1/        # Versioned routes
```

---

## Common Workflows

### Workflow 1: Migrate Single Feature
```powershell
# 1. Create app
.\system\utility\New-PSWebHostApp.ps1 -AppName "MyFeature" -Category "Utilities" ...

# 2. Preview migration
.\system\utility\Move-ComponentToApp.ps1 -ComponentPath "routes/api/v1/feature" -TargetApp "MyFeature" -WhatIf

# 3. Execute migration
.\system\utility\Move-ComponentToApp.ps1 -ComponentPath "routes/api/v1/feature" -TargetApp "MyFeature"

# 4. Update menu
# Edit apps/MyFeature/menu.yaml

# 5. Test
.\WebHost.ps1 -Port 8888 -Async
```

### Workflow 2: Migrate Entire Category
```powershell
# 1. Create all apps in category
.\create-category-apps.ps1

# 2. Preview all migrations
.\migrate-category-apps.ps1 -WhatIf

# 3. Execute migrations
.\migrate-category-apps.ps1

# 4. Bulk update menus
.\update-category-menus.ps1

# 5. Clean up
# Remove empty directories

# 6. Test
.\WebHost.ps1 -Port 8888 -Async
```

### Workflow 3: Analyze Before Planning
```powershell
# 1. Run analysis
.\system\utility\Analyze-Dependencies.ps1

# 2. Identify extraction candidates
$data = Get-Content PsWebHost_Data\system\utility\Analyze-Dependencies.json | ConvertFrom-Json
$candidates = $data.Results |
  Where-Object { $_.ExtractabilityScore -ge 80 -and $_.ComponentType -ne 'Test' } |
  Sort-Object ExtractabilityScore -Descending

# 3. Group by likely category
$candidates | Group-Object {
  if ($_.ExternalTools -like '*docker*') { 'Containers' }
  elseif ($_.ExternalTools -like '*mysql*|*redis*') { 'Databases' }
  elseif ($_.FilePath -like '*admin*') { 'Admin' }
  else { 'Utilities' }
}

# 4. Plan migration based on grouping
```

---

## Reference

### File Locations
- **Core Migration Tools:** `system/utility/`
- **Analysis Output:** `PsWebHost_Data/system/utility/Analyze-Dependencies.json`
- **Apps Directory:** `apps/`
- **Migration Scripts:** Project root (move to `system/utility/` after testing)

### Command Cheat Sheet
```powershell
# Analyze dependencies
.\system\utility\Analyze-Dependencies.ps1

# Create app
.\system\utility\New-PSWebHostApp.ps1 -AppName "..." -Category "..." ...

# Move component (preview)
.\system\utility\Move-ComponentToApp.ps1 -ComponentPath "..." -TargetApp "..." -WhatIf

# Move component (execute)
.\system\utility\Move-ComponentToApp.ps1 -ComponentPath "..." -TargetApp "..."

# Query analysis data
$data = Get-Content PsWebHost_Data\system\utility\Analyze-Dependencies.json | ConvertFrom-Json

# Find component in analysis
$data.Results | Where-Object { $_.FilePath -like '*search*' }

# Get extractability stats
$data.Summary.HighlyExtractable
$data.Summary.MediumExtractable
$data.Summary.LowExtractable
```

---

## Additional Resources

- **Migration Summary:** `MIGRATION_SUMMARY.md` - Detailed overview of completed migrations
- **Dependency Analysis:** `PsWebHost_Data/system/utility/Analyze-Dependencies.json` - Full analysis data
- **App Examples:** `apps/WindowsAdmin/`, `apps/MySQLManager/` - Reference implementations

---

## Support

For issues or questions:
1. Check this guide first
2. Review `MIGRATION_SUMMARY.md` for examples
3. Examine successful migrations in `apps/` directory
4. Analyze dependencies with `Analyze-Dependencies.ps1`
