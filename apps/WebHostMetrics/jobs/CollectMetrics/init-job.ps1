#Requires -Version 7

<#
.SYNOPSIS
    Initialization script for System Metrics Collection

.DESCRIPTION
    This script runs before job.json is parsed
    Use it to:
    - Validate environment
    - Set default variables
    - Perform pre-execution checks

.PARAMETER Variables
    Hashtable of variables that will be used for template substitution
#>

[CmdletBinding()]
param(
    [hashtable]$Variables = @{}
)

$MyTag = '[WebHostMetrics:Job:CollectMetrics:Init]'

try {
    Write-Verbose "$MyTag Running initialization..."

    # Set default interval to 30 seconds if not provided
    if (-not $Variables.ContainsKey('Interval')) {
        $Variables['Interval'] = '30'
        Write-Verbose "$MyTag Set default Interval: 30 seconds"
    }

    # Validate interval is a number
    $intervalValue = 0
    if (-not [int]::TryParse($Variables['Interval'], [ref]$intervalValue)) {
        throw "Interval must be a valid integer, got: $($Variables['Interval'])"
    }

    # Validate interval is reasonable (5-3600 seconds)
    if ($intervalValue -lt 5 -or $intervalValue -gt 3600) {
        throw "Interval must be between 5 and 3600 seconds, got: $intervalValue"
    }

    Write-Verbose "$MyTag Initialization complete (Interval: $intervalValue seconds)"
}
catch {
    Write-Error "$MyTag Initialization failed: $_"
    throw
}
