@{
    # Module manifest for PSDockerManager
    RootModule = 'PSDockerManager.psm1'
    ModuleVersion = '1.0.0'
    GUID = '8f3e4a2b-1c5d-4e6f-9a7b-3c8d5e2f1a4b'
    Author = 'PSWebHost Docker Manager'
    Description = 'Docker CLI wrapper functions for container management'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Test-DockerAvailability',
        'Get-DockerContainers',
        'Start-DockerContainer',
        'Stop-DockerContainer',
        'Restart-DockerContainer',
        'Remove-DockerContainer',
        'Get-DockerContainerLogs',
        'Test-DockerContainerId'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
