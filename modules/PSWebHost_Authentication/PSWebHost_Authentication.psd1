@{
    ModuleVersion = '0.0.1'
    GUID = 'a1b2c3d4-e5f6-7890-1234-567890abcdef'
    Author = 'Edward Skarke III'
    CompanyName = 'Self'
    Copyright = '(c) 2025 Edward Skarke III. All rights reserved.'
    Description = 'Functions for handling authentication for PsWebHost.'
    FunctionsToExport = @(
        'Add-PSWebHostGroup',
        'Add-PSWebHostGroupMember',
        'Add-PSWebHostRole',
        'Add-PSWebHostRoleAssignment',
        'Get-AuthenticationMethod',
        'Get-AuthenticationMethodForm',
        'Get-CardSettings',
        'Get-LastLoginAttempt',
        'Get-LoginSession',
        'Get-PSWebHostRole',
        'Get-PSWebHostGroup',
        'Get-PSWebHostUser',
        'Get-PSWebHostUsers',
        'Get-UserAuthenticationMethods',
        'Invoke-AuthenticationMethod',
        'New-PSWebHostUser',
        'Protect-String',
        'PSWebLogon',
        'Register-PSWebHostUser',
        'Remove-LoginSession',
        'Remove-PSWebHostGroup',
        'Remove-PSWebHostGroupMember',
        'Remove-PSWebHostRole',
        'Remove-PSWebHostRoleAssignment',
        'Set-CardSession',
        'Set-CardSettings',
        'Set-LastLoginAttempt',
        'Set-LoginSession',
        'Test-IsValidEmailAddress',
        'Test-IsValidPassword',
        'Test-LoginLockout',
        'Test-StringForHighRiskUnicode',
        'Unprotect-String'
    )
    RootModule = 'PSWebHost_Authentication.psm1'
    RequiredModules = @(
        'PSWebHost_Database'
    )
}