[cmdletbinding()]
param (
    [switch]$ShowVariables,
    [switch]$Upgrade # New parameter
)
begin{
    Write-Verbose -Message 'Initializing variables.' -Verbose
    $ScriptFolder             = Split-Path $MyInvocation.MyCommand.Definition

    # Add project modules folder to PSModulePath if not already present
    $projectRoot = Split-Path -Parent $ScriptFolder
    $modulesFolderPath = Join-Path $projectRoot "modules"
    if (-not ($Env:PSModulePath -split ';' -contains $modulesFolderPath)) {
        $Env:PSModulePath = "$modulesFolderPath;$($Env:PSModulePath)"
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
        Import-Module powershell-yaml
    }
    catch {
        Install-Module powershell-yaml
        Import-Module powershell-yaml
    }

    $WingetList = winget list
    if (-not ($WingetList -match 'SQLite.SQLite')) {
        winget install SQLite.SQLite
    }

    $Packages = Get-Package
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
        Write-Warning "SQLite (sqlite3 command) not found. Attempting to install via Winget."

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