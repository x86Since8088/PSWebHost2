# Module Loading Accountability Checklist

## ❌ NEVER Use Dot-Sourcing for Reusable Code

### What is Dot-Sourcing?
```powershell
# ❌ BAD - Dot-sourcing
. $PSScriptRoot\Helper.ps1
. "C:\Path\To\Script.ps1"
```

### Why Dot-Sourcing is Problematic:
1. **No version control** - Can't specify module versions
2. **No dependency tracking** - Hard to know what depends on what
3. **Scope pollution** - Variables leak between scopes
4. **No manifest** - No metadata about functions, version, author
5. **Performance issues** - Re-parses script every time (no module caching)
6. **Hard to test** - Can't easily mock or replace functionality
7. **No export control** - All functions/variables become available
8. **Breaking encapsulation** - Internal implementation details exposed

---

## ✅ ALWAYS Use Proper Modules

### Module Structure Requirements:

```
apps/YourApp/modules/YourModule/
├── YourModule.psd1    ✅ REQUIRED - Module manifest
├── YourModule.psm1    ✅ REQUIRED - Module script file
├── Private/           ✅ OPTIONAL - Private helper functions
│   └── PrivateHelper.ps1
└── Public/            ✅ OPTIONAL - Public exported functions
    └── PublicFunction.ps1
```

### Minimum .psd1 Contents:
```powershell
@{
    ModuleVersion = '1.0.0'                    # ✅ REQUIRED
    GUID = 'unique-guid-here'                  # ✅ REQUIRED
    RootModule = 'YourModule.psm1'             # ✅ REQUIRED
    FunctionsToExport = @('Func1', 'Func2')    # ✅ REQUIRED
    PowerShellVersion = '7.0'                  # ✅ RECOMMENDED
}
```

### How to Use Modules:
```powershell
# ✅ GOOD - Proper module import
Import-Module (Join-Path $PSScriptRoot "..\..\modules\YourModule") -Force -ErrorAction Stop

# ✅ GOOD - With manifest check
$modulePath = Join-Path $PSScriptRoot "..\..\modules\YourModule\YourModule.psd1"
Import-Module $modulePath -Force -ErrorAction Stop
```

---

## Accountability Checklist for Developers

### Before Writing Any Reusable Code:

- [ ] Will this code be used by **more than one file**?
  - If YES → Create a proper module with .psd1
  - If NO → Keep as inline code

- [ ] Does a .psd1 manifest exist for this module?
  - If NO → Create one immediately
  - If YES → Verify FunctionsToExport is accurate

- [ ] Are you about to use dot-sourcing (`. $path`)?
  - If YES → STOP! Convert to module first
  - If NO → Continue with Import-Module

- [ ] Does the module have a unique GUID?
  - If NO → Generate one: `New-Guid`
  - If YES → Verify it's actually unique

- [ ] Are all exported functions listed in FunctionsToExport?
  - If NO → Update the manifest
  - If YES → Verify list is complete

---

## Code Review Checklist

### When Reviewing Pull Requests:

✅ **APPROVE IF:**
- Uses `Import-Module` for all reusable code
- Every module has a `.psd1` manifest
- `FunctionsToExport` lists all public functions
- No dot-sourcing (`. $file`) anywhere
- Module paths use `Join-Path` (not hardcoded strings)

❌ **REQUEST CHANGES IF:**
- Uses dot-sourcing (`. $file`)
- Module missing `.psd1` manifest
- `.ps1` file in `modules/` directory (should be `.psm1`)
- `FunctionsToExport = '*'` (should list explicitly)
- Hardcoded module paths
- Module loaded in multiple places (should load once globally)

---

## Migration Path for Existing Code

### Step 1: Identify Dot-Sourced Files
```powershell
# Find all dot-sourcing in codebase
Get-ChildItem -Recurse -Filter "*.ps1" |
    Select-String -Pattern '^\s*\.\s+\$' -AllMatches
```

### Step 2: For Each Dot-Sourced File:

1. **Create module structure:**
   ```powershell
   mkdir "modules/ModuleName"
   mv "modules/OldFile.ps1" "modules/ModuleName/ModuleName.psm1"
   ```

2. **Create manifest:**
   ```powershell
   # List all functions
   $functions = Select-String -Path "modules/ModuleName/ModuleName.psm1" -Pattern "^function (\w+-\w+)" |
       ForEach-Object { $_.Matches.Groups[1].Value }

   # Create manifest
   @{
       ModuleVersion = '1.0.0'
       GUID = (New-Guid).ToString()
       RootModule = 'ModuleName.psm1'
       FunctionsToExport = $functions
       PowerShellVersion = '7.0'
   } | Export-PowerShellDataFile -Path "modules/ModuleName/ModuleName.psd1"
   ```

3. **Update all references:**
   ```powershell
   # Find all files that dot-source this module
   Get-ChildItem -Recurse -Filter "*.ps1" |
       Select-String -Pattern "OldFile\.ps1"

   # Replace in each file:
   # OLD: . (Join-Path $PSScriptRoot "....\OldFile.ps1")
   # NEW: Import-Module (Join-Path $PSScriptRoot "....\ModuleName") -Force
   ```

4. **Test thoroughly:**
   - Restart server
   - Test all endpoints
   - Check for module loading errors in logs

---

## Real Example: FileExplorerHelper

### ❌ Before (BAD):
```
apps/WebhostFileExplorer/modules/
└── FileExplorerHelper.ps1    ❌ Flat file, no manifest

# In routes:
$helperPath = Join-Path $PSScriptRoot "..\..\modules\FileExplorerHelper.ps1"
. $helperPath    ❌ Dot-sourcing
```

### ✅ After (GOOD):
```
apps/WebhostFileExplorer/modules/FileExplorerHelper/
├── FileExplorerHelper.psd1    ✅ Manifest with metadata
└── FileExplorerHelper.psm1    ✅ Module file

# In routes:
Import-Module (Join-Path $PSScriptRoot "..\..\modules\FileExplorerHelper") -Force -ErrorAction Stop    ✅ Proper import
```

### Changes Made:
1. Created `FileExplorerHelper/` subdirectory
2. Renamed `.ps1` → `.psm1`
3. Created `.psd1` with all 16 exported functions
4. Updated 12 route files to use Import-Module
5. Removed all dot-sourcing references
6. Updated error messages from "load FileExplorerHelper.ps1" to "import FileExplorerHelper module"

---

## Common Patterns to Watch For

### Pattern 1: "Helper" Scripts
```powershell
# ❌ BAD
. (Join-Path $PSScriptRoot "Helper.ps1")

# ✅ GOOD
Import-Module (Join-Path $PSScriptRoot "../modules/Helper") -Force
```

### Pattern 2: "Utility" Scripts
```powershell
# ❌ BAD
. "$PSScriptRoot\..\..\Utilities.ps1"

# ✅ GOOD
Import-Module (Join-Path $PSScriptRoot "../../modules/Utilities") -Force
```

### Pattern 3: "Shared" Code
```powershell
# ❌ BAD
. "C:\Path\To\Shared\Functions.ps1"

# ✅ GOOD
Import-Module "SharedFunctions" -Force  # From PSModulePath
```

---

## Automated Checks

### Pre-Commit Hook (Optional)
```powershell
# .git/hooks/pre-commit
# Fail if dot-sourcing detected in staged files
$staged = git diff --cached --name-only --diff-filter=ACM | Where-Object { $_ -match '\.ps1$' }
$dotSourced = $staged | ForEach-Object {
    Select-String -Path $_ -Pattern '^\s*\.\s+[\$\(]' -Quiet
}

if ($dotSourced -contains $true) {
    Write-Host "❌ COMMIT BLOCKED: Dot-sourcing detected!" -ForegroundColor Red
    Write-Host "   Convert to proper module with .psd1 manifest" -ForegroundColor Yellow
    exit 1
}
```

### CI/CD Check
```powershell
# In build pipeline
$violations = Get-ChildItem -Recurse -Filter "*.ps1" -Exclude "*.Tests.ps1" |
    Select-String -Pattern '^\s*\.\s+[\$\(]' -List |
    Select-Object -ExpandProperty Path

if ($violations) {
    Write-Error "Dot-sourcing violations found in: $($violations -join ', ')"
    exit 1
}
```

---

## Module Loading Best Practices Summary

### ✅ DO:
1. Always create `.psd1` manifests for modules
2. Use `Import-Module` for all reusable code
3. List functions explicitly in `FunctionsToExport`
4. Use unique GUIDs for each module
5. Specify minimum PowerShell version
6. Use `-Force` to reload during development
7. Use `-ErrorAction Stop` for critical modules
8. Keep modules in `modules/ModuleName/` structure

### ❌ DON'T:
1. Use dot-sourcing for reusable code
2. Put `.ps1` files directly in `modules/` directory
3. Use `FunctionsToExport = '*'` (be explicit)
4. Hardcode module paths (use `Join-Path`)
5. Load same module in multiple places
6. Skip the `.psd1` manifest ("it works without it")
7. Use global variables between modules
8. Mix module code with script code

---

## Verification Commands

### Check All Modules Have Manifests:
```powershell
Get-ChildItem -Path "apps/*/modules" -Recurse -Directory |
    Where-Object { -not (Test-Path (Join-Path $_.FullName "*.psd1")) } |
    Select-Object FullName
```

### Find All Dot-Sourcing:
```powershell
Get-ChildItem -Path "apps" -Recurse -Filter "*.ps1" -File |
    Select-String -Pattern '^\s*\.\s+[\$\(]' -List |
    Select-Object Path, LineNumber, Line
```

### Verify Module Exports:
```powershell
Get-ChildItem -Path "apps/*/modules/*/*psd1" | ForEach-Object {
    $manifest = Import-PowerShellDataFile $_
    $functions = Select-String -Path ($_.FullName -replace '\.psd1$', '.psm1') -Pattern "^function (\w+-\w+)" |
        ForEach-Object { $_.Matches.Groups[1].Value }

    [PSCustomObject]@{
        Module = $_.Name
        Manifest = $manifest.FunctionsToExport.Count
        Actual = $functions.Count
        Match = $manifest.FunctionsToExport.Count -eq $functions.Count
    }
}
```

---

## Questions & Answers

**Q: Can I use dot-sourcing for one-time scripts?**
A: Yes, but ONLY for scripts that are:
- Run manually (not by the server)
- Not shared between files
- Temporary/throwaway code

**Q: What about performance? Import-Module is slower!**
A: Modules are **cached after first import**. Dot-sourcing **re-parses every time**. Modules are actually faster for repeated use.

**Q: I only have 2 functions, do I need a module?**
A: If those functions are used by **more than one file**, YES.

**Q: Can I use `#Requires -Modules` instead?**
A: `#Requires` is for **dependencies**. You still need `Import-Module` to actually load the module.

**Q: What if I need to reload during development?**
A: Use `Import-Module -Force` to reload. Modules support this better than dot-sourcing.

---

## Conclusion

**Dot-sourcing is for the past. Modules are the future.**

If you find yourself about to write `. $somePath`, **STOP** and create a proper module with a `.psd1` manifest instead.

Your future self (and your teammates) will thank you.

---

**Last Updated:** 2026-01-26
**Applies To:** All PSWebHost apps and modules
**Enforcement:** Code reviews + automated checks (optional)
