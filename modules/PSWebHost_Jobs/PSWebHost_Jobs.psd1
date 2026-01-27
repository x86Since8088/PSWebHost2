@{
    RootModule = 'PSWebHost_Jobs.psm1'
    ModuleVersion = '2.0.0'
    GUID = 'f2a8c9e1-4d3b-4f7a-9c2e-6b8d3f5a1c7e'
    Author = 'PSWebHost Team'
    Description = 'Unified job management system for PSWebHost - handles job discovery, scheduling, and execution'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Initialize-PSWebHostJobSystem',
        'Get-PSWebHostJobCatalog',
        'Get-PSWebHostJobDefinition',
        'Start-PSWebHostJob',
        'Stop-PSWebHostJob',
        'Restart-PSWebHostJob',
        'Get-PSWebHostJobOutput',
        'Get-PSWebHostJobStatus',
        'Get-PSWebHostRunningJobs',
        'Process-PSWebHostJobCommandQueue',
        'Test-PSWebHostJobPermission'
    )
    PrivateData = @{
        PSData = @{
            Tags = @('PSWebHost', 'Jobs', 'Scheduling', 'TaskManagement')
        }
    }
}
