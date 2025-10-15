param(
    [Parameter(Mandatory=$true)]
    [System.IO.FileInfo[]]$Files
)

# analyze_functions.ps1 - Version 4.0
# - Merged user's custom logic with fine-tuning improvements.
# - Added a comprehensive ignore list for common cmdlets.
# - Preserved module-level skipping.
# - Removed live execution during analysis to clean up output.

# --- CONFIGURATION ---

# Add or remove cmdlet names here to control the verbosity of the output.
$CmdletsToIgnore = @(
    'Write-Host', 'Write-Output', 'Write-Warning', 'Write-Verbose', 'Write-Information', 'Write-Error',
    'Get-Date', 'Join-Path', 'Test-Path', 'Split-Path', 'Resolve-Path',
    'New-Object', 'New-Item',
    'Get-Item', 'Get-Content', 'Set-Content', 'Get-Command',
    'ConvertTo-Json', 'ConvertFrom-Json',
    'ConvertTo-SecureString', 'ConvertFrom-SecureString',
    'Select-Object', 'Where-Object', 'ForEach-Object', 'Sort-Object',
    'Out-String', 'Out-Null',
    'Get-Member', 'Set-Variable', 'Get-Variable',
    'Get-PSCallStack', 'Format-List', 'Import-Csv'
)

# Add module names to this list to skip reporting on any cmdlets they contain.
$SkipModules = @(
    'Microsoft.PowerShell.Utility',
    'Microsoft.PowerShell.Management'
)

# Use a regex to skip modules (e.g., all Microsoft modules).
$SkipModulesRegex = '^(Microsoft\.)'

# --- END CONFIGURATION ---

# Pre-load project modules to help `Get-Command` resolve project-specific functions.
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Get-ChildItem "$ProjectRoot\Modules" -Directory | ForEach-Object {
    Import-Module $_.FullName -DisableNameChecking -Force -ErrorAction Ignore
}
Get-ChildItem "$ProjectRoot\Modules" -Directory | ForEach-Object {
    Import-Module $_.FullName -DisableNameChecking -ErrorAction SilentlyContinue
}
. "$ProjectRoot\system\init.ps1" |Out-Null

if (-not $Files) {
    Write-Warning "The `$Files variable is not populated. Please populate it with file objects to analyze."
    return
}

function CheckScriptBlock {
    param(
        $Ast
    )
    $Commands = $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)|
        Where-Object{$_.GetCommandName}|
        Where-Object{$_.GetCommandName() -match '^\s*[a-z]'}
    $CommandOutputArr = @()

    foreach ($Command in $Commands) {
        $CommandName = $Command.GetCommandName()

        if (-not $CommandName -or ($CommandName.ToLower() -in $CmdletsToIgnore)) {
            continue
        }

        $CommandInfo = Get-Command $CommandName -ErrorAction SilentlyContinue
        if ($CommandInfo.CommandType -eq 'Alias'){$CommandInfo = Get-Command -Name $CommandInfo.ResolvedCommand}
        if ($CommandInfo) {
            if ($CommandInfo.Module.Name -in $SkipModules) { continue }
            if ($CommandInfo.Module.Name -match $SkipModulesRegex) { continue }
        }
        
        $CommandOutput = "    Calls: $($CommandName.TrimStart('\'))"
        
        $PositionalParameters = $null
        if ($CommandInfo) {
            $PositionalParameters = $CommandInfo.Parameters.Values | Where-Object { $_.Position -ge 0 } | Sort-Object Position
        }
        
        $CurrentPositionalIndex = 0
        
        $i = 1
        while ($i -lt $Command.CommandElements.Count) {
            $Element = $Command.CommandElements[$i]

            if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
                $ParamName = $Element.ParameterName
                if ($Element.Argument) {
                    $CommandOutput += "`n      - $ParamName`: $($Element.Argument.ToString())"
                    $i++
                } else {
                    $NextElementIndex = $i + 1
                    if ($NextElementIndex -lt $Command.CommandElements.Count -and $Command.CommandElements[$NextElementIndex] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                        $ArgumentValue = $Command.CommandElements[$NextElementIndex].ToString()
                        $CommandOutput += "`n      - $ParamName`: $ArgumentValue"
                        $i += 2
                    } else {
                        $CommandOutput += "`n      - $ParamName (switch)"
                        $i++
                    }
                }
            } else {
                $ArgumentValue = $Element.ToString()
                if ($PositionalParameters -and $CurrentPositionalIndex -lt $PositionalParameters.Count) {
                    $ParamName = $PositionalParameters[$CurrentPositionalIndex].Name
                    $CommandOutput += "`n      - $ParamName (positional): $ArgumentValue"
                    $CurrentPositionalIndex++
                } else {
                    $CommandOutput += "`n      - (positional): $ArgumentValue"
                }
                $i++
            }
        }
        $CommandOutputArr += $CommandOutput
    }
}

foreach ($File in $Files) {
    Write-Output "File: $($File.FullName -replace '^.*?\\PsWebHost\\','.')"
    
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
    $Functions = $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    Write-Output "  Body: $($Function.Name)($($ParamSignature))"
    CheckScriptBlock -Ast $Ast                    
    foreach ($Function in $Functions) {
        $ParamStrings = foreach($Param in $Function.Parameters){ $Param.ToString() }
        $ParamSignature = $ParamStrings -join ", "
        Write-Output "  Function: $($Function.Name)($($ParamSignature))"
        . CheckScriptBlock -Ast $Function.Body
        
        # Print sorted, unique output for the function
        $CommandOutputArr | Sort-Object -Unique
        if ($CommandOutputArr.Count -gt 0) {
            Write-Output ""
        }
    }
}
