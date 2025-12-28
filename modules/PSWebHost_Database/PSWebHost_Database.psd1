@{
    ModuleVersion = '0.0.1'
    GUID = 'd2b0e6d8-f89d-4d6a-b6a1-2b0d9c3e05d5'
    Author = 'Edward Skarke III'
    CompanyName = 'Self'
    Copyright = '(c) 2025 Edward Skarke III. All rights reserved.'
    Description = 'Functions for interacting with the SQLite database for PsWebHost.'
    FunctionsToExport = @(
        'Get-PSWebSQLiteData',
        'Invoke-PSWebSQLiteNonQuery',
        'New-PSWebSQLiteData',
        'Sanitize-SqlQueryString',
        'Invoke-TestToken',
        'Get-PSWebUser',
        'Set-PSWebUser',
        'Set-PSWebHostRole'
    )
    RootModule = 'PSWebHost_Database.psm1'
    RequiredModules = @()
}