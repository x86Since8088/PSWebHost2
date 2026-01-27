@{
    RootModule = 'PSWebHost_JobExecution.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a7f3e8d9-4b2c-4f5a-9e7d-6c8b3a2f1e0d'
    Author = 'PSWebHost Team'
    Description = 'Job submission and execution system for PSWebHost'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Submit-PSWebHostJob'
        'Get-PSWebHostJobResults'
        'Remove-PSWebHostJobResults'
        'Process-PSWebHostJobSubmissions'
        'Invoke-PSWebHostJobInMainLoop'
        'Invoke-PSWebHostJobInRunspace'
        'Invoke-PSWebHostJobAsBackgroundJob'
    )
    PrivateData = @{
        PSData = @{
            Tags = @('PSWebHost', 'Jobs', 'TaskManagement')
        }
    }
}
