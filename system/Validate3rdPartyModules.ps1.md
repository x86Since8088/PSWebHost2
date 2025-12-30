# Validate3rdPartyModules.ps1

Validates, manages, and downloads third-party PowerShell modules required by PsWebHost based on a YAML specification file.

## Overview

This script ensures that all required third-party PowerShell modules are installed with the correct versions, using a local module cache to maintain project-specific dependencies without affecting the system-wide PowerShell module installation.

## Purpose

- **Dependency Management**: Automates the installation and validation of required PowerShell modules
- **Version Control**: Enforces specific version requirements, ranges, or exact version matches
- **Module Isolation**: Uses a project-local `ModuleDownload` directory to avoid conflicts with system modules
- **Version Disabling**: Automatically disables (renames) module versions that fall outside the specification
- **Bootstrapping**: Self-installs the `powershell-yaml` module if not present to parse the configuration file

## Configuration File

The script reads from `system/Validate3rdPartyModules.yaml` which defines module requirements:

```yaml
- Name: ModuleName
  Version: 1.2.3          # Specific required version(s) - can be array
  VersionMIN: 1.0.0       # Minimum acceptable version
  VersionMAX: 2.0.0       # Maximum acceptable version
  Repository: PSGallery   # PowerShell repository to download from
  URL: https://...        # Optional fallback download URL
```

**Version Specification Rules:**
- `Version`: Array of exact version(s) allowed (e.g., `[1.2.3, 1.2.4]`)
- `VersionMIN`: Minimum version (inclusive) - can be used alone or with `VersionMAX`
- `VersionMAX`: Maximum version (inclusive) - can be used alone or with `VersionMIN`
- If none specified, defaults to `VersionMIN: 0.0.0.0` (all versions allowed)

## Usage

```powershell
# Run validation (typically called from WebHost.ps1 during startup)
.\system\Validate3rdPartyModules.ps1 -Verbose
```

## How It Works

### 1. Bootstrap YAML Module

```powershell
if (-not (Get-Module -ListAvailable -Name 'powershell-yaml')) {
    Install-Module -Name 'powershell-yaml' -Repository PSGallery -Force -Scope CurrentUser
}
```

Ensures the `powershell-yaml` module is installed to parse the configuration file.

### 2. Create Local Module Cache

Creates `ModuleDownload` directory in project root if it doesn't exist:

```powershell
$moduleDownloadDir = Join-Path $ProjectRoot "ModuleDownload"
if (-not (Test-Path $moduleDownloadDir)) {
    New-Item -Path $moduleDownloadDir -ItemType Directory | Out-Null
}
```

### 3. Add to PSModulePath

Temporarily adds the local cache to the module search path:

```powershell
if (-not ($moduleDownloadDir -in ($env:PSModulePath -split ";"))) {
    $env:PSModulePath = $moduleDownloadDir + ";" + $env:PSModulePath
}
```

### 4. Validate Existing Module Versions

For each module specification, the script:

1. **Scans existing versions** in `ModuleDownload\ModuleName\{version}` folders
2. **Tests each version** against the specification using `Test-VersionInSpec`
3. **Disables out-of-spec versions** by renaming folders to `{version}.disabled`
4. **Re-enables previously disabled versions** if they now match the spec

Example output:
```
WARNING:  Verion 2.1.0 is not inside of the Module Specification:
          Name: PSSQLite
          VersionMIN: 1.0.0
          VersionMAX: 2.0.0
          Repository: PSGallery
WARNING:  Disabling 'C:\sc\PsWebHost\ModuleDownload\PSSQLite\2.1.0'.
```

### 5. Check Installation Status

The script performs a three-tier search for installed modules:

1. **Primary**: Local `ModuleDownload` directory
2. **Secondary**: Currently loaded module commands
3. **Tertiary**: System-wide module locations

### 6. Download Missing or Incorrect Versions

If a module is missing or has the wrong version:

```powershell
$saveParams = @{
    Name = $moduleName
    Repository = $repository
    Path = $moduleDownloadDir
    Force = $true
    AcceptLicense = $true
}

if ($HighestRequiredVersion) {
    $saveParams.RequiredVersion = $HighestRequiredVersion
} else {
    if ($VersionMIN) { $saveParams.MinimumVersion = $VersionMIN }
    if ($VersionMAX) { $saveParams.MaximumVersion = $VersionMAX }
}

Save-Module @saveParams
```

Downloads to `ModuleDownload\{ModuleName}\{Version}\`

## Key Functions

### `FixVersionLength`

Normalizes version strings to 4-part format (e.g., `1.2` → `1.2.0.0`):

```powershell
function FixVersionLength {
    param($version)
    ForEach ($versionItem in $version) {
        [version](($versionItem.tostring() + ".0.0.0.0" -split '\.'|Select-Object -First 4) -join '.')
    }
}
```

### `Test-VersionInSpec`

Validates whether a version meets the specification requirements:

```powershell
function Test-VersionInSpec {
    param(
        [version]$Version,
        [version[]]$RequiredVersion,  # Exact versions allowed
        [version]$VersionMIN,          # Minimum version
        [version]$VersionMAX           # Maximum version
    )

    # Returns $true if version matches any RequiredVersion
    # OR if version is within MIN/MAX range
}
```

**Logic:**
- If `RequiredVersion` is set, version must match one of the specified versions
- If `VersionMIN` and/or `VersionMAX` are set, version must fall within the range
- All comparisons are inclusive

## Version Management Examples

### Example 1: Exact Version Required

```yaml
- Name: PSSQLite
  Version: 1.1.0
  Repository: PSGallery
```

Only version `1.1.0` is allowed. Any other version will be disabled.

### Example 2: Version Range

```yaml
- Name: PSSQLite
  VersionMIN: 1.0.0
  VersionMAX: 2.0.0
  Repository: PSGallery
```

Versions `1.0.0` through `2.0.0` (inclusive) are allowed.

### Example 3: Multiple Exact Versions

```yaml
- Name: PSSQLite
  Version:
    - 1.1.0
    - 1.2.0
  Repository: PSGallery
```

Only versions `1.1.0` and `1.2.0` are allowed.

### Example 4: Minimum Version Only

```yaml
- Name: PSSQLite
  VersionMIN: 1.5.0
  Repository: PSGallery
```

Any version `>= 1.5.0` is allowed.

## Error Handling

### AcceptLicense Parameter Error

Some older PowerShell versions don't support `-AcceptLicense`:

```powershell
if ($errMsg -match "A parameter cannot be found that matches parameter name 'AcceptLicense'") {
    $saveParams.Remove('AcceptLicense')
    Save-Module @saveParams  # Retry without parameter
}
```

### Module Lock Retry Logic

If a module folder is locked during rename (disabling), the script retries 3 times with 1-second delays:

```powershell
for ($i = 0; $i -lt 3; $i++) {
    try {
        Rename-Item $Versionfolder.FullName ($Versionfolder.Name + '.disabled') -ErrorAction Stop
        $renamed = $true
        break
    } catch {
        if ($i -lt 2) {
            Write-Verbose "Rename failed (attempt $($i+1)/3), retrying in 1 second..."
            Start-Sleep -Seconds 1
        }
    }
}
```

### Fallback URL Download

Placeholder for direct URL downloads when PSGallery fails:

```powershell
if ($moduleSpec.URL) {
    Write-Warning "Attempting direct download from $($moduleSpec.URL)..."
    # Add logic for direct download and extraction here if needed
}
```

## Integration with PsWebHost

This script is typically called during WebHost.ps1 startup to ensure all dependencies are available before the server starts:

```powershell
# From WebHost.ps1
& (Join-Path $ProjectRoot "system\Validate3rdPartyModules.ps1") -Verbose
```

## Output Examples

### Successful Validation

```
VERBOSE: Validating module: PSSQLite version 1.1.0...
VERBOSE:   Module 'PSSQLite' is allowed to use version '1.1.0' in versions '1.1.0' VersionMin '0.0.0.0' VersionMax '0.0.0.0'.
VERBOSE:   Module 'PSSQLite' is already up to date.
VERBOSE: Third-party module validation complete.
```

### Version Mismatch (Download Required)

```
WARNING:   Module 'PSSQLite' version mismatch. Found 2.1.0, require '1.1.0'. Scheduling for download.
VERBOSE:   Downloading 'PSSQLite' version '1.1.0' from repository 'PSGallery'...
VERBOSE:   Successfully downloaded 'PSSQLite'.
```

### Out-of-Spec Version Disabled

```
WARNING:   Verion 2.1.0 is not inside of the Module Specification:
          Name: PSSQLite
          VersionMIN: 1.0.0
          VersionMAX: 2.0.0
          Repository: PSGallery
WARNING:   Disabling 'C:\sc\PsWebHost\ModuleDownload\PSSQLite\2.1.0'.
```

## Directory Structure After Validation

```
PsWebHost/
├── ModuleDownload/
│   ├── powershell-yaml/
│   │   └── 0.4.7/              # Bootstrap module
│   ├── PSSQLite/
│   │   ├── 1.1.0/              # Active version
│   │   └── 2.1.0.disabled/     # Disabled out-of-spec version
│   └── OtherModule/
│       └── 3.2.1/
└── system/
    ├── Validate3rdPartyModules.ps1
    └── Validate3rdPartyModules.yaml
```

## Security Considerations

- **Repository Trust**: Modules are downloaded from repositories specified in the YAML config (typically PSGallery)
- **Version Pinning**: Exact version requirements prevent automatic updates that could introduce breaking changes
- **Local Isolation**: Using a project-local module directory prevents conflicts with system-wide modules
- **No Automatic Execution**: Script validates and downloads but does not automatically import modules

## Troubleshooting

### Module Not Found After Download

Check that the `ModuleDownload` directory is in `$env:PSModulePath`:

```powershell
$env:PSModulePath -split ';'
```

### Version Still Showing as Disabled

Manually rename the folder to remove `.disabled`:

```powershell
Rename-Item 'ModuleDownload\ModuleName\1.2.0.disabled' '1.2.0'
```

### Download Fails from PSGallery

1. Check internet connectivity
2. Verify repository is accessible: `Find-Module -Name ModuleName -Repository PSGallery`
3. Add fallback URL to YAML configuration
4. Manually download and extract to `ModuleDownload\ModuleName\{Version}\`

## Performance

- **Validation Speed**: Fast - only checks folder names and compares versions
- **Download Speed**: Depends on module size and network connection
- **Caching**: Once validated, no re-download occurs unless version changes

## Dependencies

- **PowerShell**: 5.1 or higher (uses `Save-Module` cmdlet)
- **Internet Access**: Required for downloading modules from PSGallery
- **powershell-yaml**: Bootstrapped automatically if not present

## See Also

- `system/Validate3rdPartyModules.yaml` - Module specification file
- `WebHost.ps1` - Main entry point that calls this script
- `ModuleDownload/` - Local module cache directory
