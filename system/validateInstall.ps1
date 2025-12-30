[cmdletbinding()]
param (
    [switch]$ShowVariables,
    [switch]$Upgrade # New parameter
)
begin{
    Write-Verbose -Message 'Initializing variables.' -Verbose
    $ScriptFolder             = Split-Path $MyInvocation.MyCommand.Definition

    # Detect OS and set platform-specific variables
    $IsWindowsOS = $IsWindows -or ($PSVersionTable.PSVersion.Major -lt 6) -or ($env:OS -eq 'Windows_NT')
    $IsLinuxOS = $IsLinux -or ($PSVersionTable.Platform -eq 'Unix' -and -not $IsMacOS)
    $IsMacOSPlatform = $IsMacOS

    $PathSeparator = if ($IsWindowsOS) { ';' } else { ':' }

    Write-Verbose "Detected OS: Windows=$IsWindowsOS, Linux=$IsLinuxOS, macOS=$IsMacOSPlatform" -Verbose

    # Add project modules folder to PSModulePath if not already present
    $projectRoot = Split-Path -Parent $ScriptFolder
    $modulesFolderPath = Join-Path $projectRoot "modules"
    if (-not ($Env:PSModulePath -split $PathSeparator -contains $modulesFolderPath)) {
        $Env:PSModulePath = "$modulesFolderPath$PathSeparator$($Env:PSModulePath)"
        Write-Verbose "Added '$modulesFolderPath' to PSModulePath." -Verbose
    }

    try {
        Import-Module PackageManagement
    }
    catch {
        Install-Module PackageManagement
        Import-Module PackageManagement
    }
    try {
        Import-Module PackageManagement
    }
    catch {
        try{
            Install-Module powershell-yaml -Force -AllowClobber 
        }
        catch {
            Install-Module powershell-yaml -Force -AllowClobber -Scope CurrentUser
        }
        Import-Module powershell-yaml
    }

    # Windows-specific: Check winget for SQLite
    if ($IsWindowsOS) {
        $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetCmd) {
            $WingetList = winget list
            if (-not ($WingetList -match 'SQLite.SQLite')) {
                Write-Verbose "SQLite not found in winget list. Installing..." -Verbose
                winget install SQLite.SQLite --accept-package-agreements --accept-source-agreements --silent
            }
        } else {
            Write-Verbose "Winget not available on this system." -Verbose
        }
    }

    $Packages = Get-Package -ErrorAction SilentlyContinue
    if (-not ('LogError' -in $Packages.Name)) {install-package LogError -Force}
    if (-not ('LogError' -in $Packages.Name)) {install-package LogError -Force}

    <#

    Write-Verbose -Message 'Validating required modules.'
    # Store the content of Requiredmodules.json for dumping
    $RequiredModulesJsonContent = Get-Content -Path "$ScriptFolder\Requiredmodules.json" | ConvertFrom-Json

    $RequiredModulesJsonContent |
        ForEach-Object{
            $ModuleRequirement = $_
            [string]$ModuleRequirementVersion = $ModuleRequirement.Version
            if ('' -eq $ModuleRequirementVersion) {$ModuleRequirementVersion = '*'}
            $module = (Get-Module -Name $ModuleRequirement.Name -ListAvailable | 
                Sort-Object -Property Version -Descending | 
                Select-Object -First 1)
            if($null -eq $module){
                Write-Error -Message "Required module not found: $($ModuleRequirement.Name). Please install it."
            }
            else{
                [string]$ModuleVersion = $module.Version.ToString()
                if ('' -eq $ModuleVersion) {$ModuleVersion = '0.0.0.0'}
                $foundVersion = [System.Version]($ModuleVersion)
                if ($ModuleRequirementVersion -ne '*' -and $foundVersion -lt [System.Version]$ModuleRequirementVersion) {
                    Write-Error -Message "Required module $($ModuleRequirement.Name) found (version $($foundVersion)), but requires version $($ModuleRequirement.Version) or higher. Please update it."
                } else {
                    Write-Verbose "Module found: $($module.Name) version $($foundVersion)"
                }
            }
        }
    Write-Verbose -Message 'Validating required modules - complete.' -Verbose
    #>

    Write-Verbose -Message 'Validating third-party modules...' -Verbose
    $thirdPartyValidatorScript = Join-Path $ScriptFolder "Validate3rdPartyModules.ps1"
    if (Test-Path $thirdPartyValidatorScript) {
        & $thirdPartyValidatorScript
    } else {
        Write-Warning "Third-party module validator script not found at $thirdPartyValidatorScript."
    }
    Write-Verbose -Message 'Validating third-party modules - complete.' -Verbose

    Write-Verbose -Message 'Validating SQLite installation.' -Verbose
    # Check if sqlite3 command is available
    # Prefer non-throwing checks to find sqlite3
    $__err = $null
    $sqliteCmd = Get-Command sqlite3 -ErrorAction SilentlyContinue -ErrorVariable __err
    if ($sqliteCmd) {
        $sqlite3Path = $sqliteCmd.Path
        Write-Verbose "SQLite found at: $sqlite3Path" -Verbose
    } else {
        Write-Warning "SQLite (sqlite3 command) not found. Attempting to install..."

        if ($IsWindowsOS) {
            # Windows: Use Winget
            $__err = $null
            $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue -ErrorVariable __err
            if ($wingetCmd) {
                Write-Verbose "Winget found." -Verbose

                $wingetCommand = "winget install --id SQLite.SQLite --accept-package-agreements --accept-source-agreements --silent"
                if ($Upgrade) {
                    $wingetCommand = "winget upgrade --id SQLite.SQLite --accept-package-agreements --accept-source-agreements --silent"
                    Write-Verbose "Attempting to upgrade SQLite via Winget." -Verbose
                } else {
                    Write-Verbose "Attempting to install SQLite via Winget (skipping upgrade unless -Upgrade switch is provided)." -Verbose
                }

                $wingetResult = Invoke-Expression $wingetCommand
                if ($LASTEXITCODE -eq 0) {
                    Write-Verbose "SQLite operation completed successfully via Winget." -Verbose
                } else {
                    Write-Error "Failed to install/upgrade SQLite via Winget. Winget exit code: $LASTEXITCODE. Output: $($wingetResult | Out-String)"
                    Write-Warning "Please install SQLite manually or run this script with administrative privileges if Winget requires them."
                }
            } else {
                Write-Error "Winget not found or failed to execute. Please install SQLite manually."
            }
        } elseif ($IsLinuxOS) {
            # Linux: Detect and use appropriate package manager
            Write-Verbose "Detecting Linux package manager..." -Verbose

            $packageManagers = @(
                @{ Name = 'apt-get'; CheckCmd = 'dpkg'; Package = 'sqlite3'; InstallCmd = 'sudo apt-get update && sudo apt-get install -y sqlite3' }
                @{ Name = 'apt'; CheckCmd = 'dpkg'; Package = 'sqlite3'; InstallCmd = 'sudo apt update && sudo apt install -y sqlite3' }
                @{ Name = 'dnf'; CheckCmd = 'rpm'; Package = 'sqlite'; InstallCmd = 'sudo dnf install -y sqlite' }
                @{ Name = 'yum'; CheckCmd = 'rpm'; Package = 'sqlite'; InstallCmd = 'sudo yum install -y sqlite' }
                @{ Name = 'pacman'; CheckCmd = 'pacman'; Package = 'sqlite'; InstallCmd = 'sudo pacman -S --noconfirm sqlite' }
                @{ Name = 'zypper'; CheckCmd = 'rpm'; Package = 'sqlite3'; InstallCmd = 'sudo zypper install -y sqlite3' }
            )

            $installedPkgMgr = $null
            foreach ($pm in $packageManagers) {
                $pmCmd = Get-Command $pm.Name -ErrorAction SilentlyContinue
                if ($pmCmd) {
                    $installedPkgMgr = $pm
                    Write-Verbose "Found package manager: $($pm.Name)" -Verbose
                    break
                }
            }

            if ($installedPkgMgr) {
                Write-Verbose "Installing SQLite using $($installedPkgMgr.Name)..." -Verbose
                Write-Verbose "Command: $($installedPkgMgr.InstallCmd)" -Verbose

                try {
                    $installResult = Invoke-Expression $installedPkgMgr.InstallCmd 2>&1
                    if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
                        Write-Verbose "SQLite installed successfully via $($installedPkgMgr.Name)." -Verbose
                    } else {
                        Write-Error "Failed to install SQLite via $($installedPkgMgr.Name). Exit code: $LASTEXITCODE. Output: $($installResult | Out-String)"
                    }
                } catch {
                    Write-Error "Error installing SQLite: $($_.Exception.Message)"
                    Write-Warning "Please install SQLite manually using your distribution's package manager."
                }
            } else {
                Write-Error "Could not detect a supported package manager (apt, dnf, yum, pacman, zypper)."
                Write-Warning "Please install SQLite manually: 'sudo <your-package-manager> install sqlite3'"
            }
        } elseif ($IsMacOSPlatform) {
            # macOS: Use Homebrew if available
            $brewCmd = Get-Command brew -ErrorAction SilentlyContinue
            if ($brewCmd) {
                Write-Verbose "Installing SQLite using Homebrew..." -Verbose
                try {
                    $brewResult = brew install sqlite 2>&1
                    if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
                        Write-Verbose "SQLite installed successfully via Homebrew." -Verbose
                    } else {
                        Write-Error "Failed to install SQLite via Homebrew. Exit code: $LASTEXITCODE"
                    }
                } catch {
                    Write-Error "Error installing SQLite: $($_.Exception.Message)"
                }
            } else {
                Write-Warning "Homebrew not found. Please install SQLite manually or install Homebrew first."
            }
        } else {
            Write-Error "Unsupported operating system. Please install SQLite manually."
        }
    }
    Write-Verbose -Message 'Validating SQLite installation - complete.' -Verbose
}
end {
    Write-Verbose "Validating database schema..."
    try {
        $validatorScript = Join-Path $PSScriptRoot "db/sqlite/validatetables.ps1"
        if (Test-Path $validatorScript) {
            $dbFile = Join-Path $projectRoot "PsWebHost_Data/pswebhost.db"
            $configFile = Join-Path $projectRoot "system/db/sqlite/sqliteconfig.json"
            & $validatorScript -DatabaseFile $dbFile -ConfigFile $configFile
        } else {
            Write-Error "Database validation script not found at '$validatorScript'."
        }
    } catch {
        Write-Error "An error occurred during database schema validation: $($_.Exception.Message)"
    }

    if ($ShowVariables.IsPresent) {
        $variablesToDump = @{
            ScriptFolder = $ScriptFolder
            ProjectRoot = $projectRoot
            ModulesFolderPath = $modulesFolderPath
            RequiredModules = $RequiredModulesJsonContent
            # Add any other relevant variables here
        }
        $variablesToDump | ConvertTo-Json -Depth 10 # Use a sufficient depth
    }
}