[cmdletbinding()]
param()

# --- Main Logic ---
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$configFile = Join-Path $PSScriptRoot "Validate3rdPartyModules.yaml"
$moduleDownloadDir = Join-Path $ProjectRoot "ModuleDownload"

# Create the download directory if it doesn't exist
if (-not (Test-Path $moduleDownloadDir)) {
    New-Item -Path $moduleDownloadDir -ItemType Directory | Out-Null
}

# Add the local module directory to the PSModulePath for this session
if (-not ($moduleDownloadDir -in ($env:PSModulePath -split ";"))) {
    $env:PSModulePath += ";" + $moduleDownloadDir
}

# --- Bootstrap YAML module ---
if (-not (Get-Module -ListAvailable -Name 'powershell-yaml')) {
    Write-Host "'powershell-yaml' module not found. Attempting to install..."
    try {
        Install-Module -Name 'powershell-yaml' -Repository PSGallery -Force -Scope CurrentUser -ErrorAction Stop
        Write-Host "Successfully installed 'powershell-yaml'."
    } catch {
        Write-Error "Failed to install 'powershell-yaml'. This script cannot continue without it. Please install it manually."
        return
    }
}

# Read and parse the config file
$modulesToValidate = Get-Content -Path $configFile | ConvertFrom-Yaml

foreach ($moduleSpec in $modulesToValidate) {
    $moduleName = $moduleSpec.Name
    $requiredVersion = $moduleSpec.Version
    $repository = $moduleSpec.Repository

    Write-Host "Validating module: $moduleName..."

    $installedModule = Get-Module -Name $moduleName -ListAvailable

    $needsDownload = $false
    if (-not $installedModule) {
        Write-Warning "Module '$moduleName' not found. Scheduling for download."
        $needsDownload = $true
    } else {
        # If multiple versions are somehow present, take the highest one
        $installedVersion = $installedModule | Sort-Object -Property Version -Descending | Select-Object -First 1
        if ($installedVersion.Version.ToString() -ne $requiredVersion) {
            Write-Warning "Module '$moduleName' version mismatch. Found $($installedVersion.Version), require $requiredVersion. Scheduling for download."
            $needsDownload = $true
        }
    }

    if ($needsDownload) {
        Write-Host "Downloading '$moduleName' version $requiredVersion from repository '$repository'..."
        try {
            $saveParams = @{
                Name = $moduleName
                RequiredVersion = $requiredVersion
                Repository = $repository
                Path = $moduleDownloadDir
                Force = $true
                AcceptLicense = $true
            }
            Save-Module @saveParams -ErrorAction Stop
            Write-Host "Successfully downloaded '$moduleName'."
        } catch {
            Write-Error "Failed to download module '$moduleName'. Error: $($_.Exception.Message)"
            if ($moduleSpec.URL) {
                Write-Warning "Attempting direct download from $($moduleSpec.URL)..."
                # Add logic for direct download and extraction here if needed
            }
        }
    } else {
        Write-Host "Module '$moduleName' is already up to date."
    }
}

Write-Host "Third-party module validation complete."
