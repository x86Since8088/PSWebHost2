@{
    ModuleVersion = '0.0.1'
    GUID = 'f5d8e6d8-f89d-4d6a-b6a1-2b0d9c3e05d6' # New GUID
    Author = 'Edward Skarke III'
    CompanyName = 'Self'
    Copyright = '(c) 2025 Edward Skarke III. All rights reserved.'
    Description = 'Functions for formatting objects.'
    FunctionsToExport = @(
        'Convert-ObjectToYaml',
        'Inspect-Object',
        'Get-ObjectSafeWalk',
        'Test-Walkable'
    )
    RootModule = 'PSWebHost_Formatters.psm1'
    RequiredModules = @()
}