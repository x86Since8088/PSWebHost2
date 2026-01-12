@{
    RootModule = 'PSWebHost_Metrics.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a8c3f1d2-5e7b-4c9a-b6d8-2f1e3a4b5c6d'
    Author = 'PSWebHost'
    Description = 'System metrics collection, aggregation, and persistence for PSWebHost'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Initialize-PSWebMetrics',
        'Stop-PSWebMetrics',
        'Get-SystemMetricsSnapshot',
        'Update-CurrentMetrics',
        'Add-MetricsSample',
        'Invoke-MetricsAggregation',
        'Write-MetricsToCsv',
        'Remove-OldMetricsCsvFiles',
        'Get-MetricsFromCsv',
        'Invoke-MetricJobMaintenance',
        'Get-CurrentMetrics',
        'Get-MetricsHistory',
        'Get-MetricsJobStatus',
        # New architecture functions
        'Get-OSPlatform',
        'Get-CPUTemperature',
        'Get-DiskIOMetrics',
        'Get-NetworkAdapterMetadata',
        'Write-MetricsToInterimCsv',
        'Move-CsvToSqlite',
        'Invoke-Metrics60sAggregation',
        'Invoke-MetricsCleanup'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('PSWebHost', 'Metrics', 'Monitoring', 'System')
        }
    }
}
