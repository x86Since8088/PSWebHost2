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
    $env:PSModulePath = $moduleDownloadDir + ";" + $env:PSModulePath
}

# --- Bootstrap YAML module ---
if (-not (Get-Module -ListAvailable -Name 'powershell-yaml')) {
    Write-Verbose "'powershell-yaml' module not found. Attempting to install..."
    $__err = $null
    Install-Module -Name 'powershell-yaml' -Repository PSGallery -Force -Scope CurrentUser -ErrorAction SilentlyContinue -ErrorVariable __err
    if ($__err) {
        Write-Error "Failed to install 'powershell-yaml'. This script cannot continue without it. Error: $__err"
        return
    } else {
        Write-Verbose "Successfully installed 'powershell-yaml'."
    }
}

# Read and parse the config file
$modulesToValidate = Get-Content -Path $configFile | ConvertFrom-Yaml

function FixVersionLength {
    param($version)
    ForEach ($versionItem in $version) {
        [version](($versionItem.tostring() + ".0.0.0.0" -split '\.'|Select-Object -First 4) -join '.')
    }
}

function Test-VersionInSpec {
    param(
        [version]$Version,
        [version[]]$RequiredVersion,
        [version]$VersionMIN,
        [version]$VersionMAX
    )

    if (
        ($RequiredVersion -and ($Version -in $RequiredVersion)) -or
        (
            (($VersionMIN -and ($Version -ge $VersionMIN)) -and
            ($VersionMAX -and ($Version -le $VersionMAX))) -or

            (!$VersionMIN -and
            ($VersionMAX -and ($Version -le $VersionMAX))) -or

            (($VersionMIN -and ($Version -ge $VersionMIN)) -and
            !$VersionMAX)
        )
    ) {
        return $true
    }
    return $false
}

# Disable module folders that are not in the specification.
foreach ($moduleSpec in $modulesToValidate) {
    $ModuleFolders = Join-Path $moduleDownloadDir $moduleSpec.Name
    # Get Version folders that are out of spec
    $moduleName = $moduleSpec.Name
    $repository = $moduleSpec.Repository
    [version[]]$requiredVersion = $moduleSpec.Version|Where-Object{$null -ne $_}|ForEach-Object{FixVersionLength -version $_}
    [version]$VersionMIN = FixVersionLength -version $moduleSpec.VersionMIN
    [version]$VersionMAX = FixVersionLength -version $moduleSpec.VersionMAX
    if (!$requiredVersion -and !$VersionMIN -and !$VersionMAX) {
        [version]$VersionMIN = '0.0.0.0'
    }

    # Check if module folder exists before iterating version folders
    if (Test-Path $ModuleFolders) {
        foreach ($ModuleFolder in (Get-ChildItem $ModuleFolders -ErrorAction SilentlyContinue)){
        foreach($Versionfolder in (Get-ChildItem $ModuleFolder.FullName|Where-Object{$_.Name -match '^[\d\.]+(|\.disabled)$'})) {
            [version]$version = FixVersionLength -version ($Versionfolder.Name -replace '\.disabled$')
            $ModulePath = join-path $moduleDownloadDir $ModuleFolder.Name
            $ModulePath = Join-Path $ModulePath $Versionfolder.Name
            $Disable = $false
            Write-Verbose "Validating module: $moduleName version $version..."

            if (Test-VersionInSpec -Version $version -RequiredVersion $requiredVersion -VersionMIN $VersionMIN -VersionMAX $VersionMAX) {
                Write-Verbose "	Module '$moduleName' is allowed to use version '$version' in versions '$($requiredVersion -join ', ')' VersionMin '$VersionMIN' VersionMax '$VersionMAX'."
            }
            ELSE {
                Write-Warning "	Verion $version is not inside of the Module Specification:`n`t`t$(($moduleSpec|ConvertTo-Yaml).trim(@("`r","`n")) -split "\r*\n" -join "`n`t`t")"
                $Disable = $true
            }
            if ($Disable -and $Versionfolder.name -notmatch '\.disabled$') {
                Write-Warning "	Disabling '$($Versionfolder.FullName)'."
                try {
                    Remove-Module $ModuleFolder.Name -Force -ErrorAction SilentlyContinue
                }
                catch {
                    Write-Verbose "	Module was not loaded, proceeding with rename."
                }

                # Retry rename with backoff if file is locked
                $renamed = $false
                for ($i = 0; $i -lt 3; $i++) {
                    try {
                        Rename-Item $Versionfolder.FullName ($Versionfolder.Name + '.disabled') -ErrorAction Stop
                        $renamed = $true
                        break
                    }
                    catch {
                        if ($i -lt 2) {
                            Write-Verbose "	Rename failed (attempt $($i+1)/3), retrying in 1 second..."
                            Start-Sleep -Seconds 1
                        }
                        else {
                            Write-Error "	Failed to disable module after 3 attempts: $($_.Exception.Message)"
                        }
                    }
                }
            }
            elseif (!$Disable -and $Versionfolder.name -match '\.disabled$') {
                if (test-path ($Versionfolder.FullName -replace '\.disabled$')){
                    Remove-Item -Recurse -Path $Versionfolder.FullName -Force
                }
                else {
                    Write-Warning "	Enabling previously disabled module '$($Versionfolder.FullName)'."
                    Rename-Item $Versionfolder.FullName ($Versionfolder.name -replace '\.disabled$')
                    Import-Module ($Versionfolder.FullName -replace '\.disabled$')
                }
            }
        }
        }
    } else {
        Write-Verbose "Module folder not found: $ModuleFolders. Will check if download is needed."
    }

    try {Remove-Module -Name $moduleName -Force -ErrorAction Ignore}
    catch {}

    # Primary: Check local ModuleDownload directory first
    $installedModule = Get-Module -Name $moduleName -ListAvailable |
        Where-Object{$_.Path -like "$moduleDownloadDir*"} |
        Sort-Object -Property Version -Descending

    # Secondary: Check for loaded module commands
    if (!$installedModule) {
        $moduleCommand = Get-Command -Module $moduleName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($moduleCommand) {
            $installedModule = $moduleCommand.Module
        }
    }

    # Tertiary: Fallback to system-wide modules
    if (!$installedModule) {
        $installedModule = Get-Module -Name $moduleName -ListAvailable -All
    }
    $needsDownload = $false
    if (-not $installedModule) {
        Write-Warning "	Module '$moduleName' not found. Scheduling for download."
        $needsDownload = $true
    } else {
        # If multiple versions are somehow present, take the highest one
        $installedVersion = FixVersionLength -version ($installedModule | Sort-Object -Property Version -Descending | Select-Object -First 1).Version
        $installedVersions = ($installedModule | Sort-Object -Property Version -Descending).Version | ForEach-Object{FixVersionLength -version $_}
        $InstalledVersionsInRange = $installedVersions | Where-Object{$_.Version -le $VersionMAX -and ($_.Version -ge $VersionMIN)}
        $InstalledVersionsOutOfRange = $installedVersions | Where-Object{$_.Version -gt $VersionMAX -or ($_.Version -lt $VersionMIN)}
        
        if (Test-VersionInSpec -Version $installedVersion -RequiredVersion $requiredVersion -VersionMIN $VersionMIN -VersionMAX $VersionMAX) {
            Write-Verbose "	Module '$moduleName' is allowed to use version $installedVersion in versions RequiredVersion '$($requiredVersion -join ', ')' VersionMin '$VersionMIN' VersionMax '$VersionMAX'."
        }
        else {
            Write-Warning "	Module '$moduleName' version mismatch. Found $($InstalledVersion), require '$($requiredVersion -join ', ')'. Scheduling for download."
            $needsDownload = $true
        }
    }

    if ($needsDownload) {
        $HighestRequiredVersion = $requiredVersion |Where-Object{$null -ne $_} | Sort-Object -Descending | Select-Object -First 1
        Write-Verbose "	Downloading '$moduleName' version '$($requiredVersion -join ', ')' from repository '$repository'..."
            $saveParams = @{
                Name = $moduleName
                Repository = $repository
                Path = $moduleDownloadDir
                Force = $true
                AcceptLicense = $true
            }
            if ($HighestRequiredVersion) {
                $saveParams.RequiredVersion = $HighestRequiredVersion
            }
            else {
                if ($VersionMIN) {
                    $saveParams.MinimumVersion = $VersionMIN
                }
                if ($VersionMAX) {
                    $saveParams.MaximumVersion = $VersionMAX
                }
            }

            $__err = $null
            Save-Module @saveParams -ErrorAction SilentlyContinue -ErrorVariable __err
            if ($__err) {
                $errMsg = $__err[0].ToString()
                if ($errMsg -match "A parameter cannot be found that matches parameter name 'AcceptLicense'") {
                    $saveParams.Remove('AcceptLicense')
                    $__err = $null
                    Save-Module @saveParams -ErrorAction SilentlyContinue -ErrorVariable __err
                    if ($__err) {
                        Write-Error "	Failed to download module '$moduleName' after retry. Error: $__err"
                    }
                } else {
                    Write-Error "	Failed to download module '$moduleName'. Error: $errMsg"
                    if ($moduleSpec.URL) {
                        Write-Warning "	Attempting direct download from $($moduleSpec.URL)..."
                        # Add logic for direct download and extraction here if needed
                    }
                }
            } else {
                Write-Verbose "	Successfully downloaded '$moduleName'."
            }
    } else {
        Write-Verbose "	Module '$moduleName' is already up to date."
    }
}

Write-Verbose "Third-party module validation complete."