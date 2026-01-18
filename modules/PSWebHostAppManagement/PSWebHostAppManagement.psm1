#Requires -Version 7

<#
.SYNOPSIS
    PSWebHost Application Management Module

.DESCRIPTION
    Provides functions for creating, installing, managing, and packaging PSWebHost applications.
    Includes app scaffolding, validation, and lifecycle management.

.NOTES
    Module: PSWebHostAppManagement
    Author: PSWebHost Team
    Version: 1.0.0
#>

#region Helper Functions

function Get-PSWebHostAppsPath {
    <#
    .SYNOPSIS
        Gets the apps directory path from PSWebServer global state
    #>
    if ($Global:PSWebServer -and $Global:PSWebServer.ContainsKey('AppsPath')) {
        return $Global:PSWebServer.AppsPath
    }

    # Fallback to script-relative path
    $scriptRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    return Join-Path $scriptRoot "apps"
}

function Test-AppNameValid {
    <#
    .SYNOPSIS
        Validates app name follows PascalCase convention
    #>
    param(
        [Parameter(Mandatory)]
        [string]$AppName
    )

    # Must be PascalCase, letters only, no spaces/special chars
    return $AppName -match '^[A-Z][a-zA-Z0-9]*$'
}

function Expand-TemplateVariables {
    <#
    .SYNOPSIS
        Replaces template placeholders with actual values
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [hashtable]$Variables
    )

    $result = $Content
    foreach ($key in $Variables.Keys) {
        $placeholder = "{{$key}}"
        $result = $result -replace [regex]::Escape($placeholder), $Variables[$key]
    }

    return $result
}

#endregion

#region App Creation

function New-PSWebHostApp {
    <#
    .SYNOPSIS
        Creates a new PSWebHost app from template

    .DESCRIPTION
        Scaffolds a complete app structure with all necessary files and directories.
        Uses templates with placeholder replacement for customization.

    .PARAMETER AppName
        Name of the app in PascalCase (e.g., MyNewApp)

    .PARAMETER Description
        Brief description of what the app does

    .PARAMETER Author
        Author name for app metadata

    .PARAMETER Version
        Initial version number (defaults to 1.0.0)

    .PARAMETER RequiredRoles
        Array of role names required to access this app

    .PARAMETER Force
        Overwrite existing app if it exists

    .EXAMPLE
        New-PSWebHostApp -AppName "DataVisualizer" -Description "Advanced data visualization tools" -Author "John Doe"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [Parameter(Mandatory)]
        [string]$Description,

        [string]$Author = $env:USERNAME,

        [string]$Version = "1.0.0",

        [string[]]$RequiredRoles = @('authenticated'),

        [switch]$Force
    )

    $MyTag = '[PSWebHostAppManagement:New]'

    # Validate app name
    if (-not (Test-AppNameValid -AppName $AppName)) {
        throw "$MyTag Invalid app name. Must be PascalCase (e.g., MyApp, DataProcessor)"
    }

    # Get apps directory
    $appsPath = Get-PSWebHostAppsPath
    $appPath = Join-Path $appsPath $AppName

    # Check if app already exists
    if ((Test-Path $appPath) -and -not $Force) {
        throw "$MyTag App '$AppName' already exists at $appPath. Use -Force to overwrite."
    }

    # Get template directory
    $templatePath = Join-Path $PSScriptRoot "New_App_Template"
    if (-not (Test-Path $templatePath)) {
        throw "$MyTag Template directory not found at $templatePath"
    }

    Write-Host "$MyTag Creating new app: $AppName" -ForegroundColor Cyan

    # Prepare template variables
    $templateVars = @{
        AppName = $AppName
        AppDescription = $Description
        AppAuthor = $Author
        AppVersion = $Version
        AppRequiredRoles = ($RequiredRoles | ForEach-Object { "  - $_" }) -join "`n"
        AppRoutePrefix = "/apps/$AppName"
        ModuleName = "PSWebHost_$AppName"
        CurrentYear = (Get-Date).Year
        CurrentDate = (Get-Date).ToString("yyyy-MM-dd")
    }

    # Create app directory structure
    $directories = @(
        $appPath,
        (Join-Path $appPath "modules\PSWebHost_$AppName"),
        (Join-Path $appPath "routes\api\v1\ui\elements"),
        (Join-Path $appPath "public\elements"),
        (Join-Path $appPath "config"),
        (Join-Path $appPath "defaultconfig"),
        (Join-Path $appPath "tasks"),
        (Join-Path $appPath "tests")
    )

    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Write-Verbose "$MyTag Created directory: $dir"
        }
    }

    # Copy and process template files
    $templateFiles = Get-ChildItem -Path $templatePath -Recurse -File

    foreach ($templateFile in $templateFiles) {
        # Calculate relative path from template root
        $relativePath = $templateFile.FullName.Substring($templatePath.Length + 1)

        # Replace .template extension and apply variable substitution to path
        $targetRelativePath = $relativePath -replace '\.template$', ''
        $targetRelativePath = Expand-TemplateVariables -Content $targetRelativePath -Variables $templateVars

        # Calculate target path
        $targetPath = Join-Path $appPath $targetRelativePath
        $targetDir = Split-Path $targetPath -Parent

        # Ensure target directory exists
        if (-not (Test-Path $targetDir)) {
            New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
        }

        # Read template content
        $content = Get-Content -Path $templateFile.FullName -Raw

        # Apply variable substitution
        $processedContent = Expand-TemplateVariables -Content $content -Variables $templateVars

        # Write to target
        Set-Content -Path $targetPath -Value $processedContent -NoNewline
        Write-Verbose "$MyTag Created file: $targetPath"
    }

    Write-Host "$MyTag App created successfully at: $appPath" -ForegroundColor Green
    Write-Host "$MyTag Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Review and customize app.yaml" -ForegroundColor Gray
    Write-Host "  2. Implement your module functions in modules\PSWebHost_$AppName\PSWebHost_$AppName.psm1" -ForegroundColor Gray
    Write-Host "  3. Add API endpoints in routes\api\v1\" -ForegroundColor Gray
    Write-Host "  4. Create UI components in public\elements\" -ForegroundColor Gray
    Write-Host "  5. Enable the app: Enable-PSWebHostApp -AppName $AppName" -ForegroundColor Gray

    return [PSCustomObject]@{
        AppName = $AppName
        AppPath = $appPath
        Created = Get-Date
        Status = 'Created'
    }
}

#endregion

#region App Lifecycle Management

function Enable-PSWebHostApp {
    <#
    .SYNOPSIS
        Enables a PSWebHost app

    .DESCRIPTION
        Sets the 'enabled' flag to true in app.yaml and optionally restarts the server
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [switch]$NoRestart
    )

    $MyTag = '[PSWebHostAppManagement:Enable]'

    $appsPath = Get-PSWebHostAppsPath
    $appPath = Join-Path $appsPath $AppName
    $appYamlPath = Join-Path $appPath "app.yaml"

    if (-not (Test-Path $appYamlPath)) {
        throw "$MyTag App '$AppName' not found at $appPath"
    }

    # Read app.yaml
    $yamlContent = Get-Content -Path $appYamlPath -Raw

    # Update enabled flag
    $yamlContent = $yamlContent -replace '(?m)^enabled:\s*false', 'enabled: true'

    # Write back
    Set-Content -Path $appYamlPath -Value $yamlContent -NoNewline

    Write-Host "$MyTag App '$AppName' enabled" -ForegroundColor Green

    if (-not $NoRestart) {
        Write-Host "$MyTag Restart PSWebHost server to apply changes" -ForegroundColor Yellow
    }
}

function Disable-PSWebHostApp {
    <#
    .SYNOPSIS
        Disables a PSWebHost app

    .DESCRIPTION
        Sets the 'enabled' flag to false in app.yaml
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [switch]$NoRestart
    )

    $MyTag = '[PSWebHostAppManagement:Disable]'

    $appsPath = Get-PSWebHostAppsPath
    $appPath = Join-Path $appsPath $AppName
    $appYamlPath = Join-Path $appPath "app.yaml"

    if (-not (Test-Path $appYamlPath)) {
        throw "$MyTag App '$AppName' not found at $appPath"
    }

    # Read app.yaml
    $yamlContent = Get-Content -Path $appYamlPath -Raw

    # Update enabled flag
    $yamlContent = $yamlContent -replace '(?m)^enabled:\s*true', 'enabled: false'

    # Write back
    Set-Content -Path $appYamlPath -Value $yamlContent -NoNewline

    Write-Host "$MyTag App '$AppName' disabled" -ForegroundColor Yellow

    if (-not $NoRestart) {
        Write-Host "$MyTag Restart PSWebHost server to apply changes" -ForegroundColor Yellow
    }
}

function Get-PSWebHostApp {
    <#
    .SYNOPSIS
        Gets information about installed PSWebHost apps

    .DESCRIPTION
        Returns app metadata, status, and configuration details

    .PARAMETER AppName
        Specific app name to query (optional, returns all if not specified)
    #>
    [CmdletBinding()]
    param(
        [string]$AppName
    )

    $appsPath = Get-PSWebHostAppsPath

    if ($AppName) {
        # Get specific app
        $appPath = Join-Path $appsPath $AppName
        if (-not (Test-Path $appPath)) {
            Write-Warning "App '$AppName' not found"
            return $null
        }

        return Get-AppInfo -AppPath $appPath
    } else {
        # Get all apps
        $appDirs = Get-ChildItem -Path $appsPath -Directory

        $apps = foreach ($dir in $appDirs) {
            $appYamlPath = Join-Path $dir.FullName "app.yaml"
            if (Test-Path $appYamlPath) {
                Get-AppInfo -AppPath $dir.FullName
            }
        }

        return $apps
    }
}

function Get-AppInfo {
    <#
    .SYNOPSIS
        Helper function to extract app information from app.yaml
    #>
    param(
        [Parameter(Mandatory)]
        [string]$AppPath
    )

    $appYamlPath = Join-Path $AppPath "app.yaml"

    if (-not (Test-Path $appYamlPath)) {
        return $null
    }

    # Parse YAML (basic parsing - could use PSYaml module for complex cases)
    $yamlContent = Get-Content -Path $appYamlPath -Raw

    # Extract fields using regex
    $name = if ($yamlContent -match '(?m)^name:\s*(.+)$') { $Matches[1].Trim() } else { Split-Path $AppPath -Leaf }
    $version = if ($yamlContent -match '(?m)^version:\s*(.+)$') { $Matches[1].Trim() } else { 'Unknown' }
    $description = if ($yamlContent -match '(?m)^description:\s*(.+)$') { $Matches[1].Trim() } else { '' }
    $enabled = if ($yamlContent -match '(?m)^enabled:\s*(true|false)') { $Matches[1] -eq 'true' } else { $false }
    $routePrefix = if ($yamlContent -match '(?m)^routePrefix:\s*(.+)$') { $Matches[1].Trim() } else { '' }

    return [PSCustomObject]@{
        Name = $name
        AppName = Split-Path $AppPath -Leaf
        Version = $version
        Description = $description
        Enabled = $enabled
        RoutePrefix = $routePrefix
        AppPath = $AppPath
    }
}

function Uninstall-PSWebHostApp {
    <#
    .SYNOPSIS
        Uninstalls a PSWebHost app

    .DESCRIPTION
        Removes app directory and all contents. Creates a backup before removal.

    .PARAMETER AppName
        Name of the app to uninstall

    .PARAMETER SkipBackup
        Skip creating a backup before removal

    .PARAMETER Force
        Skip confirmation prompt
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [switch]$SkipBackup,

        [switch]$Force
    )

    $MyTag = '[PSWebHostAppManagement:Uninstall]'

    $appsPath = Get-PSWebHostAppsPath
    $appPath = Join-Path $appsPath $AppName

    if (-not (Test-Path $appPath)) {
        throw "$MyTag App '$AppName' not found at $appPath"
    }

    # Confirm with user
    if (-not $Force -and -not $PSCmdlet.ShouldProcess($AppName, "Uninstall app")) {
        Write-Host "$MyTag Uninstall cancelled" -ForegroundColor Yellow
        return
    }

    # Create backup
    if (-not $SkipBackup) {
        $backupPath = Join-Path $Global:PSWebServer.DataRoot "backups\app-uninstall-$AppName-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Write-Host "$MyTag Creating backup at $backupPath..." -ForegroundColor Cyan

        Copy-Item -Path $appPath -Destination $backupPath -Recurse -Force
        Write-Host "$MyTag Backup created" -ForegroundColor Green
    }

    # Remove app directory
    Write-Host "$MyTag Removing app directory..." -ForegroundColor Yellow
    Remove-Item -Path $appPath -Recurse -Force

    Write-Host "$MyTag App '$AppName' uninstalled successfully" -ForegroundColor Green
    Write-Host "$MyTag Restart PSWebHost server to complete removal" -ForegroundColor Yellow
}

#endregion

#region App Validation

function Test-PSWebHostAppStructure {
    <#
    .SYNOPSIS
        Validates PSWebHost app structure and configuration

    .DESCRIPTION
        Checks for required files, validates YAML syntax, and ensures proper structure

    .PARAMETER AppName
        Name of the app to validate

    .PARAMETER Strict
        Enable strict validation (check for recommended files and patterns)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [switch]$Strict
    )

    $MyTag = '[PSWebHostAppManagement:Test]'

    $appsPath = Get-PSWebHostAppsPath
    $appPath = Join-Path $appsPath $AppName

    if (-not (Test-Path $appPath)) {
        throw "$MyTag App '$AppName' not found at $appPath"
    }

    $issues = @()
    $warnings = @()

    # Required files
    $requiredFiles = @(
        'app.yaml'
    )

    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $appPath $file
        if (-not (Test-Path $filePath)) {
            $issues += "Missing required file: $file"
        }
    }

    # Recommended files (strict mode)
    if ($Strict) {
        $recommendedFiles = @(
            'README.md',
            'app_init.ps1',
            'modules',
            'routes',
            'public'
        )

        foreach ($file in $recommendedFiles) {
            $filePath = Join-Path $appPath $file
            if (-not (Test-Path $filePath)) {
                $warnings += "Missing recommended file/directory: $file"
            }
        }
    }

    # Validate app.yaml
    $appYamlPath = Join-Path $appPath "app.yaml"
    if (Test-Path $appYamlPath) {
        $yamlContent = Get-Content -Path $appYamlPath -Raw

        # Check required fields
        $requiredFields = @('name', 'version', 'enabled')
        foreach ($field in $requiredFields) {
            if ($yamlContent -notmatch "(?m)^$field\s*:") {
                $issues += "app.yaml missing required field: $field"
            }
        }
    }

    # Report results
    $isValid = $issues.Count -eq 0

    Write-Host "$MyTag Validation results for '$AppName':" -ForegroundColor Cyan

    if ($isValid) {
        Write-Host "  ✓ App structure is valid" -ForegroundColor Green
    } else {
        Write-Host "  ✗ App structure has issues" -ForegroundColor Red
        foreach ($issue in $issues) {
            Write-Host "    - $issue" -ForegroundColor Red
        }
    }

    if ($warnings.Count -gt 0) {
        Write-Host "  ⚠ Warnings:" -ForegroundColor Yellow
        foreach ($warning in $warnings) {
            Write-Host "    - $warning" -ForegroundColor Yellow
        }
    }

    return [PSCustomObject]@{
        AppName = $AppName
        IsValid = $isValid
        Issues = $issues
        Warnings = $warnings
    }
}

#endregion

#region App Import/Export

function Export-PSWebHostApp {
    <#
    .SYNOPSIS
        Packages a PSWebHost app for distribution

    .DESCRIPTION
        Creates a ZIP archive of the app directory for sharing or backup

    .PARAMETER AppName
        Name of the app to export

    .PARAMETER OutputPath
        Path where the ZIP file should be saved (defaults to current directory)

    .PARAMETER IncludeData
        Include app data directory in the export
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [string]$OutputPath = ".",

        [switch]$IncludeData
    )

    $MyTag = '[PSWebHostAppManagement:Export]'

    $appsPath = Get-PSWebHostAppsPath
    $appPath = Join-Path $appsPath $AppName

    if (-not (Test-Path $appPath)) {
        throw "$MyTag App '$AppName' not found at $appPath"
    }

    # Get app info for version
    $appInfo = Get-AppInfo -AppPath $appPath
    $version = $appInfo.Version -replace '[^\d\.]', ''

    # Create output filename
    $timestamp = Get-Date -Format "yyyyMMdd"
    $zipFileName = "$AppName-v$version-$timestamp.zip"
    $zipPath = Join-Path $OutputPath $zipFileName

    Write-Host "$MyTag Exporting app '$AppName'..." -ForegroundColor Cyan

    # Create temporary staging directory
    $tempDir = Join-Path $env:TEMP "PSWebHostApp-$AppName-$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

    try {
        # Copy app files
        $stagingAppDir = Join-Path $tempDir $AppName
        Copy-Item -Path $appPath -Destination $stagingAppDir -Recurse -Force

        # Remove data directory unless IncludeData is specified
        if (-not $IncludeData) {
            $dataPath = Join-Path $stagingAppDir "data"
            if (Test-Path $dataPath) {
                Remove-Item -Path $dataPath -Recurse -Force
            }
        }

        # Create ZIP
        Compress-Archive -Path $stagingAppDir -DestinationPath $zipPath -Force

        Write-Host "$MyTag App exported to: $zipPath" -ForegroundColor Green

        $zipFile = Get-Item $zipPath
        Write-Host "$MyTag Package size: $([math]::Round($zipFile.Length / 1MB, 2)) MB" -ForegroundColor Gray

        return [PSCustomObject]@{
            AppName = $AppName
            Version = $appInfo.Version
            PackagePath = $zipPath
            PackageSize = $zipFile.Length
            Created = Get-Date
        }

    } finally {
        # Clean up temp directory
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force
        }
    }
}

function Install-PSWebHostApp {
    <#
    .SYNOPSIS
        Installs a PSWebHost app from a ZIP package or directory

    .DESCRIPTION
        Extracts and installs an app package into the apps directory

    .PARAMETER PackagePath
        Path to the app ZIP file or directory

    .PARAMETER Force
        Overwrite existing app if it exists
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackagePath,

        [switch]$Force
    )

    $MyTag = '[PSWebHostAppManagement:Install]'

    if (-not (Test-Path $PackagePath)) {
        throw "$MyTag Package not found: $PackagePath"
    }

    $appsPath = Get-PSWebHostAppsPath

    $packageItem = Get-Item $PackagePath

    if ($packageItem.Extension -eq '.zip') {
        # Extract ZIP to temporary location
        $tempDir = Join-Path $env:TEMP "PSWebHostApp-Install-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Host "$MyTag Extracting package..." -ForegroundColor Cyan

        Expand-Archive -Path $PackagePath -DestinationPath $tempDir -Force

        # Find app directory (should be single directory in ZIP)
        $extractedDirs = Get-ChildItem -Path $tempDir -Directory
        if ($extractedDirs.Count -ne 1) {
            throw "$MyTag Invalid package structure. Expected single app directory."
        }

        $sourceAppPath = $extractedDirs[0].FullName
        $appName = $extractedDirs[0].Name

    } elseif ($packageItem.PSIsContainer) {
        # Directory installation
        $sourceAppPath = $PackagePath
        $appName = $packageItem.Name
    } else {
        throw "$MyTag Invalid package. Must be ZIP file or directory."
    }

    $targetAppPath = Join-Path $appsPath $appName

    # Check if app exists
    if ((Test-Path $targetAppPath) -and -not $Force) {
        throw "$MyTag App '$appName' already exists. Use -Force to overwrite."
    }

    # Copy to apps directory
    Write-Host "$MyTag Installing app '$appName'..." -ForegroundColor Cyan
    Copy-Item -Path $sourceAppPath -Destination $targetAppPath -Recurse -Force

    # Clean up temp directory if extraction was used
    if ($packageItem.Extension -eq '.zip') {
        Remove-Item -Path $tempDir -Recurse -Force
    }

    Write-Host "$MyTag App '$appName' installed successfully" -ForegroundColor Green
    Write-Host "$MyTag Restart PSWebHost server to load the new app" -ForegroundColor Yellow

    return [PSCustomObject]@{
        AppName = $appName
        AppPath = $targetAppPath
        Installed = Get-Date
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'New-PSWebHostApp',
    'Enable-PSWebHostApp',
    'Disable-PSWebHostApp',
    'Get-PSWebHostApp',
    'Uninstall-PSWebHostApp',
    'Test-PSWebHostAppStructure',
    'Export-PSWebHostApp',
    'Install-PSWebHostApp'
)
