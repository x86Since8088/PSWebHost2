@{
    ModuleVersion = '0.0.1'
    GUID = 'd2b0e6d8-f89d-4d6a-b6a1-2b0d9c3e05d5'
    Author = 'Edward Skarke III'
    CompanyName = 'Self'
    Copyright = '(c) 2025 Edward Skarke III. All rights reserved.'
    Description = 'Functions for interacting with the SQLite database for PsWebHost.'
    FunctionsToExport = @(
        'Add-PSWebAuthProvider',
        'Add-UserToGroup',
        'ConvertFrom-CompressedBase64',
        'Get-CardSettings',
        'Get-LastLoginAttempt',
        'Get-LoginSession',
        'Get-PSWebAuthProvider',
        'Get-PSWebGroup',
        'Get-PSWebGroups',
        'Get-PSWebRoles',
        'Get-PSWebSQLiteData',
        'Get-UserData',
        'Get-UserProvider',
        'Initialize-PSWebHostDatabase',
        'Invoke-PSWebSQLiteNonQuery',
        'New-PSWebSQLiteData',
        'New-PSWebSQLiteDataByID',
        'New-PSWebSQLiteTable',
        'Remove-PSWebAuthProvider',
        'Remove-RoleForPrincipal',
        'Remove-UserFromGroup',
        'Set-CardSession',
        'Set-CardSettings',
        'Set-LastLoginAttempt',
        'Set-LoginSession',
        'Set-PSWebAuthProvider',
        'Set-RoleForPrincipal',
        'Set-UserData',
        'Set-UserProvider',
        'Invoke-TestToken'
    )
    RootModule = 'PSWebHost_Database.psm1'
    RequiredModules = @()
}