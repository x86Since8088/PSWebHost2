param (
    [switch]$Loadvariables
)
# Define project root
if ($null -eq $ProjectRoot) {
    $ProjectRoot = Split-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition)
}
$Global:PSWebServer = @{}
$Global:PSWebServer.Project_Root = @{ Path = $ProjectRoot }

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

# Save config if updated
if ($configUpdated) {
    $Global:PSWebServer.Config | ConvertTo-Json -Depth 10 | Set-Content $Configfile
    Write-Verbose "Initialized Data.UserDataStorage in configuration." -Verbose
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

# Add modules folder to PSModulePath
$modulesFolderPath = Join-Path $Global:PSWebServer.Project_Root.Path "modules"
if (-not ($Env:PSModulePath -split ';' -contains $modulesFolderPath)) {
    $Env:PSModulePath = "$modulesFolderPath;$($Env:PSModulePath)"
    Write-Verbose "Added '$modulesFolderPath' to PSModulePath." -Verbose
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
$Global:PSWebServer.LogFilePath = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/Logs/log.tsv"

# Ensure the Logs directory exists
$logDirectory = Split-Path $Global:PSWebServer.LogFilePath -Parent
if (-not (Test-Path $logDirectory)) {
    New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    Write-Verbose "Created logs directory: $logDirectory" -Verbose
}

# --- Real-Time Event Stream Buffer ---
# Initialize a thread-safe ring buffer for real-time log events
$Global:PSWebServer.EventStreamBuffer = [System.Collections.Concurrent.ConcurrentQueue[PSCustomObject]]::new()
$Global:PSWebServer.EventStreamMaxSize = 1000  # Maximum events to retain
$Global:PSWebServer.EventStreamJobName = "PSWebHost_LogTail_EventStream"

<#
$global:StopLogging = $false

$loggingScriptBlock = {
    param($logQueue, $webServerConfig, $stopSignal)

    $logDirectory = Join-Path $global:PSWebServer.Project_Root.Path "PsWebHost_Data/Logs"
    if (-not (Test-Path $logDirectory)) {
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    }
    $logFile = Join-Path $logDirectory "log.tsv"

    while (-not $stopSignal.Value) {
        $logEntries = [System.Collections.Generic.List[string]]::new()
        while ($logQueue.TryDequeue([ref]'logEntry')) {
            $logEntries.Add($logEntry)
        }

        if ($logEntries.Count -gt 0) {
            Add-Content -Path $logFile -Value $logEntries
        }
        Start-Sleep -Milliseconds 500
    }
}
#>

$loggingPowerShell = [powershell]::Create().AddScript($loggingScriptBlock).AddParameters(@{
    logQueue = $global:PSWebHostLogQueue
    webServerConfig = $Global:PSWebServer
    stopSignal = $global:StopLogging
})
$global:LoggingPS = $loggingPowerShell
$global:PSWebServer.LoggingJob = $loggingPowerShell.BeginInvoke()
Write-Verbose "Started background logging job." -Verbose
# --- End Logging Setup ---

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