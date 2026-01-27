@{
    # Module manifest for FileExplorerConfig
    ModuleVersion = '1.0.0'
    GUID = 'b9c8d7e6-f5a4-4321-9876-5e4d3c2b1a09'
    Author = 'PSWebHost'
    CompanyName = 'PSWebHost'
    Copyright = '(c) 2026 PSWebHost. All rights reserved.'
    Description = 'FileExplorer Configuration Module - Provides config-driven root management for FileExplorer with dynamic root discovery, role-based access, and path template resolution'

    # Module file
    RootModule = 'FileExplorerConfig.psm1'

    # Minimum PowerShell version
    PowerShellVersion = '7.0'

    # Functions to export - only public functions
    FunctionsToExport = @(
        'Get-WebHostFileExplorerConfigPath',
        'New-WebHostFileExplorerDefaultConfig',
        'Resolve-WebHostFileExplorerConfigPath',
        'Get-WebHostFileExplorerConfig',
        'Clear-WebHostFileExplorerConfigCache'
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
            Tags = @('FileExplorer', 'Configuration', 'RootManagement', 'PSWebHost')
            ProjectUri = ''
            LicenseUri = ''
            ReleaseNotes = @'
v1.0.0 - Initial Release
- Get-WebHostFileExplorerConfigPath: Returns path to roots.json configuration file
- New-WebHostFileExplorerDefaultConfig: Creates default configuration with standard roots
- Resolve-WebHostFileExplorerConfigPath: Resolves path templates with variable substitution
- Get-WebHostFileExplorerConfig: Loads configuration with 5-minute TTL caching
- Clear-WebHostFileExplorerConfigCache: Clears configuration cache for forced reload

Features:
- Config-driven root definitions (roots.json)
- Dynamic root discovery (buckets, User:others)
- Role-based access control
- Path template resolution ({UserID}, {Project_Root.Path}, etc.)
- 5-minute TTL caching for performance
- Automatic default config generation
'@
        }
    }
}
