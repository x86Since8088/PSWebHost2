@{
    # Module manifest for FileExplorerHelper
    ModuleVersion = '1.0.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'PSWebHost'
    CompanyName = 'PSWebHost'
    Copyright = '(c) 2026 PSWebHost. All rights reserved.'
    Description = 'File Explorer Helper Module - Provides reusable functions for File Explorer API endpoints'

    # Module file
    RootModule = 'FileExplorerHelper.psm1'

    # Minimum PowerShell version
    PowerShellVersion = '7.0'

    # Functions to export
    FunctionsToExport = @(
        'New-WebHostFileExplorerResponse',
        'Send-WebHostFileExplorerResponse',
        'Test-WebHostFileExplorerSession',
        'Resolve-WebHostFileExplorerPath',
        'Get-WebHostFileExplorerTree',
        'Get-WebHostFileExplorerMimeType',
        'Get-WebHostFileExplorerCategory',
        'Get-WebHostFileExplorerQueryParams',
        'Send-WebHostFileExplorerError',
        'Get-WebHostFileExplorerTrashPath',
        'Save-WebHostFileExplorerUndoData',
        'Get-WebHostFileExplorerUserInfo',
        'Test-WebHostFileExplorerRemoteVolume',
        'Get-WebHostFileExplorerRemoteTrashPath',
        'Write-WebHostFileExplorerTrashMetadata',
        'Move-WebHostFileExplorerToTrash'
    )

    # Cmdlets to export (none)
    CmdletsToExport = @()

    # Variables to export (none)
    VariablesToExport = @()

    # Aliases to export (none)
    AliasesToExport = @()

    # Private data
    PrivateData = @{
        PSData = @{
            Tags = @('PSWebHost', 'FileExplorer', 'WebAPI')
            ProjectUri = ''
            LicenseUri = ''
            ReleaseNotes = 'Initial release - converted from dot-sourced script to proper module'
        }
    }
}
