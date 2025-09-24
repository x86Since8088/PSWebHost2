@{
    ModuleVersion = '0.0.1'
    GUID = 'a1b2c3d4-e5f6-7890-1234-567890abcdef'
    Author = 'Edward Skarke III'
    CompanyName = 'Self'
    Copyright = '(c) 2025 Edward Skarke III. All rights reserved.'
    Description = 'Functions for handling authentication for PsWebHost.'
    FunctionsToExport = @(
        'Get-AuthenticationMethod',
        'Get-AuthenticationMethodForm',
        'Get-PSWebHostUser',
        'Get-PSWebHostUsers',
        'Get-UserAuthenticationMethods',
        'Get-UserRoles',
        'Invoke-AuthenticationMethod',
        'New-PSWebHostUser',
        'New-PSWebUser',
        'Test-IsValidEmailAddress',
        'Test-IsValidPassword',
        'Test-LoginLockout',
        'PSWebLogon'
    )
    RootModule = 'PSWebHost_Authentication.psm1'
    RequiredModules = @(
        'PSWebHost_Database'
    )
}