param (
    [switch]$Loadvariables,
    [switch]$Force
)

# ============================================================================
# Duplicate Loading Prevention
# ============================================================================
if ($PSWebHostDotSourceLoaded -and $global:PSWebHostGlobalLoaded -and -not $Force.IsPresent) {
    return Write-Host ".\init has already been loaded and -Force is not being used. Skipping."
}

# ============================================================================
# PowerShell Version Check - Require PowerShell 7 or later
# ============================================================================
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "`n========================================================================================================" -ForegroundColor Red
    Write-Host "  ERROR: PowerShell 7 or later is required to run PSWebHost" -ForegroundColor Red
    Write-Host "========================================================================================================" -ForegroundColor Red
    Write-Host "`nCurrent version: PowerShell $($PSVersionTable.PSVersion.ToString())" -ForegroundColor Yellow
    Write-Host "Required version: PowerShell 7.0 or later`n" -ForegroundColor Yellow

    Write-Host "Installation Instructions:" -ForegroundColor Cyan
    Write-Host "-------------------------`n" -ForegroundColor Cyan

    # Use built-in OS detection variables (available in PowerShell 6+)
    # Note: These are read-only automatic variables, don't assign to them
    if ($IsWindows) {
        Write-Host "Windows - Option 1 (Recommended): Using Winget" -ForegroundColor Green
        Write-Host "  winget install --id Microsoft.Powershell --source winget`n" -ForegroundColor White

        Write-Host "Windows - Option 2: Using MSI Installer" -ForegroundColor Green
        Write-Host "  Download from: https://aka.ms/powershell-release?tag=stable`n" -ForegroundColor White

        Write-Host "Windows - Option 3: Using Windows Package Manager" -ForegroundColor Green
        Write-Host "  Install from Microsoft Store: search for 'PowerShell'`n" -ForegroundColor White
    } elseif ($IsLinux) {
        Write-Host "Linux - Detect your distribution and use the appropriate command:`n" -ForegroundColor Green

        Write-Host "Ubuntu/Debian:" -ForegroundColor Cyan
        Write-Host "  sudo apt-get update" -ForegroundColor White
        Write-Host "  sudo apt-get install -y wget apt-transport-https software-properties-common" -ForegroundColor White
        Write-Host "  wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb" -ForegroundColor White
        Write-Host "  sudo dpkg -i packages-microsoft-prod.deb" -ForegroundColor White
        Write-Host "  sudo apt-get update" -ForegroundColor White
        Write-Host "  sudo apt-get install -y powershell`n" -ForegroundColor White

        Write-Host "RHEL/CentOS/Fedora:" -ForegroundColor Cyan
        Write-Host "  sudo dnf install -y powershell`n" -ForegroundColor White

        Write-Host "Arch Linux:" -ForegroundColor Cyan
        Write-Host "  yay -S powershell-bin`n" -ForegroundColor White
    } elseif ($IsMacOS) {
        Write-Host "macOS - Using Homebrew:" -ForegroundColor Green
        Write-Host "  brew install --cask powershell`n" -ForegroundColor White
    }

    Write-Host "After installation, run this script again using:" -ForegroundColor Yellow
    Write-Host "  pwsh $($MyInvocation.MyCommand.Path)`n" -ForegroundColor White

    Write-Host "For more information, visit:" -ForegroundColor Cyan
    Write-Host "  https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell`n" -ForegroundColor White

    Write-Host "========================================================================================================`n" -ForegroundColor Red
    exit 1
}

# Define project root
if ($null -eq $ProjectRoot) {
    $ProjectRoot = Split-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition)
}
# Use synchronized hashtable for thread-safe access from async runspaces
$Global:PSWebServer = [hashtable]::Synchronized(@{})
$Global:PSWebServer.Project_Root = [hashtable]::Synchronized(@{ Path = $ProjectRoot })

# Add modules folder to PSModulePath
$modulesFolderPath = Join-Path $Global:PSWebServer.Project_Root.Path "modules"
if (-not ($Env:PSModulePath -split ';' -contains $modulesFolderPath)) {
    $Env:PSModulePath = "$modulesFolderPath;$($Env:PSModulePath)"
    Write-Verbose "Added '$modulesFolderPath' to PSModulePath." -Verbose
}

$Global:PSWebServer.Modules = [hashtable]::Synchronized(@{})

function Import-TrackedModule {
    param (
        [string]$Path
    )
    $moduleInfo = Import-Module $Path -Force -DisableNameChecking -PassThru 3>$null
    $fileInfo = Get-Item -Path $Path
    $Global:PSWebServer.Modules[$moduleInfo.Name] = @{
        Path = $Path
        LastWriteTime = $fileInfo.LastWriteTime
        Loaded = (Get-Date)
    }
    Write-Verbose "Tracked module $($moduleInfo.Name) from $Path" -Verbose
}

# Source core functions using full paths and track them
Import-TrackedModule -Path (Join-Path $modulesFolderPath "Sanitization/Sanitization.psm1")
Import-TrackedModule -Path (Join-Path $modulesFolderPath "PSWebHost_Support/PSWebHost_Support.psd1")
Import-TrackedModule -Path (Join-Path $modulesFolderPath "PSWebHost_Database/PSWebHost_Database.psd1")
Import-TrackedModule -Path (Join-Path $modulesFolderPath "PSWebHost_Authentication/PSWebHost_Authentication.psd1")
Import-TrackedModule -Path (Join-Path $modulesFolderPath "smtp/smtp.psd1")

# Validate installation, dependencies, and database schema
& (Join-Path $PSScriptRoot 'validateInstall.ps1')

try {
    Import-Module PSSQLite 
}
catch {
    Write-Error -Message "Error importing PSSQLite module: $($_.Exception.Message)"
}
if ($Loadvariables.IsPresent) {return}


# Load configuration
$Configfile = Join-Path $ProjectRoot "config/settings.json"

# Create default config if it doesn't exist
if (-not (Test-Path $Configfile)) {
    Write-Verbose "Config file not found. Creating default configuration at: $Configfile" -Verbose

    $configDir = Split-Path $Configfile -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }

    $defaultConfig = @{
        WebServer = @{
            Port = 8080
            HttpsPort = 8443
            AuthenticationSchemes = "Anonymous"
        }
        MimeTypes = @{
            ".css" = "text/css"
            ".js" = "application/javascript"
            ".html" = "text/html"
            ".png" = "image/png"
            ".jpg" = "image/jpeg"
            ".jpeg" = "image/jpeg"
            ".gif" = "image/gif"
            ".svg" = "image/svg+xml"
            ".ico" = "image/x-icon"
            ".webp" = "image/webp"
            ".json" = "application/json"
            ".txt" = "text/plain"
            ".pdf" = "application/pdf"
            ".xml" = "application/xml"
            ".csv" = "text/csv"
            ".zip" = "application/zip"
            ".gz" = "application/gzip"
            ".7z" = "application/x-7z-compressed"
            ".mp3" = "audio/mpeg"
            ".wav" = "audio/wav"
            ".ogg" = "audio/ogg"
            ".mp4" = "video/mp4"
            ".webm" = "video/webm"
            ".ttf" = "font/ttf"
            ".otf" = "font/otf"
            ".woff" = "font/woff"
            ".woff2" = "font/woff2"
            ".wasm" = "application/wasm"
        }
        authentication = @{
            providers = @{
                WindowsIntegrated = @{
                    Type = "Windows"
                    AccountNameRegex = "^[\.\w]+[\\/]*\w*$"
                    endpoint = "/api/v1/authprovider/windows"
                    RedirectFieldName = $null
                    cors_origin = $null
                }
            }
        }
        roles = @(
            "site_admin"
            "vault_admin"
            "system_admin"
            "user"
            "unauthenticated"
            "authenticated"
        )
        debug_url = @{
            default = @{
                PSNativeCommandUseErrorActionPreference = "False"
                ProgressPreference = "Continue"
                ConfirmPreference = "High"
                DebugPreference = "SilentlyContinue"
                WhatIfPreference = "False"
                ErrorActionPreference = "Continue"
                InformationPreference = "SilentlyContinue"
                VerbosePreference = "SilentlyContinue"
                WarningPreference = "Continue"
            }
            "/api/v1" = @{
                VerbosePreference = "Continue"
            }
        }
        Data = @{
            UserDataStorage = @("PsWebHost_Data\UserData")
        }
    }

    $defaultConfig | ConvertTo-Json -Depth 10 | Set-Content $Configfile -Encoding UTF8
    Write-Verbose "Default configuration created successfully." -Verbose
}

$Global:PSWebServer.Config = (Get-Content $Configfile | ConvertFrom-Json)
$Global:PSWebServer.SettingsLastWriteTime = (Get-Item $Configfile).LastWriteTime

# --- Node GUID Generation ---
# Each PSWebHost instance needs a unique identifier for node-to-node communication
$configUpdated = $false
if (-not $Global:PSWebServer.Config.WebServer.guid) {
    $newGuid = [guid]::NewGuid().ToString()
    Write-Verbose "Generated new Node GUID: $newGuid" -Verbose

    # Add guid property to WebServer config
    $Global:PSWebServer.Config.WebServer | Add-Member -MemberType NoteProperty -Name 'guid' -Value $newGuid -Force
    $configUpdated = $true
}
$Global:PSWebServer.NodeGuid = $Global:PSWebServer.Config.WebServer.guid
Write-Verbose "Node GUID: $($Global:PSWebServer.NodeGuid)" -Verbose

# --- Nodes Configuration ---
$nodesConfigFile = Join-Path $ProjectRoot "config/nodes.json"
if (-not (Test-Path $nodesConfigFile)) {
    $defaultNodesConfig = @{
        nodes = @{}
    }
    $defaultNodesConfig | ConvertTo-Json -Depth 5 | Set-Content $nodesConfigFile -Encoding UTF8
    Write-Verbose "Created default nodes configuration at: $nodesConfigFile" -Verbose
}
$Global:PSWebServer.NodesConfig = (Get-Content $nodesConfigFile | ConvertFrom-Json)
$Global:PSWebServer.NodesConfigPath = $nodesConfigFile

# --- API Keys Configuration ---
# Built-in API keys for localhost admin and global_read access
# API keys are linked to system user accounts - roles come from the user
function New-ApiKeyString {
    # Generate a secure random API key (32 bytes = 256 bits, Base64 encoded)
    $bytes = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return [Convert]::ToBase64String($bytes)
}

# Ensure system users exist for API keys
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
$systemUsers = @(
    @{
        UserID = 'system:localhost_admin'
        Email = 'localhost_admin@system.local'
        Roles = @('admin', 'site_admin', 'system_admin', 'authenticated')
    },
    @{
        UserID = 'system:global_read'
        Email = 'global_read@system.local'
        Roles = @('authenticated')
    }
)

foreach ($sysUser in $systemUsers) {
    $existingUser = Get-PSWebSQLiteData -File $dbFile -Query "SELECT UserID FROM Users WHERE UserID = '$($sysUser.UserID)';"
    if (-not $existingUser) {
        Write-Host "[Init] Creating system user: $($sysUser.UserID)" -ForegroundColor Cyan
        # Create system user with a placeholder password hash (not used for login)
        $placeholderHash = 'SYSTEM_ACCOUNT_NO_PASSWORD_LOGIN'
        $safeUserID = Sanitize-SqlQueryString -String $sysUser.UserID
        $safeEmail = Sanitize-SqlQueryString -String $sysUser.Email
        $insertQuery = "INSERT INTO Users (ID, UserID, Email, PasswordHash) VALUES ('$([guid]::NewGuid().ToString())', '$safeUserID', '$safeEmail', '$placeholderHash');"
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $insertQuery

        # Assign roles to the system user
        foreach ($role in $sysUser.Roles) {
            $safeRole = Sanitize-SqlQueryString -String $role
            $roleQuery = "INSERT OR IGNORE INTO PSWeb_Roles (PrincipalID, PrincipalType, RoleName) VALUES ('$safeUserID', 'User', '$safeRole');"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $roleQuery
        }
        Write-Verbose "[Init] System user created with roles: $($sysUser.Roles -join ', ')" -Verbose
    }
}

if (-not $Global:PSWebServer.Config.ApiKeys) {
    Write-Verbose "Generating built-in API keys..." -Verbose

    # Generate new API keys
    $localhostAdminKey = New-ApiKeyString
    $globalReadKey = New-ApiKeyString

    $apiKeysConfig = [PSCustomObject]@{
        localhost_admin = [PSCustomObject]@{
            key = $localhostAdminKey
            user_id = 'system:localhost_admin'
            allowed_ips = @('127.0.0.1', '::1', 'localhost')
            description = 'Admin access for localhost connections only'
        }
        global_read = [PSCustomObject]@{
            key = $globalReadKey
            user_id = 'system:global_read'
            allowed_ips = @()  # Empty means all IPs allowed
            description = 'Read-only access from any IP'
        }
    }

    $Global:PSWebServer.Config | Add-Member -MemberType NoteProperty -Name 'ApiKeys' -Value $apiKeysConfig -Force
    $configUpdated = $true

    Write-Host "[Init] Generated new API keys:" -ForegroundColor Cyan
    Write-Host "  localhost_admin: $localhostAdminKey" -ForegroundColor Yellow
    Write-Host "  global_read: $globalReadKey" -ForegroundColor Yellow
    Write-Host "  (These are displayed only once - save them securely!)" -ForegroundColor Red
}

# Store API keys in memory for quick access
$Global:PSWebServer.ApiKeys = @{}
if ($Global:PSWebServer.Config.ApiKeys) {
    foreach ($keyName in @('localhost_admin', 'global_read')) {
        $keyConfig = $Global:PSWebServer.Config.ApiKeys.$keyName
        if ($keyConfig -and $keyConfig.key) {
            $Global:PSWebServer.ApiKeys[$keyConfig.key] = @{
                Name = $keyName
                UserID = $keyConfig.user_id
                AllowedIPs = $keyConfig.allowed_ips
                Description = $keyConfig.description
                Source = 'config'
            }
        }
    }
    Write-Verbose "Loaded $($Global:PSWebServer.ApiKeys.Count) API keys from config" -Verbose
}

# Securely handle SMTP password
if ($Global:PSWebServer.Config.Smtp -and -not [string]::IsNullOrEmpty($Global:PSWebServer.Config.Smtp.Password)) {
    $securePassword = $Global:PSWebServer.Config.Smtp.Password | ConvertTo-SecureString -AsPlainText -Force
    $Global:PSWebServer.Config.Smtp.PasswordSecureString = $securePassword | ConvertFrom-SecureString
    # Clear the plaintext password from the in-memory config
    $Global:PSWebServer.Config.Smtp.Password = $null
}

# Securely handle Google client_secret
if ($Global:PSWebServer.Config.authentication.providers.Google -and -not [string]::IsNullOrEmpty($Global:PSWebServer.Config.authentication.providers.Google.client_secret)) {
    $secureClientSecret = $Global:PSWebServer.Config.authentication.providers.Google.client_secret | ConvertTo-SecureString -AsPlainText -Force
    $Global:PSWebServer.Config.authentication.providers.Google.client_secret_securestring = $secureClientSecret | ConvertFrom-SecureString
    # Clear the plaintext password from the in-memory config
    $Global:PSWebServer.Config.authentication.providers.Google.client_secret = $null
}

# Securely handle o365 client_secret
if ($Global:PSWebServer.Config.authentication.providers.o365 -and -not [string]::IsNullOrEmpty($Global:PSWebServer.Config.authentication.providers.o365.client_secret)) {
    $secureClientSecret = $Global:PSWebServer.Config.authentication.providers.o365.client_secret | ConvertTo-SecureString -AsPlainText -Force
    $Global:PSWebServer.Config.authentication.providers.o365.client_secret_securestring = $secureClientSecret | ConvertFrom-SecureString
    # Clear the plaintext password from the in-memory config
    $Global:PSWebServer.Config.authentication.providers.o365.client_secret = $null
}

# Securely handle GoogleMaps ApiKey
if ($Global:PSWebServer.Config.GoogleMaps -and -not [string]::IsNullOrEmpty($Global:PSWebServer.Config.GoogleMaps.ApiKey)) {
    $secureApiKey = $Global:PSWebServer.Config.GoogleMaps.ApiKey | ConvertTo-SecureString -AsPlainText -Force
    $Global:PSWebServer.Config.GoogleMaps.ApiKey_securestring = $secureApiKey | ConvertFrom-SecureString
    # Clear the plaintext password from the in-memory config
    $Global:PSWebServer.Config.GoogleMaps.ApiKey = $null
}

# Initialize UserDataStorage if not present
if (-not $Global:PSWebServer.Config.Data) {
    $Global:PSWebServer.Config | Add-Member -MemberType NoteProperty -Name 'Data' -Value ([PSCustomObject]@{
        UserDataStorage = @("PsWebHost_Data\UserData")
    })
    $configUpdated = $true
}
elseif (-not $Global:PSWebServer.Config.Data.UserDataStorage -or $Global:PSWebServer.Config.Data.UserDataStorage.Count -eq 0) {
    $Global:PSWebServer.Config.Data | Add-Member -MemberType NoteProperty -Name 'UserDataStorage' -Value @("PsWebHost_Data\UserData") -Force
    $configUpdated = $true
}

# Save config if updated (GUID, UserDataStorage, etc.)
if ($configUpdated) {
    $Global:PSWebServer.Config | ConvertTo-Json -Depth 10 | Set-Content $Configfile
    Write-Verbose "Updated configuration file with new settings." -Verbose
}

# Ensure UserData directories exist
foreach ($storagePath in $Global:PSWebServer.Config.Data.UserDataStorage) {
    $fullPath = if ([System.IO.Path]::IsPathRooted($storagePath)) {
        $storagePath
    } else {
        Join-Path $ProjectRoot $storagePath
    }
    if (-not (Test-Path $fullPath)) {
        New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
        Write-Verbose "Created user data storage directory: $fullPath" -Verbose
    }
}

# Add ModuleDownload folder to PSModulePath for third-party modules
$moduleDownloadPath = Join-Path $Global:PSWebServer.Project_Root.Path "ModuleDownload"
if (-not (Test-Path $moduleDownloadPath)) {
    New-Item -Path $moduleDownloadPath -ItemType Directory -Force | Out-Null
    Write-Verbose "Created ModuleDownload directory: $moduleDownloadPath" -Verbose
}
if (-not ($Env:PSModulePath -split ';' -contains $moduleDownloadPath)) {
    $Env:PSModulePath = "$moduleDownloadPath;$($Env:PSModulePath)"
    Write-Verbose "Added '$moduleDownloadPath' to PSModulePath." -Verbose
}

# --- Thread-Safe Logging Setup ---
$global:PSWebHostLogQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$global:PSHostUIQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

# Load timestamp helper function
. (Join-Path $PSScriptRoot 'Get-PSWebHostTimestamp.ps1')

# Generate timestamped log filename using ISO 8601 format with timezone
# Format: YYYY-MM-DDTHHMMSS_mmmmmmmZZZZ (e.g., 2025-12-31T012345_1234567-0800)
# This format includes timezone offset and handles daylight savings changes
$logTimestamp = Get-PSWebHostTimestamp -ForFilename
$logFileName = "log_$logTimestamp.tsv"
$Global:PSWebServer.LogFilePath = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/Logs/$logFileName"

# Store the logs directory path for API access
$Global:PSWebServer.LogDirectory = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/Logs"

# Ensure the Logs directory exists
if (-not (Test-Path $Global:PSWebServer.LogDirectory)) {
    New-Item -Path $Global:PSWebServer.LogDirectory -ItemType Directory -Force | Out-Null
    Write-Verbose "Created logs directory: $($Global:PSWebServer.LogDirectory)" -Verbose
}

# --- Real-Time Event Stream Buffer ---
# Initialize a thread-safe ring buffer for real-time log events
$Global:PSWebServer.EventStreamBuffer = [System.Collections.Concurrent.ConcurrentQueue[PSCustomObject]]::new()
$Global:PSWebServer.EventStreamMaxSize = 1000  # Maximum events to retain
$Global:PSWebServer.EventStreamJobName = "PSWebHost_LogTail_EventStream"

# --- Log History for Event Stream ---
# Initialize a thread-safe synchronized hashtable for log history
$Global:LogHistory = [hashtable]::Synchronized(@{})
$Global:LogHistoryMaxSize = 5000  # Maximum entries to retain
$Global:LogHistoryIndex = 0  # Auto-incrementing index for ordering

$global:StopLogging = [ref]$false

$loggingScriptBlock = {
    param($logQueue, $logFilePath, $stopSignal)

    # Ensure log directory exists
    $logDirectory = Split-Path $logFilePath -Parent
    if (-not (Test-Path $logDirectory)) {
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    }

    while (-not $stopSignal.Value) {
        $logEntries = [System.Collections.Generic.List[string]]::new()
        $logEntry = $null

        # Dequeue all available log entries
        while ($logQueue.TryDequeue([ref]$logEntry)) {
            if ($logEntry) {
                $logEntries.Add($logEntry)
            }
        }

        # Write entries to file in batch
        if ($logEntries.Count -gt 0) {
            try {
                Add-Content -Path $logFilePath -Value $logEntries -ErrorAction SilentlyContinue
            } catch {
                # Silently ignore write errors to prevent logging loop
            }
        }

        Start-Sleep -Milliseconds 100
    }
}

$loggingPowerShell = [powershell]::Create().AddScript($loggingScriptBlock).AddParameters(@{
    logQueue = $global:PSWebHostLogQueue
    logFilePath = $Global:PSWebServer.LogFilePath
    stopSignal = $global:StopLogging
})
$global:LoggingPS = $loggingPowerShell
$global:PSWebServer.LoggingJob = $loggingPowerShell.BeginInvoke()
Write-Verbose "Started background logging job." -Verbose
# --- End Logging Setup ---

# --- Log History Collection Job ---
$global:StopLogHistoryCollection = [ref]$false

$logHistoryScriptBlock = {
    param($logHistory, $logHistoryMaxSize, $logHistoryIndex, $stopSignal, $projectRoot)

    # Helper function to get log tail jobs and receive their output
    function Get-LogTailOutput {
        param($ProjectRoot)

        # Get all Log_Tail jobs
        $jobs = Get-Job -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'Log_Tail:*' }

        $allOutput = @()
        foreach ($job in $jobs) {
            if ($job.HasMoreData) {
                # Receive output from job
                $output = Receive-Job -Job $job -ErrorAction SilentlyContinue

                if ($output) {
                    foreach ($entry in $output) {
                        # Parse TSV line from log tail output
                        if ($entry.Line) {
                            $fields = $entry.Line -split "`t"
                            if ($fields.Count -ge 5) {
                                # Unescape the data field (remove backslash escaping)
                                $dataField = if ($fields.Count -gt 4) { $fields[4] } else { '' }
                                $dataField = $dataField -replace '\\(.)', '$1'

                                $allOutput += [PSCustomObject]@{
                                    Path = $entry.Path
                                    Date = $fields[0]
                                    DateTimeOffset = $fields[1]
                                    Severity = $fields[2]
                                    Category = if ($fields.Count -gt 3) { $fields[3] } else { '' }
                                    Message = $dataField
                                    LineNumber = $entry.LineNumber
                                    ReceivedAt = $entry.Date
                                }
                            }
                        }
                    }
                }
            }
        }

        return $allOutput
    }

    while (-not $stopSignal.Value) {
        try {
            # Collect log entries from all Log_Tail jobs
            $logEntries = Get-LogTailOutput -ProjectRoot $projectRoot

            # Add entries to synchronized hashtable
            foreach ($entry in $logEntries) {
                # Increment index (thread-safe via lock)
                $index = [System.Threading.Interlocked]::Increment([ref]$logHistoryIndex.Value)

                # Create event entry
                $eventEntry = @{
                    Index = $index
                    Date = $entry.Date
                    DateTimeOffset = $entry.DateTimeOffset
                    state = $entry.Severity
                    UserID = $entry.Category
                    Provider = 'System'
                    Data = $entry.Message
                    Path = $entry.Path
                    LineNumber = $entry.LineNumber
                    ReceivedAt = $entry.ReceivedAt
                    _timestamp = Get-Date
                }

                # Add to hashtable
                $logHistory[$index] = $eventEntry
            }

            # Trim to max size - keep most recent entries
            $currentSize = $logHistory.Count
            if ($currentSize -gt $logHistoryMaxSize) {
                $entriesToRemove = $currentSize - $logHistoryMaxSize

                # Get all keys sorted by index
                $allKeys = @($logHistory.Keys | Sort-Object)

                # Remove oldest entries
                for ($i = 0; $i -lt $entriesToRemove -and $i -lt $allKeys.Count; $i++) {
                    $logHistory.Remove($allKeys[$i])
                }
            }

        } catch {
            # Silently continue on errors to prevent job crash
            Start-Sleep -Milliseconds 500
        }

        Start-Sleep -Milliseconds 500
    }
}

$logHistoryPowerShell = [powershell]::Create().AddScript($logHistoryScriptBlock).AddParameters(@{
    logHistory = $Global:LogHistory
    logHistoryMaxSize = $Global:LogHistoryMaxSize
    logHistoryIndex = [ref]$Global:LogHistoryIndex
    stopSignal = $global:StopLogHistoryCollection
    projectRoot = $Global:PSWebServer.Project_Root.Path
})
$global:LogHistoryPS = $logHistoryPowerShell
$global:PSWebServer.LogHistoryJob = $logHistoryPowerShell.BeginInvoke()
Write-Verbose "Started log history collection job." -Verbose
# --- End Log History Setup ---


# Register roles from config if they don't exist
if ($Global:PSWebServer.Config.roles) {
    $configRoles = $Global:PSWebServer.Config.roles
    $dbRoles = Get-PSWebHostRole -ListAll
    foreach ($role in $configRoles) {
        if ($role -notin $dbRoles) {
            Write-Verbose "Registering role '$role' from config." -Verbose
            Add-PSWebHostRole -RoleName $role
        }
    }
}

# --- Apps Framework Initialization ---
# Initialize thread-safe apps registry
$Global:PSWebServer.Apps = [hashtable]::Synchronized(@{})
$appsPath = Join-Path $Global:PSWebServer.Project_Root.Path "apps"

# Create apps directory if it doesn't exist
if (-not (Test-Path $appsPath)) {
    New-Item -Path $appsPath -ItemType Directory -Force | Out-Null
    Write-Verbose "Created apps directory: $appsPath" -Verbose
}

# Load and initialize each app
Get-ChildItem -Path $appsPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $appDir = $_.FullName
    $appName = $_.Name
    $manifestPath = Join-Path $appDir "app.yaml"

    if (Test-Path $manifestPath) {
        try {
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Yaml

            if ($manifest.enabled) {
                # Add app modules to PSModulePath
                $appModulesPath = Join-Path $appDir "modules"
                if (Test-Path $appModulesPath) {
                    if (-not ($Env:PSModulePath -split ';' -contains $appModulesPath)) {
                        $Env:PSModulePath = "$appModulesPath;$($Env:PSModulePath)"
                        Write-Verbose "Added app modules path: $appModulesPath" -Verbose
                    }
                }

                # Run app_init.ps1 if it exists
                $initScript = Join-Path $appDir "app_init.ps1"
                if (Test-Path $initScript) {
                    try {
                        & $initScript -PSWebServer $Global:PSWebServer -AppRoot $appDir
                        Write-Verbose "Executed app init script for: $appName" -Verbose
                    } catch {
                        Write-Warning "Failed to execute app_init.ps1 for app '$appName': $($_.Exception.Message)"
                    }
                }

                # Track the app
                # DataPath points to centralized PsWebHost_Data/apps/[app name]
                $centralDataPath = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\apps\$appName"
                if (-not (Test-Path $centralDataPath)) {
                    New-Item -Path $centralDataPath -ItemType Directory -Force | Out-Null
                }

                $appData = @{
                    Path = $appDir
                    Manifest = $manifest
                    ManifestPath = $manifestPath
                    Loaded = Get-Date
                    ModulesPath = $appModulesPath
                    RoutesPath = Join-Path $appDir "routes"
                    PublicPath = Join-Path $appDir "public"
                    DataPath = $centralDataPath
                }

                # Register app by folder name
                $Global:PSWebServer.Apps[$appName] = $appData

                # Also register by routePrefix if it exists (allows /apps/uplot to map to UI_Uplot folder)
                if ($manifest.routePrefix -and $manifest.routePrefix -match '^/apps/([a-zA-Z0-9_-]+)') {
                    $routePrefixName = $matches[1]
                    if ($routePrefixName -ne $appName) {
                        $Global:PSWebServer.Apps[$routePrefixName] = $appData
                        Write-Verbose "  Registered app '$appName' also as '$routePrefixName' (from routePrefix)" -Verbose
                    }
                }

                Write-Host "[Init] Loaded app: $appName (v$($manifest.version))" -ForegroundColor Green
            } else {
                Write-Verbose "App '$appName' is disabled, skipping." -Verbose
            }
        } catch {
            Write-Warning "Failed to load app '$appName': $($_.Exception.Message)"
        }
    } else {
        Write-Verbose "No app.yaml found in '$appName', skipping." -Verbose
    }
}

Write-Verbose "Apps framework initialized. Loaded $($Global:PSWebServer.Apps.Count) app(s)." -Verbose

# --- Build Merged Category Structure ---
# Merge duplicate parent categories across apps
$Global:PSWebServer.Categories = [hashtable]::Synchronized(@{})

foreach ($appName in $Global:PSWebServer.Apps.Keys) {
    $appInfo = $Global:PSWebServer.Apps[$appName]
    $manifest = $appInfo.Manifest

    # Skip apps without category structure
    if (-not $manifest.parentCategory) {
        continue
    }

    $parentCat = $manifest.parentCategory
    $subCat = $manifest.subCategory

    # Use category ID as key for merging
    $categoryId = $parentCat.id

    # Create or update parent category
    if (-not $Global:PSWebServer.Categories.ContainsKey($categoryId)) {
        $Global:PSWebServer.Categories[$categoryId] = @{
            id = $parentCat.id
            name = $parentCat.name
            description = $parentCat.description
            icon = $parentCat.icon
            order = $parentCat.order
            subCategories = [hashtable]::Synchronized(@{})
            apps = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
        }
        Write-Verbose "[Init] Created category: $($parentCat.name) (id: $categoryId)" -Verbose
    }

    $category = $Global:PSWebServer.Categories[$categoryId]

    # Create subcategory key (use name as key)
    $subCategoryKey = if ($subCat.name) { $subCat.name } else { "default" }

    # Create or update subcategory
    if (-not $category.subCategories.ContainsKey($subCategoryKey)) {
        $category.subCategories[$subCategoryKey] = @{
            name = $subCat.name
            order = if ($subCat.order) { $subCat.order } else { 999 }
            apps = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
        }
        Write-Verbose "[Init]   Added subcategory: $subCategoryKey (order: $($subCat.order))" -Verbose
    }

    # Add app to subcategory
    $subCategory = $category.subCategories[$subCategoryKey]
    $null = $subCategory.apps.Add(@{
        name = $appName
        displayName = $manifest.name
        version = $manifest.version
        description = $manifest.description
        routePrefix = $manifest.routePrefix
        requiredRoles = $manifest.requiredRoles
    })

    # Also add to parent category apps list
    $null = $category.apps.Add($appName)

    Write-Verbose "[Init]   Added app '$appName' to category '$($parentCat.name)' > '$subCategoryKey'" -Verbose
}

Write-Host "[Init] Built category structure: $($Global:PSWebServer.Categories.Count) parent categories" -ForegroundColor Green
foreach ($catId in ($Global:PSWebServer.Categories.Keys | Sort-Object)) {
    $cat = $Global:PSWebServer.Categories[$catId]
    $subCatCount = $cat.subCategories.Count
    $appCount = $cat.apps.Count
    Write-Verbose "[Init]   - $($cat.name): $subCatCount subcategories, $appCount apps" -Verbose
}

# --- End Apps Framework Initialization ---

# NOTE: App-specific initialization (modules, background jobs, data directories, etc.)
# is now handled by each app's app_init.ps1 file, which is automatically discovered
# and executed by the app framework above. See apps/*/app_init.ps1 for details.

# ============================================================================
# Mark init.ps1 as loaded to prevent duplicate loading
# ============================================================================
$PSWebHostDotSourceLoaded = $true
$global:PSWebHostGlobalLoaded = $true