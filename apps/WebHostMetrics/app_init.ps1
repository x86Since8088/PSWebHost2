#Requires -Version 7

# WebHostMetrics App Initialization Script
# This script runs during PSWebHost startup when the WebHostMetrics app is loaded

param(
    [hashtable]$PSWebServer,
    [string]$AppRoot
)

$MyTag = '[WebHostMetrics:Init]'

Write-Host "$MyTag Initializing metrics system..." -ForegroundColor Cyan

try {
    # Import metrics module from app's modules directory
    # Use explicit path to ensure module is found even if PSModulePath isn't set yet
    $modulePath = Join-Path $AppRoot "modules\PSWebHost_Metrics\PSWebHost_Metrics.psm1"

    if (Test-Path $modulePath) {
        Import-Module $modulePath -DisableNameChecking -ErrorAction Stop
    } else {
        # Fallback: try loading from PSModulePath (if framework has set it up)
        Import-Module PSWebHost_Metrics -DisableNameChecking -ErrorAction Stop
    }

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

    # Get project root - handle different possible structures
    $projectRoot = if ($PSWebServer.Project_Root) {
        $PSWebServer.Project_Root.Path
    } elseif ($Global:PSWebServer.Project_Root) {
        $Global:PSWebServer.Project_Root.Path
    } else {
        # Fallback: calculate from AppRoot
        Split-Path (Split-Path $AppRoot -Parent) -Parent
    }

    # Create a PowerShell background job for metrics collection
    # This runs in a loop with 5-second intervals to collect system metrics
    $Global:PSWebServer.MetricsJob = Start-Job -Name "PSWebHost_MetricsCollection" -ScriptBlock {
        param($MetricsObject, $ProjectRoot, $AppRoot)

        # Initialize global PSWebServer in job scope if needed
        if (-not $Global:PSWebServer) {
            $Global:PSWebServer = @{}
        }
        if (-not $Global:PSWebServer.Project_Root) {
            $Global:PSWebServer.Project_Root = @{ Path = $ProjectRoot }
        }

        # Attach the synchronized Metrics object to the global scope
        $Global:PSWebServer.Metrics = $MetricsObject

        # Import required module in the job context
        # Calculate module path from AppRoot (more reliable than ProjectRoot)
        $modulePath = Join-Path $AppRoot "modules\PSWebHost_Metrics\PSWebHost_Metrics.psm1"

        if (Test-Path $modulePath) {
            Import-Module $modulePath -DisableNameChecking -ErrorAction Stop
        } else {
            # Fallback: try loading from PSModulePath (if available in job scope)
            Import-Module PSWebHost_Metrics -DisableNameChecking -ErrorAction Stop
        }

        # Mock Write-PSWebHostLog if not available in job scope
        if (-not (Get-Command Write-PSWebHostLog -ErrorAction SilentlyContinue)) {
            function Write-PSWebHostLog {
                param($Severity, $Category, $Message, $Data)
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Write-Host "[$timestamp] [$Severity] [$Category] $Message" -ForegroundColor $(
                    switch ($Severity) {
                        'Error' { 'Red' }
                        'Warning' { 'Yellow' }
                        'Info' { 'Cyan' }
                        default { 'Gray' }
                    }
                )
            }
        }

        $iterationCount = 0

        while (-not $MetricsObject.JobState.ShouldStop) {
            $iterationCount++
            try {
                # Prevent concurrent execution if previous run still active
                if ($MetricsObject.JobState.IsExecuting) {
                    $elapsed = ((Get-Date) - $MetricsObject.JobState.ExecutionStartTime).TotalSeconds
                    Write-Verbose "[MetricsJob] Skipped execution - previous run still in progress ($($elapsed)s elapsed)"

                    # If execution has been stuck for >30 seconds, force release the lock
                    if ($MetricsObject.JobState.ExecutionStartTime -and $elapsed -gt 30) {
                        Write-PSWebHostLog -Severity 'Warning' -Category 'Metrics' -Message "Force-releasing stuck execution lock after 30 seconds"
                        $MetricsObject.JobState.IsExecuting = $false
                    }
                } else {
                    # Set execution lock
                    $MetricsObject.JobState.IsExecuting = $true
                    $MetricsObject.JobState.ExecutionStartTime = Get-Date

                    # Execute metrics maintenance
                    Invoke-MetricJobMaintenance

                    # Release execution lock
                    $MetricsObject.JobState.IsExecuting = $false
                }
            } catch {
                # Log error using Write-PSWebHostLog
                Write-PSWebHostLog -Severity 'Error' -Category 'Metrics' -Message "Error in metrics collection job: $($_.Exception.Message)" -Data @{
                    Exception = $_.Exception.GetType().FullName
                    StackTrace = $_.ScriptStackTrace
                }

                if ($MetricsObject.JobState.Errors.Count -lt 100) {
                    [void]$MetricsObject.JobState.Errors.Add(@{
                        Timestamp = Get-Date
                        Message = $_.Exception.Message
                        StackTrace = $_.ScriptStackTrace
                    })
                }
                # Always release execution lock on error
                $MetricsObject.JobState.IsExecuting = $false
            }

            # Sleep for 5 seconds before next collection
            Start-Sleep -Seconds 5
        }
    } -ArgumentList $Global:PSWebServer.Metrics, $projectRoot, $AppRoot

    # Note: Initial metrics collection will happen asynchronously via job (within 5 seconds)
    # Removed synchronous initial collection to prevent startup hangs on slow performance counter queries

    # Store app configuration in PSWebServer
    if (-not $PSWebServer.ContainsKey('WebHostMetrics')) {
        # Calculate DataPath - handle different possible structures
        $dataRoot = if ($Global:PSWebServer.ContainsKey('DataRoot') -and $Global:PSWebServer['DataRoot']) {
            $Global:PSWebServer['DataRoot']
        } elseif ($PSWebServer.ContainsKey('DataRoot') -and $PSWebServer['DataRoot']) {
            $PSWebServer['DataRoot']
        } else {
            # Fallback: PsWebHost_Data in project root
            Join-Path $projectRoot "PsWebHost_Data"
        }

        $PSWebServer['WebHostMetrics'] = @{
            AppRoot = $AppRoot
            DataPath = Join-Path $dataRoot "metrics"
            Initialized = Get-Date
            JobName = "PSWebHost_MetricsCollection"
            SampleIntervalSeconds = 5
            RetentionHours = 24
            CsvRetentionDays = 30
        }
    }

    Write-Host "$MyTag Metrics collection started (5s intervals, job ID: $($Global:PSWebServer.MetricsJob.Id))" -ForegroundColor Green

} catch {
    Write-Warning "$MyTag Failed to initialize metrics system: $($_.Exception.Message)"
    Write-Warning "$MyTag Server will continue without metrics collection"
}
