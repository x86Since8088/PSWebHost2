#Requires -Version 7

<#
.SYNOPSIS
    Initializes the WebHostDebugVariables app

.DESCRIPTION
    Sets up the debug variables browser with tree view capabilities
#>

$MyTag = '[WebHostDebugVariables:Init]'

try {
    Write-Host "$MyTag Initializing Debug Variables browser..." -ForegroundColor Cyan

    # No special initialization needed - all functionality is in API endpoints
    Write-Host "$MyTag Debug Variables browser initialized successfully" -ForegroundColor Green

} catch {
    Write-Warning "$MyTag Failed to initialize: $_"
}
