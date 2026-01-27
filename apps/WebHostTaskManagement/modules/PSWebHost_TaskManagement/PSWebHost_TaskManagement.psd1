@{
    # Module manifest for PSWebHost_TaskManagement
    ModuleVersion = '1.0.0'
    GUID = 'f8a9b7c6-d5e4-3f2a-1b0c-9d8e7f6a5b4c'
    Author = 'PSWebHost'
    CompanyName = 'PSWebHost'
    Copyright = '(c) 2026 PSWebHost. All rights reserved.'
    Description = 'Job Command Queue Module - Provides file-based command queue for API endpoints (running in runspaces) to communicate with main_loop.ps1 (running in main process)'

    # Module file
    RootModule = 'PSWebHost_TaskManagement.psm1'

    # Minimum PowerShell version
    PowerShellVersion = '7.0'

    # Functions to export - only public functions
    FunctionsToExport = @(
        'Submit-JobCommand',
        'Get-JobCommandStatus',
        'Get-JobStatus'
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
            Tags = @('JobManagement', 'TaskManagement', 'CommandQueue', 'PSWebHost')
            ProjectUri = ''
            LicenseUri = ''
            ReleaseNotes = @'
v1.0.0 - Initial Release
- Submit-JobCommand: Submit job commands to queue for main_loop.ps1 processing
- Get-JobCommandStatus: Check status of submitted commands
- Get-JobStatus: Get status of running/completed jobs
- Internal helper: Get-JobCommandQueuePath for queue directory management
'@
        }
    }
}
