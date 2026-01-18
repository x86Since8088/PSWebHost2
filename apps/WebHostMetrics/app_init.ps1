#Requires -Version 7

# WebHostMetrics App Initialization Script
# This script runs during PSWebHost startup when the WebHostMetrics app is loaded

param(
    [hashtable]$PSWebServer,
    [string]$AppRoot
)

$MyTag = '[WebHostMetrics:Init]'

Write-Host "$MyTag Initializing metrics collection system..." -ForegroundColor Cyan

try {
    # Import metrics module from app's modules directory
    # The app framework has already added apps/WebHostMetrics/modules to PSModulePath
    Import-Module PSWebHost_Metrics -Force -ErrorAction Stop

    # Initialize metrics system with configuration
    Initialize-PSWebMetrics -SampleIntervalSeconds 5 -RetentionHours 24 -CsvRetentionDays 30

    # Clean up any existing metrics job to prevent duplicates
    if ($Global:PSWebServer.MetricsJob) {
        Stop-Job -Job $Global:PSWebServer.MetricsJob -ErrorAction SilentlyContinue
        Remove-Job -Job $Global:PSWebServer.MetricsJob -Force -ErrorAction SilentlyContinue
        $Global:PSWebServer.MetricsJob = $null
    }

    # Initialize execution state in synchronized hashtable
    if (-not $Global:PSWebServer.Metrics.JobState.ContainsKey('IsExecuting')) {
        $Global:PSWebServer.Metrics.JobState.IsExecuting = $false
    }
    if (-not $Global:PSWebServer.Metrics.JobState.ContainsKey('ShouldStop')) {
        $Global:PSWebServer.Metrics.JobState.ShouldStop = $false
    }

    # Create a PowerShell background job for metrics collection
    # This runs in a loop with 5-second intervals to collect system metrics
    $Global:PSWebServer.MetricsJob = Start-Job -Name "PSWebHost_MetricsCollection" -ScriptBlock {
        param($MetricsState, $ModulePath)

        # Import required module in the job context
        # Module is in apps/WebHostMetrics/modules which is already in PSModulePath
        Import-Module PSWebHost_Metrics -Force -ErrorAction Stop

        while (-not $MetricsState.ShouldStop) {
            try {
                # Prevent concurrent execution if previous run still active
                if ($MetricsState.IsExecuting) {
                    $elapsed = ((Get-Date) - $MetricsState.ExecutionStartTime).TotalSeconds
                    Write-Verbose "[MetricsJob] Skipped execution - previous run still in progress ($($elapsed)s elapsed)"

                    # If execution has been stuck for >30 seconds, force release the lock
                    if ($MetricsState.ExecutionStartTime -and $elapsed -gt 30) {
                        Write-Warning "[MetricsJob] Force-releasing stuck execution lock after 30 seconds"
                        $MetricsState.IsExecuting = $false
                    }
                } else {
                    # Set execution lock
                    $MetricsState.IsExecuting = $true
                    $MetricsState.ExecutionStartTime = Get-Date

                    # Execute metrics maintenance
                    Invoke-MetricJobMaintenance

                    # Release execution lock
                    $MetricsState.IsExecuting = $false
                }
            } catch {
                # Log error but don't crash the job
                Write-Warning "[MetricsJob] Error: $($_.Exception.Message)"
                if ($MetricsState.Errors.Count -lt 100) {
                    [void]$MetricsState.Errors.Add(@{
                        Timestamp = Get-Date
                        Message = $_.Exception.Message
                    })
                }
                # Always release execution lock on error
                $MetricsState.IsExecuting = $false
            }

            # Sleep for 5 seconds before next collection
            Start-Sleep -Seconds 5
        }
    } -ArgumentList $Global:PSWebServer.Metrics.JobState, $Global:PSWebServer.ModulesPath

    # Note: Initial metrics collection will happen asynchronously via job (within 5 seconds)
    # Removed synchronous initial collection to prevent startup hangs on slow performance counter queries

    # Store app configuration in PSWebServer
    if (-not $PSWebServer.ContainsKey('WebHostMetrics')) {
        $PSWebServer['WebHostMetrics'] = @{
            AppRoot = $AppRoot
            DataPath = Join-Path $Global:PSWebServer['DataRoot'] "metrics"
            Initialized = Get-Date
            JobName = "PSWebHost_MetricsCollection"
            SampleIntervalSeconds = 5
            RetentionHours = 24
            CsvRetentionDays = 30
        }
    }

    Write-Host "$MyTag Metrics collection system started (5-second intervals)" -ForegroundColor Green
    Write-Verbose "$MyTag Metrics data path: $($PSWebServer['WebHostMetrics'].DataPath)"
    Write-Verbose "$MyTag Background job: $($PSWebServer['WebHostMetrics'].JobName)"

} catch {
    Write-Warning "$MyTag Failed to initialize metrics system: $($_.Exception.Message)"
    Write-Warning "$MyTag Server will continue without metrics collection"
}
