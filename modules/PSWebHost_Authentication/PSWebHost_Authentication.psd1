@{
    ModuleVersion = '0.0.1'
    GUID = 'a1b2c3d4-e5f6-7890-1234-567890abcdef'
    Author = 'Edward Skarke III'
    CompanyName = 'Self'
    Copyright = '(c) 2025 Edward Skarke III. All rights reserved.'
    Description = 'Functions for handling authentication for PsWebHost.'
    FunctionsToExport = @(
        'Add-PSWebHostUserToGroup',
        'Add-PSWebHostUserToRole',
        'Get-AuthenticationMethod',
        'Get-AuthenticationMethodForm',
        'Get-PSWebHostUser',
        'Get-PSWebHostUsers',
        'Get-UserAuthenticationMethods',
        'Get-UserRoles',
        'Invoke-AuthenticationMethod',
        'New-PSWebHostGroup',
        'New-PSWebHostRole',
        'New-PSWebHostUser',
        'Protect-String',
        'PSWebLogon',
        'Remove-PSWebHostGroup',
        'Remove-PSWebHostRole',
        'Remove-PSWebHostUserFromGroup',
        'Remove-PSWebHostUserFromRole',
        'Test-IsValidEmailAddress',
        'Test-IsValidPassword',
        'Test-LoginLockout',
        'Test-StringForHighRiskUnicode',
        'Unprotect-String',
        'Register-PSWebHostUser'
    )
    RootModule = 'PSWebHost_Authentication.psm1'
    RequiredModules = @(
        'PSWebHost_Database'
    )
}