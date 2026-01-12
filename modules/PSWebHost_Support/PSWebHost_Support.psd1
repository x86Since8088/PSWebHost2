@{
    # Module properties
    ModuleVersion = '0.0.1'
    GUID = '1ab7181b-ecb7-4251-a857-87183428baae' # Generate a new GUID for your module
    Author = 'Edward Skarke III'
    CompanyName = 'Self'
    Copyright = '(c) 2025 Edward Skarke III. All rights reserved.'
    Description = 'Support functions for PsWebHost'

    # Files to export from this module
    FunctionsToExport = @(
        'Complete-PSWebHostEvent',
        'ConvertTo-CompressedBase64',
        'context_reponse',
        'Get-PSWebHostEvents',
        'Get-PSWebSessions',
        'Get-RequestBody',
        'New-PSWebHostResult',
        'Process-HttpRequest',
        'Read-PSWebHostLog',
        'Remove-PSWebSession',
        'Set-PSWebSession',
        'Start-PSWebHostEvent',
        'Sync-SessionStateToDatabase',
        'Validate-UserSession',
        'Write-PSWebHostLog'
    )

    # Root module file
    RootModule = 'PSWebHost_Support.psm1'

    # Required modules (if any)
    RequiredModules = @(
    )
}