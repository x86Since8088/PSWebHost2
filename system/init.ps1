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

# Add modules folder to PSModulePath
$modulesFolderPath = Join-Path $Global:PSWebServer.Project_Root.Path "modules"
if (-not ($Env:PSModulePath -split ';' -contains $modulesFolderPath)) {
    $Env:PSModulePath = "$modulesFolderPath;$($Env:PSModulePath)"
    Write-Verbose "Added '$modulesFolderPath' to PSModulePath." -Verbose
}

# --- Thread-Safe Logging Setup ---
$global:PSWebHostLogQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$global:PSHostUIQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$global:StopLogging = $false

$loggingScriptBlock = {
    param($logQueue, $webServerConfig, $stopSignal)

    $logDirectory = Join-Path $webServerConfig.Project_Root.Path "PsWebHost_Data/Logs"
    if (-not (Test-Path $logDirectory)) {
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    }
    $logFile = Join-Path $logDirectory "log.tsv"

    while (-not $stopSignal.Value) {
        $logEntries = [System.Collections.Generic.List[string]]::new()
        while ($logQueue.TryDequeue([ref]$logEntry)) {
            $logEntries.Add($logEntry)
        }

        if ($logEntries.Count -gt 0) {
            Add-Content -Path $logFile -Value $logEntries
        }
        Start-Sleep -Milliseconds 500
    }
}

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

try {
    Import-Module PSSQLite 
}
catch {
    Write-Error -Message "Error importing PSSQLite module: $($_.Exception.Message)"
}
if ($Loadvariables.IsPresent) {return}

# Validate installation, dependencies, and database schema
& (Join-Path $PSScriptRoot 'validateInstall.ps1')

# Register roles from config if they don't exist
if ($Global:PSWebServer.Config.roles) {
    $configRoles = $Global:PSWebServer.Config.roles
    $dbRoles = Get-PSWebHostRole -ListAll
    foreach ($role in $configRoles) {
        if ($role -notin $dbRoles) {
            Write-Verbose "Registering role '$role' from config." -Verbose
            New-PSWebHostRole -RoleName $role
        }
    }
}