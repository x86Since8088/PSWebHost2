#Requires -Version 7

<#
.SYNOPSIS
    Remote PowerShell execution endpoint
.DESCRIPTION
    Executes PowerShell code within the server context, optionally in a background job
    with access to server variables.
#>

param(
    [hashtable]$Body,
    [hashtable]$Query,
    [switch]$Test,
    [string[]]$Roles = @()
)

$MyTag = '[CLI]'

# Test mode setup
if ($Test) {
    $projectRoot = Split-Path (Split-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent) -Parent

    if (-not $Global:PSWebServer) {
        $Global:PSWebServer = @{
            Project_Root = @{ Path = $projectRoot }
        }
    }

    # Auto-include 'authenticated' and 'debug' roles for testing
    if ('authenticated' -notin $Roles) {
        $Roles = @('authenticated', 'debug') + $Roles
    }

    # Mock body for testing
    if (-not $Body) {
        $Body = @{
            script = 'Get-Date; $PSVersionTable.PSVersion'
        }
    }

    Write-Host "$MyTag [Test Mode] Executing CLI command" -ForegroundColor Yellow
}

try {
    # Validate script parameter
    if (-not $Body.script) {
        return @{
            status = 'error'
            message = 'Missing required parameter: script'
            timestamp = (Get-Date).ToString('o')
        }
    }

    $scriptBlock = $Body.script
    $timeout = if ($Body.timeout) { [int]$Body.timeout } else { 30 }
    $inRunspace = if ($Body.ContainsKey('inRunspace')) { [bool]$Body.inRunspace } else { $false }
    $usingVars = if ($Body.using) { $Body.using -split ',' | ForEach-Object { $_.Trim() } } else { $null }

    # Build variable mapping for job
    $variables = @{}

    if ($usingVars) {
        # Include only specified variables
        foreach ($varName in $usingVars) {
            $cleanName = $varName -replace '^(global:|script:)', ''

            # Try global scope first
            if (Get-Variable -Name $cleanName -Scope Global -ErrorAction SilentlyContinue) {
                $variables["global:$cleanName"] = Get-Variable -Name $cleanName -Scope Global -ValueOnly
            }
            # Try script scope
            elseif (Get-Variable -Name $cleanName -Scope Script -ErrorAction SilentlyContinue) {
                $variables["script:$cleanName"] = Get-Variable -Name $cleanName -Scope Script -ValueOnly
            }
        }
    } else {
        # Include all global and script scope variables (default)
        Get-Variable -Scope Global | ForEach-Object {
            $variables["global:$($_.Name)"] = $_.Value
        }

        Get-Variable -Scope Script | ForEach-Object {
            if ($_.Name -notin $variables.Keys) {
                $variables["script:$($_.Name)"] = $_.Value
            }
        }
    }

    if ($inRunspace) {
        # Execute directly in current runspace (DANGEROUS - can block)
        Write-Verbose "$MyTag Executing in current runspace (may block if input requested)"

        try {
            # Restore variables to current scope
            foreach ($key in $variables.Keys) {
                if ($key -match '^global:(.+)$') {
                    Set-Variable -Name $matches[1] -Value $variables[$key] -Scope Global -Force
                } elseif ($key -match '^script:(.+)$') {
                    Set-Variable -Name $matches[1] -Value $variables[$key] -Scope Script -Force
                }
            }

            $result = Invoke-Expression $scriptBlock 2>&1
            $success = $?

            return @{
                status = if ($success) { 'success' } else { 'error' }
                output = $result | Out-String
                executionMode = 'runspace'
                timestamp = (Get-Date).ToString('o')
            }
        } catch {
            return @{
                status = 'error'
                message = $_.Exception.Message
                stackTrace = $_.ScriptStackTrace
                executionMode = 'runspace'
                timestamp = (Get-Date).ToString('o')
            }
        }
    } else {
        # Execute in background job (SAFE - won't block)
        Write-Verbose "$MyTag Executing in background job (timeout: ${timeout}s)"

        $job = Start-Job -ScriptBlock {
            param($ScriptText, $Variables)

            # Restore all passed variables
            foreach ($key in $Variables.Keys) {
                if ($key -match '^global:(.+)$') {
                    Set-Variable -Name $matches[1] -Value $Variables[$key] -Scope Global -Force
                } elseif ($key -match '^script:(.+)$') {
                    Set-Variable -Name $matches[1] -Value $Variables[$key] -Scope Script -Force
                }
            }

            # Execute the script
            try {
                Invoke-Expression $ScriptText 2>&1
            } catch {
                Write-Error $_.Exception.Message
                throw
            }
        } -ArgumentList $scriptBlock, $variables

        # Wait for job with timeout
        $completed = Wait-Job -Job $job -Timeout $timeout

        if ($completed) {
            $output = Receive-Job -Job $job 2>&1
            $jobState = $job.State

            Remove-Job -Job $job -Force

            return @{
                status = if ($jobState -eq 'Completed') { 'success' } else { 'error' }
                output = $output | Out-String
                executionMode = 'job'
                jobState = $jobState
                timestamp = (Get-Date).ToString('o')
            }
        } else {
            # Timeout occurred
            Stop-Job -Job $job
            $partialOutput = Receive-Job -Job $job 2>&1
            Remove-Job -Job $job -Force

            return @{
                status = 'timeout'
                message = "Execution exceeded timeout of ${timeout} seconds"
                partialOutput = $partialOutput | Out-String
                executionMode = 'job'
                timestamp = (Get-Date).ToString('o')
            }
        }
    }

} catch {
    return @{
        status = 'error'
        message = $_.Exception.Message
        stackTrace = $_.ScriptStackTrace
        timestamp = (Get-Date).ToString('o')
    }
}
