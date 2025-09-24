@{
    ModuleVersion = '0.0.1'
    GUID = 'd2b0e6d8-f89d-4d6a-b6a1-2b0d9c3e05d5'
    Author = 'Edward Skarke III'
    CompanyName = 'Self'
    Copyright = '(c) 2025 Edward Skarke III. All rights reserved.'
    Description = 'Functions for interacting with the SQLite database for PsWebHost.'
    FunctionsToExport = @(
        'Add-UserToGroup',
        'Get-CardSettings',
        'Get-LastLoginAttempt',
        'Get-LoginSession',
        'Get-PSWebGroup',
        'Get-PSWebGroups',
        'Get-PSWebRoles',
        'Get-PSWebSQLiteData',
        'Get-UserProvider',
        'Initialize-PSWebHostDatabase',
        'Invoke-PSWebSQLiteNonQuery',
        'New-PSWebSQLiteData',
        'New-PSWebSQLiteDataByID',
        'New-PSWebSQLiteTable',
        'Set-CardSession',
        'Set-CardSettings',
        'Set-LastLoginAttempt',
        'Set-LoginSession',
        'Set-RoleForPrincipal',
        'Set-UserProvider'
    )
    RootModule = 'PSWebHost_Database.psm1'
    RequiredModules = @()
}