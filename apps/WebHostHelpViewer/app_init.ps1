#Requires -Version 7

# WebHostHelpViewer App Initialization Script
# System-wide help file viewer with text/markdown rendering modes

param(
    [hashtable]$PSWebServer,
    [string]$AppRoot
)

$MyTag = '[WebHostHelpViewer:Init]'

Write-Host "$MyTag Initializing Help Viewer app..." -ForegroundColor Cyan

try {
    # Store app configuration in PSWebServer
    if (-not $PSWebServer.ContainsKey('WebHostHelpViewer')) {
        $PSWebServer['WebHostHelpViewer'] = @{
            AppRoot = $AppRoot
            Initialized = Get-Date
            Version = '1.0.0'
            SupportedPaths = @(
                'public/help',
                'docs',
                'apps/*/help',
                'apps/*/docs'
            )
            SupportedExtensions = @('.md', '.markdown', '.txt')
        }
    }

    Write-Host "$MyTag Help Viewer initialized successfully" -ForegroundColor Green

} catch {
    Write-Warning "$MyTag Failed to initialize Help Viewer: $($_.Exception.Message)"
}
