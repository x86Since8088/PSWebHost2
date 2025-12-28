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
    foreach ($ModuleFolder in $ModuleFolders){
        foreach($Versionfolder in (Get-ChildItem $ModuleFolder.FullName|Where-Object{$_.Name -match '^[\d\.]+(|\.disabled)$'})) {
            [version]$version = FixVersionLength -version ($Versionfolder.Name -replace '\.disabled$')
            $Disable = $false
            Write-Verbose "Validating module: $moduleName version $version..."
            if (
                ($requiredVersion -and ($Version -in $requiredVersion)) -or
                (
                    (($VersionMIN -and ($Version -ge $VersionMIN)) -and 
                    ($VersionMAX -and ($Version -le $VersionMAX))) -or

                    (!$VersionMIN -and
                    ($VersionMAX -and ($Version -le $VersionMAX))) -or

                    (($VersionMIN -and ($Version -ge $VersionMIN)) -and 
                    !$VersionMAX)
                )
            ){
                Write-Verbose "	Module '$moduleName' is allowed to use version '$version' in versions '$($requiredVersion -join ', ')' VersionMin '$VersionMIN' VersionMax '$VersionMAX'."
            }
            ELSE {
                Write-Warning "	Verion $version is not inside of the Module Specification:`n`t`t$(($moduleSpec|ConvertTo-Yaml).trim('
').split('
').join("`n`t`t"))"
                $Disable = $true
            }
            if ($Disable -and $Versionfolder.name -notmatch '\.disabled$') {
                Write-Warning "	Disabling '$(join-path $moduleDownloadDir ($ModuleFolder.Name)\\$($Versionfolder.Name))'."
                try {
                    Remove-Module $ModuleFolder.Name -Force
                }
                catch {
                    Write-Error -Message "	Module removal failed for $(join-path $moduleDownloadDir ($ModuleFolder.Name)\\$($Versionfolder.Name))."
                }
                Rename-Item $Versionfolder.FullName ($Versionfolder.Name + '.disabled')
            }
            elseif (!$Disable -and $Versionfolder.name -match '\.disabled$') {
                Write-Warning "	Enabling previously disabled module '$(join-path $moduleDownloadDir ($ModuleFolder.Name)\\$($Versionfolder.Name))'."
                Rename-Item $Versionfolder.FullName ($Versionfolder.Name -replace '\.disabled$')
                Import-Module ($Versionfolder.FullName -replace '\.disabled$')
            }
        }
    }

    try {Remove-Module -Name $moduleName -Force -ErrorAction Ignore}
    catch {}
    # This command is more likeley to favor detecting the local module copy
    $installedModule = (Get-Command -Module $moduleName|Select-Object -First 1).Module
    # Failback to a more traditional method that will also find
    if (!$installedModule) {
        $installedModule = Get-Module -Name $moduleName -ListAvailable|
            Where-Object{$_.Path -like "$moduleDownloadDir*"}
    }
    # Failback to detecting the system wide module.
    if (!$installedModule) {
        $installedModule = Get-Module -Name $moduleName -ListAvailable
    }
    $needsDownload = $false
    if (-not $installedModule) {
        Write-Warning "	Module '$moduleName' not found. Scheduling for download."
        $needsDownload = $true
    } else {
        # If multiple versions are somehow present, take the highest one
        $installedVersion = FixVersionLength -version ($installedModule | Sort-Object -Property Version -Descending | Select-Object -First 1).Version
        if (
            ($requiredVersion -and ($InstalledVersion -in $requiredVersion)) -or
            (
                (($VersionMIN -and ($InstalledVersion -ge $VersionMIN)) -and 
                ($VersionMAX -and ($InstalledVersion -le $VersionMAX))) -or

                (!$VersionMIN -and
                ($VersionMAX -and ($InstalledVersion -le $VersionMAX))) -or

                (($VersionMIN -and ($InstalledVersion -ge $VersionMIN)) -and 
                !$VersionMAX)
            )
        ) {
            Write-Verbose "	Module '$moduleName' is allowed to use version $version in versions RequiredVersion '$($requiredVersion -join ', ')' VersionMin '$VersionMIN' VersionMax '$VersionMAX'."
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