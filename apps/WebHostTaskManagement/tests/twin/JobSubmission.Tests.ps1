#Requires -Version 7

<#
.SYNOPSIS
    Twin tests for PSWebHost Job Submission System

.DESCRIPTION
    Tests job submission, execution, and results retrieval in PSWebHost.
    Tests all three execution modes: MainLoop, Runspace, and BackgroundJob.
#>

BeforeAll {
    # Import required modules
    $projectRoot = Join-Path $PSScriptRoot "..\..\..\..\"
    $modulePath = Join-Path $projectRoot "modules\PSWebHost_JobExecution\PSWebHost_JobExecution.psd1"
    Import-Module $modulePath -Force

    # Setup global PSWebServer mock
    if (-not $global:PSWebServer) {
        $global:PSWebServer = @{
            DataPath = Join-Path $projectRoot "PsWebHost_Data"
            Project_Root = @{ Path = $projectRoot }
        }
    }

    # Setup test directories
    $script:testDataDir = Join-Path $global:PSWebServer.DataPath "apps\WebHostTaskManagement"
    $script:submissionDir = Join-Path $script:testDataDir "JobSubmission\test-user"
    $script:outputDir = Join-Path $script:testDataDir "JobOutput"
    $script:resultsDir = Join-Path $script:testDataDir "JobResults"

    foreach ($dir in @($script:submissionDir, $script:outputDir, $script:resultsDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }

    # Cleanup function
    $script:CleanupTestFiles = {
        param($JobID)
        $patterns = @(
            (Join-Path $script:submissionDir "*${JobID}*.json"),
            (Join-Path $script:outputDir "*${JobID}*.json"),
            (Join-Path $script:resultsDir "${JobID}.json")
        )
        foreach ($pattern in $patterns) {
            Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Remove-Item -Force
        }
    }
}

Describe "Job Submission System" {
    Context "Submit-PSWebHostJob" {
        It "Should submit a job successfully with debug role" {
            $result = Submit-PSWebHostJob `
                -UserID "test-user" `
                -SessionID "test-session" `
                -JobName "TestJob1" `
                -Command "Write-Output 'Hello World'" `
                -Description "Test job" `
                -ExecutionMode "MainLoop" `
                -Roles @('debug')

            $result.Success | Should -Be $true
            $result.JobID | Should -Not -BeNullOrEmpty
            $result.SubmissionFile | Should -Exist

            # Cleanup
            & $script:CleanupTestFiles -JobID $result.JobID
        }

        It "Should submit a job with runspace execution mode" {
            $result = Submit-PSWebHostJob `
                -UserID "test-user" `
                -SessionID "test-session" `
                -JobName "TestJob2" `
                -Command "Get-Date" `
                -Description "Test runspace job" `
                -ExecutionMode "Runspace" `
                -Roles @('task_manager')

            $result.Success | Should -Be $true
            $result.JobID | Should -Not -BeNullOrEmpty

            # Cleanup
            & $script:CleanupTestFiles -JobID $result.JobID
        }

        It "Should submit a job with background job execution mode" {
            $result = Submit-PSWebHostJob `
                -UserID "test-user" `
                -SessionID "test-session" `
                -JobName "TestJob3" `
                -Command "1 + 1" `
                -Description "Test background job" `
                -ExecutionMode "BackgroundJob" `
                -Roles @('system_admin')

            $result.Success | Should -Be $true
            $result.JobID | Should -Not -BeNullOrEmpty

            # Cleanup
            & $script:CleanupTestFiles -JobID $result.JobID
        }

        It "Should reject MainLoop execution without debug role" {
            {
                Submit-PSWebHostJob `
                    -UserID "test-user" `
                    -SessionID "test-session" `
                    -JobName "TestJob4" `
                    -Command "Write-Output 'Test'" `
                    -ExecutionMode "MainLoop" `
                    -Roles @('authenticated')
            } | Should -Throw -ExpectedMessage "*MainLoop execution mode requires 'debug' role*"
        }

        It "Should reject Runspace execution without elevated roles" {
            {
                Submit-PSWebHostJob `
                    -UserID "test-user" `
                    -SessionID "test-session" `
                    -JobName "TestJob5" `
                    -Command "Write-Output 'Test'" `
                    -ExecutionMode "Runspace" `
                    -Roles @('authenticated')
            } | Should -Throw -ExpectedMessage "*elevated roles*"
        }
    }

    Context "Job Execution - MainLoop Mode" {
        It "Should execute a simple command in main loop" {
            # Submit job
            $submission = Submit-PSWebHostJob `
                -UserID "test-user" `
                -SessionID "test-session" `
                -JobName "MainLoopTest1" `
                -Command "Write-Output 'Main Loop Test'" `
                -ExecutionMode "MainLoop" `
                -Roles @('debug')

            # Read submission file
            $submissionData = Get-Content -Path $submission.SubmissionFile -Raw | ConvertFrom-Json
            $submissionHash = @{}
            $submissionData.PSObject.Properties | ForEach-Object {
                $submissionHash[$_.Name] = $_.Value
            }

            # Execute job
            Invoke-PSWebHostJobInMainLoop -JobSubmission $submissionHash -ResultsDir $script:resultsDir

            # Verify result file was created
            $resultFile = Join-Path $script:resultsDir "$($submission.JobID).json"
            $resultFile | Should -Exist

            # Check result content
            $result = Get-Content -Path $resultFile -Raw | ConvertFrom-Json
            $result.JobID | Should -Be $submission.JobID
            $result.Success | Should -Be $true
            $result.Output | Should -Match "Main Loop Test"

            # Cleanup
            & $script:CleanupTestFiles -JobID $submission.JobID
        }

        It "Should capture errors in main loop execution" {
            $submission = Submit-PSWebHostJob `
                -UserID "test-user" `
                -SessionID "test-session" `
                -JobName "MainLoopError" `
                -Command "throw 'Intentional error'" `
                -ExecutionMode "MainLoop" `
                -Roles @('debug')

            $submissionData = Get-Content -Path $submission.SubmissionFile -Raw | ConvertFrom-Json
            $submissionHash = @{}
            $submissionData.PSObject.Properties | ForEach-Object {
                $submissionHash[$_.Name] = $_.Value
            }

            Invoke-PSWebHostJobInMainLoop -JobSubmission $submissionHash -ResultsDir $script:resultsDir

            $resultFile = Join-Path $script:resultsDir "$($submission.JobID).json"
            $result = Get-Content -Path $resultFile -Raw | ConvertFrom-Json

            $result.Success | Should -Be $false
            $result.Output | Should -Match "Intentional error"

            # Cleanup
            & $script:CleanupTestFiles -JobID $submission.JobID
        }

        It "Should record execution timing" {
            $submission = Submit-PSWebHostJob `
                -UserID "test-user" `
                -SessionID "test-session" `
                -JobName "TimingTest" `
                -Command "Start-Sleep -Milliseconds 100; Write-Output 'Done'" `
                -ExecutionMode "MainLoop" `
                -Roles @('debug')

            $submissionData = Get-Content -Path $submission.SubmissionFile -Raw | ConvertFrom-Json
            $submissionHash = @{}
            $submissionData.PSObject.Properties | ForEach-Object {
                $submissionHash[$_.Name] = $_.Value
            }

            Invoke-PSWebHostJobInMainLoop -JobSubmission $submissionHash -ResultsDir $script:resultsDir

            $resultFile = Join-Path $script:resultsDir "$($submission.JobID).json"
            $result = Get-Content -Path $resultFile -Raw | ConvertFrom-Json

            $result.Runtime | Should -BeGreaterThan 0.09
            $result.DateStarted | Should -Not -BeNullOrEmpty
            $result.DateCompleted | Should -Not -BeNullOrEmpty

            # Cleanup
            & $script:CleanupTestFiles -JobID $submission.JobID
        }
    }

    Context "Job Execution - Runspace Mode" {
        It "Should start a job in a dedicated runspace" {
            $submission = Submit-PSWebHostJob `
                -UserID "test-user" `
                -SessionID "test-session" `
                -JobName "RunspaceTest1" `
                -Command "Write-Output 'Runspace Test'" `
                -ExecutionMode "Runspace" `
                -Roles @('task_manager')

            $submissionData = Get-Content -Path $submission.SubmissionFile -Raw | ConvertFrom-Json
            $submissionHash = @{}
            $submissionData.PSObject.Properties | ForEach-Object {
                $submissionHash[$_.Name] = $_.Value
            }

            $result = Invoke-PSWebHostJobInRunspace -JobSubmission $submissionHash -ResultsDir $script:resultsDir

            $result.Success | Should -Be $true
            $result.RunspaceID | Should -Not -BeNullOrEmpty

            # Wait for runspace to complete (max 5 seconds)
            $timeout = 5
            $elapsed = 0
            $resultFile = Join-Path $script:resultsDir "$($submission.JobID).json"

            while (-not (Test-Path $resultFile) -and $elapsed -lt $timeout) {
                Start-Sleep -Milliseconds 500
                $elapsed += 0.5
            }

            # Verify result was created
            $resultFile | Should -Exist

            # Cleanup runspace
            if ($global:PSWebServer.Runspaces -and $global:PSWebServer.Runspaces.ContainsKey($result.RunspaceID)) {
                $rsInfo = $global:PSWebServer.Runspaces[$result.RunspaceID]
                if ($rsInfo.PowerShell) {
                    $rsInfo.PowerShell.Dispose()
                }
                if ($rsInfo.Runspace) {
                    $rsInfo.Runspace.Dispose()
                }
                $global:PSWebServer.Runspaces.Remove($result.RunspaceID)
            }

            # Cleanup
            & $script:CleanupTestFiles -JobID $submission.JobID
        }
    }

    Context "Job Execution - Background Job Mode" {
        It "Should start a job as PowerShell background job" {
            $submission = Submit-PSWebHostJob `
                -UserID "test-user" `
                -SessionID "test-session" `
                -JobName "BGJobTest1" `
                -Command "Write-Output 'Background Job Test'; 2 + 2" `
                -ExecutionMode "BackgroundJob" `
                -Roles @('system_admin')

            $submissionData = Get-Content -Path $submission.SubmissionFile -Raw | ConvertFrom-Json
            $submissionHash = @{}
            $submissionData.PSObject.Properties | ForEach-Object {
                $submissionHash[$_.Name] = $_.Value
            }

            $result = Invoke-PSWebHostJobAsBackgroundJob -JobSubmission $submissionHash -ResultsDir $script:resultsDir

            $result.Success | Should -Be $true
            $result.PSJobID | Should -BeGreaterThan 0

            # Wait for job to complete
            $job = Get-Job -Id $result.PSJobID
            $job | Wait-Job -Timeout 10 | Out-Null

            # Verify result file
            $resultFile = Join-Path $script:resultsDir "$($submission.JobID).json"
            $resultFile | Should -Exist

            # Cleanup job
            Remove-Job -Id $result.PSJobID -Force -ErrorAction SilentlyContinue

            # Cleanup
            & $script:CleanupTestFiles -JobID $submission.JobID
        }
    }

    Context "Job Results Management" {
        It "Should retrieve job results for a user" {
            # Submit and execute a test job
            $submission = Submit-PSWebHostJob `
                -UserID "test-user-results" `
                -SessionID "test-session" `
                -JobName "ResultsTest1" `
                -Command "Write-Output 'Results Test'" `
                -ExecutionMode "MainLoop" `
                -Roles @('debug')

            $submissionData = Get-Content -Path $submission.SubmissionFile -Raw | ConvertFrom-Json
            $submissionHash = @{}
            $submissionData.PSObject.Properties | ForEach-Object {
                $submissionHash[$_.Name] = $_.Value
            }

            Invoke-PSWebHostJobInMainLoop -JobSubmission $submissionHash -ResultsDir $script:resultsDir

            # Get results
            $results = Get-PSWebHostJobResults -UserID "test-user-results" -MaxResults 10

            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -BeGreaterThan 0
            $results[0].JobID | Should -Be $submission.JobID

            # Cleanup
            & $script:CleanupTestFiles -JobID $submission.JobID
        }

        It "Should delete a job result" {
            # Submit and execute a test job
            $submission = Submit-PSWebHostJob `
                -UserID "test-user-delete" `
                -SessionID "test-session" `
                -JobName "DeleteTest1" `
                -Command "Write-Output 'Delete Test'" `
                -ExecutionMode "MainLoop" `
                -Roles @('debug')

            $submissionData = Get-Content -Path $submission.SubmissionFile -Raw | ConvertFrom-Json
            $submissionHash = @{}
            $submissionData.PSObject.Properties | ForEach-Object {
                $submissionHash[$_.Name] = $_.Value
            }

            Invoke-PSWebHostJobInMainLoop -JobSubmission $submissionHash -ResultsDir $script:resultsDir

            # Verify result exists
            $resultFile = Join-Path $script:resultsDir "$($submission.JobID).json"
            $resultFile | Should -Exist

            # Delete result
            $deleted = Remove-PSWebHostJobResults -JobID $submission.JobID

            $deleted | Should -Be $true
            $resultFile | Should -Not -Exist

            # Cleanup remaining files
            & $script:CleanupTestFiles -JobID $submission.JobID
        }
    }

    Context "Process-PSWebHostJobSubmissions Integration" {
        It "Should process pending job submissions from file system" {
            # Submit multiple jobs
            $job1 = Submit-PSWebHostJob `
                -UserID "test-user-proc" `
                -SessionID "test-session" `
                -JobName "ProcTest1" `
                -Command "Write-Output 'Job 1'" `
                -ExecutionMode "MainLoop" `
                -Roles @('debug')

            $job2 = Submit-PSWebHostJob `
                -UserID "test-user-proc" `
                -SessionID "test-session" `
                -JobName "ProcTest2" `
                -Command "Write-Output 'Job 2'" `
                -ExecutionMode "MainLoop" `
                -Roles @('debug')

            # Process submissions
            Process-PSWebHostJobSubmissions

            # Verify results were created
            $result1File = Join-Path $script:resultsDir "$($job1.JobID).json"
            $result2File = Join-Path $script:resultsDir "$($job2.JobID).json"

            $result1File | Should -Exist
            $result2File | Should -Exist

            # Verify submission files were moved to output
            $job1.SubmissionFile | Should -Not -Exist
            $outputFile1 = Join-Path $script:outputDir (Split-Path $job1.SubmissionFile -Leaf)
            $outputFile1 | Should -Exist

            # Cleanup
            & $script:CleanupTestFiles -JobID $job1.JobID
            & $script:CleanupTestFiles -JobID $job2.JobID
        }
    }
}

AfterAll {
    # Cleanup any remaining test files
    Write-Host "Cleaning up test files..." -ForegroundColor Yellow

    $patterns = @(
        (Join-Path $script:submissionDir "*.json"),
        (Join-Path $script:outputDir "*.json"),
        (Join-Path $script:resultsDir "*.json")
    )

    foreach ($pattern in $patterns) {
        Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "test-user|TestJob|MainLoop|Runspace|BGJob|Results|Delete|Proc" } |
            Remove-Item -Force
    }

    Write-Host "Test cleanup complete" -ForegroundColor Green
}
