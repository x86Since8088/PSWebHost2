# Log_Tail.ps1
# Monitors log files and outputs new lines as PSCustomObjects

[CmdletBinding(DefaultParameterSetName='Path')]
param(
    [Parameter(ParameterSetName='Path', Position=0)]
    [string[]]$Path,

    [Parameter(ParameterSetName='SelectFiles')]
    [switch]$SelectWithGridView,

    [Parameter(ParameterSetName='ManageJobs', Mandatory=$true)]
    [string]$Name,

    [Parameter(ParameterSetName='ManageJobs')]
    [switch]$Receive,

    [Parameter(ParameterSetName='ManageJobs')]
    [switch]$Stop,

    [Parameter(ParameterSetName='Path')]
    [Parameter(ParameterSetName='SelectFiles')]
    [int]$Seconds = 0,

    [Parameter(ParameterSetName='Path')]
    [Parameter(ParameterSetName='SelectFiles')]
    [switch]$AsJob
)

$ErrorActionPreference = 'Stop'
$MyTag = '[Log_Tail.ps1]'

# Load WebHost environment if not already loaded
if ($null -eq $Global:PSWebServer) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
    . (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null
} else {
    $ProjectRoot = $Global:PSWebServer.Project_Root.Path
}

# ========================================
# Job Management Functions
# ========================================

function Get-LogTailJobs {
    param([string]$Pattern = '*')

    $jobPattern = "Log_Tail: $Pattern"
    $jobs = Get-Job -Name $jobPattern -ErrorAction SilentlyContinue

    if ($jobs) {
        return $jobs | Select-Object Id, Name, State, HasMoreData,
            @{N='Location';E={$_.Location}},
            @{N='Command';E={$_.Command}},
            @{N='StartTime';E={$_.PSBeginTime}},
            @{N='EndTime';E={$_.PSEndTime}}
    }
    return $null
}

function Stop-LogTailJob {
    param([string]$Pattern)

    $jobPattern = "Log_Tail: $Pattern"
    $jobs = Get-Job -Name $jobPattern -ErrorAction SilentlyContinue

    if ($jobs) {
        foreach ($job in $jobs) {
            Write-Verbose "$MyTag Stopping and removing job: $($job.Name)"
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
        Write-Host "Stopped and removed $($jobs.Count) job(s)" -ForegroundColor Green
    } else {
        Write-Warning "No jobs found matching pattern: $jobPattern"
    }
}

function Receive-LogTailJob {
    param([string]$Pattern)

    $jobPattern = "Log_Tail: $Pattern"
    $jobs = Get-Job -Name $jobPattern -ErrorAction SilentlyContinue

    if ($jobs) {
        foreach ($job in $jobs) {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Write-Host "Job: $($job.Name) (State: $($job.State))" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan

            $output = Receive-Job -Job $job -Keep
            if ($output) {
                $output | Format-Table -AutoSize
            } else {
                Write-Host "(No output yet)" -ForegroundColor Gray
            }
        }
    } else {
        Write-Warning "No jobs found matching pattern: $jobPattern"
    }
}

# ========================================
# Job Management Mode
# ========================================

if ($PSCmdlet.ParameterSetName -eq 'ManageJobs') {
    if ($Stop) {
        Stop-LogTailJob -Pattern $Name
    } elseif ($Receive) {
        Receive-LogTailJob -Pattern $Name
    } else {
        # Just list jobs
        $jobs = Get-LogTailJobs -Pattern $Name
        if ($jobs) {
            $jobs | Format-Table -AutoSize
        } else {
            Write-Warning "No jobs found matching pattern: Log_Tail: $Name"
        }
    }
    return
}

# ========================================
# File Selection Mode
# ========================================

# ========================================
# File Discovery and Path Processing
# ========================================

# Helper function to find log files
function Get-LogFiles {
    $searchPaths = @(
        (Join-Path $ProjectRoot "PsWebHost_Data\Logs"),
        (Join-Path $ProjectRoot "tests"),
        (Join-Path $ProjectRoot "PsWebHost_Data")
    )

    $logFiles = @()
    foreach ($searchPath in $searchPaths) {
        if (Test-Path $searchPath) {
            $logFiles += Get-ChildItem -Path $searchPath -Recurse -Include *.log, *.csv, *.tsv, *.txt -File -ErrorAction SilentlyContinue
        }
    }
    return $logFiles
}

if ($SelectWithGridView) {
    # Find log files in testing/data folders
    $logFiles = Get-LogFiles

    if (-not $logFiles) {
        throw "No log files found in search paths"
    }

    # Present selection grid
    $selectedFiles = $logFiles | Select-Object FullName, Name, Length, LastWriteTime |
        Out-GridView -Title "Select log files to tail (Ctrl+Click for multiple)" -OutputMode Multiple

    if (-not $selectedFiles) {
        Write-Warning "No files selected"
        return
    }

    $Path = $selectedFiles.FullName
}

# If no path specified, tail all found log files
if (-not $Path) {
    Write-Verbose "$MyTag No path specified, discovering all log files..."
    $logFiles = Get-LogFiles

    if (-not $logFiles) {
        throw "No log files found in search paths. Use -Path to specify files or -SelectWithGridView to choose."
    }

    $Path = $logFiles.FullName
    Write-Host "No path specified. Tailing all $($Path.Count) discovered log files:" -ForegroundColor Cyan
    $Path | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
}

# Process and clean up paths
$processedPaths = @()
foreach ($p in $Path) {
    # Trim quotes and whitespace
    $p = $p -replace '^[\s''"]+|[\s''"]+$'

    # Replace bare asterisk with project root wildcard
    $p = $p -replace '^\*$', (Join-Path $ProjectRoot '*')

    # Expand wildcards if present
    if ($p -match '[\*\?]') {
        $expanded = Get-ChildItem -Path $p -Include *.log, *.csv, *.tsv, *.txt -File -ErrorAction SilentlyContinue
        if ($expanded) {
            $processedPaths += $expanded.FullName
        } else {
            Write-Warning "No files found matching pattern: $p"
        }
    } else {
        $processedPaths += $p
    }
}

# Replace original Path with processed paths
$Path = $processedPaths

if (-not $Path -or $Path.Count -eq 0) {
    throw "No valid files to tail after path processing"
}

# ========================================
# Tail Implementation Script Block
# ========================================

$tailScriptBlock = {
    param(
        [string]$FilePath,
        [int]$MaxSeconds
    )

    $startTime = Get-Date
    $lineNumber = 0

    # Detect encoding
    try {
        $bytes = [System.IO.File]::ReadAllBytes($FilePath) | Select-Object -First 4
        $encoding = if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            [System.Text.Encoding]::UTF8
        } elseif ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
            [System.Text.Encoding]::Unicode
        } elseif ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
            [System.Text.Encoding]::BigEndianUnicode
        } else {
            [System.Text.Encoding]::Default
        }
        $encodingName = $encoding.EncodingName
    } catch {
        $encoding = [System.Text.Encoding]::UTF8
        $encodingName = "UTF-8 (assumed)"
    }

    # Open file for reading with FileShare.ReadWrite (allows writing while we read)
    $fileStream = New-Object System.IO.FileStream(
        $FilePath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )

    try {
        # Seek to end of file to only show new lines
        [void]$fileStream.Seek(0, [System.IO.SeekOrigin]::End)
        $reader = New-Object System.IO.StreamReader($fileStream, $encoding)

        Write-Verbose "Tailing file: $FilePath (Encoding: $encodingName)"

        while ($true) {
            # Check timeout
            if ($MaxSeconds -gt 0) {
                $elapsed = (Get-Date) - $startTime
                if ($elapsed.TotalSeconds -ge $MaxSeconds) {
                    Write-Verbose "Timeout reached ($MaxSeconds seconds). Stopping tail."
                    break
                }
            }

            # Read new lines
            $line = $reader.ReadLine()

            if ($null -ne $line) {
                $lineNumber++

                # Output as PSCustomObject
                [PSCustomObject]@{
                    Path = $FilePath
                    Encoding = $encodingName
                    Date = Get-Date
                    LineNumber = $lineNumber
                    Line = $line
                }
            } else {
                # No new data, wait a bit
                Start-Sleep -Milliseconds 100
            }
        }
    }
    finally {
        if ($reader) { $reader.Close() }
        if ($fileStream) { $fileStream.Close() }
    }
}

# ========================================
# Start Tail Jobs
# ========================================

$startedJobs = @()

foreach ($file in $Path) {
    # Resolve to full path
    if (-not [System.IO.Path]::IsPathRooted($file)) {
        $file = Join-Path $PWD $file
    }

    if (-not (Test-Path $file)) {
        Write-Warning "File not found: $file"
        continue
    }

    $resolvedPath = (Resolve-Path $file).Path
    $jobName = "Log_Tail: $resolvedPath"

    # Check for existing job and stop it
    $existingJob = Get-Job -Name $jobName -ErrorAction SilentlyContinue
    if ($existingJob) {
        Write-Verbose "$MyTag Stopping existing job for file: $resolvedPath"
        Stop-Job -Job $existingJob -ErrorAction SilentlyContinue
        Remove-Job -Job $existingJob -Force -ErrorAction SilentlyContinue
    }

    if ($AsJob) {
        # Start as background job
        Write-Verbose "$MyTag Starting tail job for: $resolvedPath"
        $job = Start-Job -Name $jobName -ScriptBlock $tailScriptBlock -ArgumentList $resolvedPath, $Seconds
        $startedJobs += $job
    } else {
        # Run inline (blocking)
        Write-Host "Tailing file: $resolvedPath (Press Ctrl+C to stop)" -ForegroundColor Cyan
        & $tailScriptBlock -FilePath $resolvedPath -MaxSeconds $Seconds
    }
}

# ========================================
# Return Job Details
# ========================================

if ($AsJob -and $startedJobs) {
    Write-Host "`nStarted $($startedJobs.Count) tail job(s):" -ForegroundColor Green
    $startedJobs | Select-Object Id, Name, State | Format-Table -AutoSize

    # If -Seconds was specified, wait for jobs to complete, then receive and remove
    if ($Seconds -gt 0) {
        Write-Host "`nWaiting for jobs to complete (${Seconds}s timeout)..." -ForegroundColor Yellow

        # Wait for all jobs to complete or timeout
        $waitSeconds = $Seconds + 2  # Add 2 seconds buffer
        Wait-Job -Job $startedJobs -Timeout $waitSeconds | Out-Null

        Write-Host "`nReceiving job output:" -ForegroundColor Cyan
        foreach ($job in $startedJobs) {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Write-Host "Job: $($job.Name) (State: $($job.State))" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan

            $output = Receive-Job -Job $job
            if ($output) {
                $output | Format-Table -AutoSize
            } else {
                Write-Host "(No output)" -ForegroundColor Gray
            }
        }

        Write-Host "`nRemoving completed jobs..." -ForegroundColor Yellow
        foreach ($job in $startedJobs) {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
        Write-Host "Jobs cleaned up successfully" -ForegroundColor Green

    } else {
        # No timeout specified, jobs will run indefinitely
        Write-Host "`nManage jobs with:" -ForegroundColor Cyan
        Write-Host "  List:    .\system\utility\Log_Tail.ps1 -Name '*' (or specific pattern)" -ForegroundColor Gray
        Write-Host "  Receive: .\system\utility\Log_Tail.ps1 -Name '*' -Receive" -ForegroundColor Gray
        Write-Host "  Stop:    .\system\utility\Log_Tail.ps1 -Name '*' -Stop" -ForegroundColor Gray

        return $startedJobs
    }
}
