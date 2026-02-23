@{
    # Module manifest for PSWebHost_MemoryAnalysis
    # Generated on 2026-02-01

    RootModule = 'PSWebHost_MemoryAnalysis.psm1'
    ModuleVersion = '1.0.0'
    GUID = '7a3c9e2d-4f8b-4c1a-9d6e-5b7a3f1c8e9d'
    Author = 'PSWebHost'
    CompanyName = 'PSWebHost'
    Copyright = '(c) 2026 PSWebHost. All rights reserved.'
    Description = 'Advanced memory analysis system for PSWebHost that provides real-time, streaming analysis of PowerShell object graphs with accurate memory consumption calculations.'

    PowerShellVersion = '7.0'

    # Functions to export from this module
    FunctionsToExport = @(
        'Get-MemoryConsumption',
        'Measure-ObjectGraph',
        'Get-TypeMemoryOverhead',
        'Get-ObjectEstimatedSize',
        'Get-AssemblyMemory',
        'Get-AssemblyMemorySummary',
        'Format-AssemblyMemoryReport'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # Private data to pass to the module
    PrivateData = @{
        PSData = @{
            Tags = @('Memory', 'Analysis', 'Diagnostics', 'PSWebHost')
            ProjectUri = ''
            ReleaseNotes = 'Initial release - Core memory analysis functionality'
        }
    }
}
