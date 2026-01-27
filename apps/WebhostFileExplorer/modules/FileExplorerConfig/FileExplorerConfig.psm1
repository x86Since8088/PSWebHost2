#Requires -Version 7

<#
.SYNOPSIS
    FileExplorer Configuration Module

.DESCRIPTION
    Provides configuration management for FileExplorer root definitions.
    Supports dynamic root discovery, role-based access, and path template resolution.

.NOTES
    This module enables config-driven root management instead of hardcoded logic.
#>

# Module-level cache for configuration
$script:ConfigCache = $null
$script:ConfigCacheTime = $null
$script:ConfigCacheTTL = [TimeSpan]::FromMinutes(5)

<#
.SYNOPSIS
    Gets the path to the FileExplorer configuration file

.DESCRIPTION
    Returns the full path to roots.json in the app's data directory.
    Creates the config directory if it doesn't exist.

.EXAMPLE
    $configPath = Get-WebHostFileExplorerConfigPath
#>
function Get-WebHostFileExplorerConfigPath {
    [CmdletBinding()]
    param()

    try {
        # Determine data root from global state
        $dataRoot = if ($Global:PSWebServer['DataPath']) {
            $Global:PSWebServer['DataPath']
        } elseif ($Global:PSWebServer['DataRoot']) {
            $Global:PSWebServer['DataRoot']
        } else {
            # Fallback to default location
            $projectRoot = if ($Global:PSWebServer['Project_Root'].Path) {
                $Global:PSWebServer['Project_Root'].Path
            } else {
                # Last resort: calculate from module location
                Split-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
            }
            Join-Path $projectRoot "PsWebHost_Data"
        }

        # Build config path
        $configDir = Join-Path $dataRoot "apps\WebhostFileExplorer\config"
        $configPath = Join-Path $configDir "roots.json"

        # Ensure directory exists
        if (-not (Test-Path $configDir)) {
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            $logCmd = Get-Command -Name Write-PSWebHostLog -ErrorAction SilentlyContinue
            if ($logCmd) {
                & $logCmd -Severity 'Info' -Category 'FileExplorerConfig' -Message "Created config directory: $configDir"
            }
        }

        return $configPath
    }
    catch {
        $logCmd = Get-Command -Name Write-PSWebHostLog -ErrorAction SilentlyContinue
        if ($logCmd) {
            & $logCmd -Severity 'Error' -Category 'FileExplorerConfig' -Message "Failed to get config path: $($_.Exception.Message)"
        }
        throw
    }
}

<#
.SYNOPSIS
    Creates a default FileExplorer configuration

.DESCRIPTION
    Generates the default roots.json configuration with standard root definitions.

.PARAMETER Path
    Path where the configuration file should be created

.EXAMPLE
    New-WebHostFileExplorerDefaultConfig -Path "C:\path\to\roots.json"
#>
function New-WebHostFileExplorerDefaultConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $defaultConfig = @{
        version = "1.0"
        lastModified = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        roots = @(
            @{
                id = "user_me"
                name = "My Files"
                type = "personal"
                prefix = "User"
                identifier = "me"
                pathTemplate = "PsWebHost_Data/UserData/{UserID}/personal"
                roles = @("authenticated")
                removable = $false
                pathFormat = "local|localhost|User:me"
                description = "Personal user storage"
            }
            @{
                id = "user_others"
                name = "User Files (Admin)"
                type = "personal_admin"
                prefix = "User"
                identifier = "others"
                pathTemplate = "PsWebHost_Data/UserData/{TargetUserID}/personal"
                roles = @("system_admin")
                removable = $false
                dynamic = @{
                    enabled = $true
                    subpathType = "user_lookup"
                    patterns = @("{email}/{last4}", "{userID}")
                }
                description = "Browse all user directories (admin only)"
            }
            @{
                id = "buckets"
                type = "bucket"
                prefix = "Bucket"
                identifier = "{BucketID}"
                pathTemplate = "PsWebHost_Data/SharedBuckets/{BucketID}"
                roles = @("authenticated")
                dynamic = @{
                    enabled = $true
                    source = "database"
                }
                description = "Shared storage buckets"
            }
            @{
                id = "site_public"
                name = "Site: Public"
                type = "site"
                prefix = "Site"
                identifier = "public"
                pathTemplate = "{Project_Root.Path}/public"
                roles = @("site_admin", "system_admin")
                pathFormat = "local|localhost|Site:public"
                description = "Site public files"
            }
            @{
                id = "site_project_root"
                name = "Site: Project Root"
                type = "site"
                prefix = "Site"
                identifier = "Project_Root"
                pathTemplate = "{Project_Root.Path}"
                roles = @("system_admin")
                pathFormat = "local|localhost|Site:Project_Root"
                description = "Site project root directory"
            }
            @{
                id = "site_data"
                name = "Site: Data"
                type = "site"
                prefix = "Site"
                identifier = "data"
                pathTemplate = "{DataPath}"
                roles = @("system_admin")
                pathFormat = "local|localhost|Site:data"
                description = "Site data directory"
            }
        )
        systemRoots = @{
            enabled = $true
            roles = @("system_admin")
            removeLocalPrefix = $true
            windows = @{
                discoverDrives = $true
            }
            linux = @{
                discoverRoot = $true
            }
            description = "System drive access (admin only)"
        }
    }

    try {
        $configJson = $defaultConfig | ConvertTo-Json -Depth 10
        Set-Content -Path $Path -Value $configJson -Force -ErrorAction Stop
        $logCmd = Get-Command -Name Write-PSWebHostLog -ErrorAction SilentlyContinue
        if ($logCmd) {
            & $logCmd -Severity 'Info' -Category 'FileExplorerConfig' -Message "Created default configuration: $Path"
        }
        return $defaultConfig
    }
    catch {
        $logCmd = Get-Command -Name Write-PSWebHostLog -ErrorAction SilentlyContinue
        if ($logCmd) {
            & $logCmd -Severity 'Error' -Category 'FileExplorerConfig' -Message "Failed to create default config: $($_.Exception.Message)"
        }
        throw
    }
}

<#
.SYNOPSIS
    Resolves path templates with variable substitution

.DESCRIPTION
    Replaces template variables like {UserID}, {Project_Root.Path} with actual values
    from the global PSWebServer state.

.PARAMETER PathTemplate
    Path template string with variables in {curly braces}

.PARAMETER Variables
    Optional hashtable of additional variables for substitution

.EXAMPLE
    Resolve-WebHostFileExplorerConfigPath -PathTemplate "{Project_Root.Path}/public" -Variables @{UserID = "abc123"}
#>
function Resolve-WebHostFileExplorerConfigPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PathTemplate,

        [Parameter()]
        [hashtable]$Variables = @{}
    )

    try {
        $resolvedPath = $PathTemplate

        # Built-in variables from global state
        $builtInVars = @{
            'DataPath' = $Global:PSWebServer['DataPath']
            'DataRoot' = $Global:PSWebServer['DataRoot']
            'Project_Root.Path' = $Global:PSWebServer['Project_Root'].Path
        }

        # Merge built-in and custom variables (custom takes precedence)
        $allVars = $builtInVars + $Variables

        # Replace all {variable} patterns
        foreach ($key in $allVars.Keys) {
            $pattern = "{$key}"
            if ($resolvedPath -like "*$pattern*") {
                $value = $allVars[$key]
                if ($value) {
                    $resolvedPath = $resolvedPath -replace [regex]::Escape($pattern), $value
                }
            }
        }

        # Check for unresolved variables
        if ($resolvedPath -match '\{[^}]+\}') {
            $logCmd = Get-Command -Name Write-PSWebHostLog -ErrorAction SilentlyContinue
            if ($logCmd) {
                & $logCmd -Severity 'Warning' -Category 'FileExplorerConfig' -Message "Path template has unresolved variables: $resolvedPath"
            }
        }

        return $resolvedPath
    }
    catch {
        $logCmd = Get-Command -Name Write-PSWebHostLog -ErrorAction SilentlyContinue
        if ($logCmd) {
            & $logCmd -Severity 'Error' -Category 'FileExplorerConfig' -Message "Failed to resolve path template: $($_.Exception.Message)"
        }
        return $PathTemplate
    }
}

<#
.SYNOPSIS
    Loads the FileExplorer configuration with caching

.DESCRIPTION
    Reads roots.json configuration file with 5-minute TTL caching.
    Creates default configuration if file doesn't exist.

.PARAMETER Force
    Bypass cache and force reload from disk

.EXAMPLE
    $config = Get-WebHostFileExplorerConfig
    $config = Get-WebHostFileExplorerConfig -Force
#>
function Get-WebHostFileExplorerConfig {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Force
    )

    try {
        # Check cache
        $now = Get-Date
        if (-not $Force -and $script:ConfigCache -and $script:ConfigCacheTime) {
            $age = $now - $script:ConfigCacheTime
            if ($age -lt $script:ConfigCacheTTL) {
                Write-Verbose "Returning cached configuration (age: $($age.TotalSeconds)s)"
                return $script:ConfigCache
            }
        }

        # Get config path
        $configPath = Get-WebHostFileExplorerConfigPath

        # Load or create configuration
        if (Test-Path $configPath) {
            $configJson = Get-Content -Path $configPath -Raw -ErrorAction Stop
            $config = $configJson | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            $logCmd = Get-Command -Name Write-PSWebHostLog -ErrorAction SilentlyContinue
            if ($logCmd) {
                & $logCmd -Severity 'Verbose' -Category 'FileExplorerConfig' -Message "Loaded configuration from: $configPath"
            }
        }
        else {
            $logCmd = Get-Command -Name Write-PSWebHostLog -ErrorAction SilentlyContinue
            if ($logCmd) {
                & $logCmd -Severity 'Info' -Category 'FileExplorerConfig' -Message "Configuration not found, creating default: $configPath"
            }
            $config = New-WebHostFileExplorerDefaultConfig -Path $configPath
        }

        # Update cache
        $script:ConfigCache = $config
        $script:ConfigCacheTime = $now

        return $config
    }
    catch {
        $logCmd = Get-Command -Name Write-PSWebHostLog -ErrorAction SilentlyContinue
        if ($logCmd) {
            & $logCmd -Severity 'Error' -Category 'FileExplorerConfig' -Message "Failed to load configuration: $($_.Exception.Message)" -Data @{
                Error = $_.Exception.ToString()
            }
        }
        return $null
    }
}

<#
.SYNOPSIS
    Clears the configuration cache

.DESCRIPTION
    Forces the next Get-WebHostFileExplorerConfig call to reload from disk.

.EXAMPLE
    Clear-WebHostFileExplorerConfigCache
#>
function Clear-WebHostFileExplorerConfigCache {
    [CmdletBinding()]
    param()

    $script:ConfigCache = $null
    $script:ConfigCacheTime = $null
    $logCmd = Get-Command -Name Write-PSWebHostLog -ErrorAction SilentlyContinue
    if ($logCmd) {
        & $logCmd -Severity 'Verbose' -Category 'FileExplorerConfig' -Message "Configuration cache cleared"
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-WebHostFileExplorerConfigPath',
    'New-WebHostFileExplorerDefaultConfig',
    'Resolve-WebHostFileExplorerConfigPath',
    'Get-WebHostFileExplorerConfig',
    'Clear-WebHostFileExplorerConfigCache'
)
