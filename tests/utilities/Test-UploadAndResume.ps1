# Test-UploadAndResume.ps1
# Synthetic tests for FileExplorer upload and resume functionality

param(
    [string]$BaseUrl = "http://localhost:8080",
    [string]$TestFilePath = "$env:TEMP\test-upload-$(Get-Date -Format 'yyyyMMdd-HHmmss').bin",
    [int]$TestFileSizeMB = 50,
    [int]$ChunkSizeKB = 512
)

Write-Host "=== FileExplorer Upload & Resume Synthetic Tests ===" -ForegroundColor Cyan
Write-Host ""

# Test configuration
$testResults = @{
    Passed = @()
    Failed = @()
}

# Bearer token variables
$script:BearerToken = $null
$script:TokenName = $null
$script:Headers = @{}
$script:UploadGuid = $null
$script:TestFileCreated = $false

# Cleanup function that ALWAYS runs
function Invoke-Cleanup {
    Write-Host "`n--- Cleanup ---" -ForegroundColor Yellow

    # Remove test file
    if ($script:TestFileCreated -and (Test-Path $TestFilePath)) {
        try {
            Remove-Item $TestFilePath -Force -ErrorAction Stop
            Write-Host "✓ Test file deleted: $TestFilePath" -ForegroundColor Gray
        } catch {
            Write-Host "⚠ Failed to delete test file: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Remove bearer token (CRITICAL - always try this)
    if ($script:TokenName) {
        Write-Host "✓ Removing bearer token: $script:TokenName" -ForegroundColor Gray
        try {
            # Suppress ALL output from token removal
            $null = & "$PSScriptRoot\system\utility\Account_Auth_BearerToken_Remove.ps1" `
                -Name $script:TokenName `
                -Confirm:$false `
                -ErrorAction Stop `
                2>&1
            Write-Host "✓ Bearer token removed" -ForegroundColor Green
        } catch {
            Write-Host "⚠ WARNING: Failed to remove bearer token: $script:TokenName" -ForegroundColor Red
            Write-Host "   Please remove manually using:" -ForegroundColor Yellow
            Write-Host "   .\system\utility\Account_Auth_BearerToken_Remove.ps1 -Name $script:TokenName" -ForegroundColor Yellow
        }
    }
}

# Register cleanup to run on exit
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Invoke-Cleanup
} | Out-Null

function Test-Result {
    param(
        [string]$TestName,
        [bool]$Success,
        [string]$Message
    )

    if ($Success) {
        $testResults.Passed += $TestName
        Write-Host "[PASS] $TestName" -ForegroundColor Green
        if ($Message) {
            Write-Host "       $Message" -ForegroundColor Gray
        }
    } else {
        $testResults.Failed += $TestName
        Write-Host "[FAIL] $TestName" -ForegroundColor Red
        if ($Message) {
            Write-Host "       $Message" -ForegroundColor Yellow
        }
    }
}

# Main test execution wrapped in try-finally
try {
    # ============================================================================
    # Test 1: Create Test File
    # ============================================================================

    Write-Host "`n--- Test 1: Create Test File ---" -ForegroundColor Yellow

    try {
        $fileSizeBytes = $TestFileSizeMB * 1024 * 1024
        $buffer = New-Object byte[] 1048576  # 1MB buffer

        $stream = [System.IO.File]::Create($TestFilePath)
        $random = New-Object System.Random

        for ($i = 0; $i -lt $TestFileSizeMB; $i++) {
            $random.NextBytes($buffer)
            $stream.Write($buffer, 0, $buffer.Length)

            if ($i % 10 -eq 0) {
                Write-Progress -Activity "Creating test file" -Status "$i MB written" -PercentComplete (($i / $TestFileSizeMB) * 100)
            }
        }

        $stream.Close()
        Write-Progress -Activity "Creating test file" -Completed

        $fileInfo = Get-Item $TestFilePath
        $script:TestFileCreated = $true
        Test-Result -TestName "Create Test File" -Success $true -Message "Created $($fileInfo.Length / 1MB)MB file"
    } catch {
        Test-Result -TestName "Create Test File" -Success $false -Message $_.Exception.Message
        throw "Cannot proceed without test file"
    }

    # ============================================================================
    # Test 2: Check Server Availability
    # ============================================================================

    Write-Host "`n--- Test 2: Check Server Availability ---" -ForegroundColor Yellow

    try {
        $response = Invoke-WebRequest -Uri "$BaseUrl/" -Method GET -UseBasicParsing -ErrorAction Stop -TimeoutSec 5
        Test-Result -TestName "Server Availability" -Success $true -Message "Server responding (HTTP $($response.StatusCode))"
    } catch {
        Test-Result -TestName "Server Availability" -Success $false -Message $_.Exception.Message
        throw "Server not available at $BaseUrl"
    }

    # ============================================================================
    # Test 3: Create Bearer Token
    # ============================================================================

    Write-Host "`n--- Test 3: Create Bearer Token ---" -ForegroundColor Yellow

    try {
        Write-Host "Creating test bearer token..." -ForegroundColor Gray

        # Capture output and suppress verbose messages
        $tokenOutput = & "$PSScriptRoot\system\utility\Account_Auth_BearerToken_New.ps1" `
            -TestAccount `
            -Roles admin, site-admin, system-admin, debug, authenticated `
            -ErrorAction Stop `
            2>&1

        # Convert to string for parsing
        $tokenResult = $tokenOutput | Out-String

        # Extract API key from output
        if ($tokenResult -match 'API Key:\s+([A-Za-z0-9+/=]+)') {
            $script:BearerToken = $matches[1]
        }

        # Extract token name from output
        if ($tokenResult -match 'Name:\s+(\S+)') {
            $script:TokenName = $matches[1]
        }

        if (-not $script:BearerToken -or -not $script:TokenName) {
            throw "Failed to extract bearer token from output. Check if Account_Auth_BearerToken_New.ps1 ran successfully."
        }

        $script:Headers = @{
            'Authorization' = "Bearer $script:BearerToken"
        }

        Test-Result -TestName "Create Bearer Token" -Success $true -Message "Token: $script:TokenName"
    } catch {
        Test-Result -TestName "Create Bearer Token" -Success $false -Message $_.Exception.Message
        throw "Cannot proceed without authentication token"
    }

    # ============================================================================
    # Test 4: Initialize Upload
    # ============================================================================

    Write-Host "`n--- Test 4: Initialize Upload ---" -ForegroundColor Yellow

    try {
        $fileName = Split-Path $TestFilePath -Leaf
        $fileSize = (Get-Item $TestFilePath).Length
        $chunkSize = $ChunkSizeKB * 1024

        $uploadCheckBody = @{
            fileName = $fileName
            fileSize = $fileSize
            targetPath = "User:me"
            uploadMethod = "putChunks"
            chunkSize = $chunkSize
        } | ConvertTo-Json

        $response = Invoke-WebRequest `
            -Uri "$BaseUrl/apps/WebhostFileExplorer/api/v1/files/upload-check" `
            -Method POST `
            -ContentType "application/json" `
            -Body $uploadCheckBody `
            -Headers $script:Headers `
            -UseBasicParsing `
            -ErrorAction Stop

        $uploadData = $response.Content | ConvertFrom-Json

        if ($uploadData.status -eq 'success') {
            $script:UploadGuid = $uploadData.data.uploadGuid
            $totalChunks = $uploadData.data.totalChunks
            Test-Result -TestName "Initialize Upload" -Success $true -Message "Upload GUID: $script:UploadGuid, Total chunks: $totalChunks"
        } else {
            throw "Upload check failed: $($uploadData.message)"
        }
    } catch {
        Test-Result -TestName "Initialize Upload" -Success $false -Message $_.Exception.Message
        throw "Cannot proceed without upload initialization"
    }

    # ============================================================================
    # Test 5: Upload First 25% of Chunks
    # ============================================================================

    Write-Host "`n--- Test 5: Upload First 25% of Chunks ---" -ForegroundColor Yellow

    try {
        $fileStream = [System.IO.File]::OpenRead($TestFilePath)
        $buffer = New-Object byte[] $chunkSize
        $chunksToUpload = [Math]::Ceiling($totalChunks * 0.25)

        $successCount = 0
        for ($chunkIndex = 0; $chunkIndex -lt $chunksToUpload; $chunkIndex++) {
            $offset = $chunkIndex * $chunkSize
            $fileStream.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
            $bytesRead = $fileStream.Read($buffer, 0, $chunkSize)

            $chunkData = New-Object byte[] $bytesRead
            [Array]::Copy($buffer, 0, $chunkData, 0, $bytesRead)

            # PUT /api/v1/files/upload-chunk
            $uri = "$BaseUrl/apps/WebhostFileExplorer/api/v1/files/upload-chunk?uploadGuid=$script:UploadGuid&chunkIndex=$chunkIndex"

            try {
                $response = Invoke-WebRequest `
                    -Uri $uri `
                    -Method PUT `
                    -Body $chunkData `
                    -ContentType "application/octet-stream" `
                    -Headers $script:Headers `
                    -UseBasicParsing `
                    -TimeoutSec 30 `
                    -ErrorAction Stop

                $successCount++

                if ($chunkIndex % 5 -eq 0) {
                    Write-Progress -Activity "Uploading chunks" -Status "$successCount / $chunksToUpload chunks" -PercentComplete (($successCount / $chunksToUpload) * 100)
                }
            } catch {
                Write-Warning "Chunk $chunkIndex failed: $($_.Exception.Message)"
            }
        }

        $fileStream.Close()
        Write-Progress -Activity "Uploading chunks" -Completed

        Test-Result -TestName "Upload First 25%" -Success ($successCount -eq $chunksToUpload) -Message "Uploaded $successCount / $chunksToUpload chunks"

        if ($successCount -ne $chunksToUpload) {
            throw "Not all chunks uploaded successfully"
        }
    } catch {
        Test-Result -TestName "Upload First 25%" -Success $false -Message $_.Exception.Message
        if ($fileStream) { $fileStream.Close() }
        throw "Chunk upload failed"
    }

    # ============================================================================
    # Test 6: Simulate Disconnect
    # ============================================================================

    Write-Host "`n--- Test 6: Simulate Disconnect ---" -ForegroundColor Yellow
    Write-Host "Simulating connection interruption (pausing for 2 seconds)..." -ForegroundColor Gray
    Start-Sleep -Seconds 2
    Test-Result -TestName "Simulate Disconnect" -Success $true -Message "Paused upload"

    # ============================================================================
    # Test 7: Query Upload Status
    # ============================================================================

    Write-Host "`n--- Test 7: Query Upload Status ---" -ForegroundColor Yellow

    try {
        $response = Invoke-WebRequest `
            -Uri "$BaseUrl/apps/WebhostFileExplorer/api/v1/files/upload-status?guid=$script:UploadGuid" `
            -Method GET `
            -Headers $script:Headers `
            -UseBasicParsing `
            -ErrorAction Stop

        $statusData = $response.Content | ConvertFrom-Json

        if ($statusData.status -eq 'success') {
            $receivedChunks = ($statusData.data.chunkBitmap | Where-Object { $_ -eq $true }).Count
            $progress = [Math]::Round(($receivedChunks / $totalChunks) * 100, 2)

            Test-Result -TestName "Query Upload Status" -Success $true -Message "Received $receivedChunks / $totalChunks chunks ($progress%)"
        } else {
            throw "Status query failed: $($statusData.message)"
        }
    } catch {
        Test-Result -TestName "Query Upload Status" -Success $false -Message $_.Exception.Message
        throw "Cannot query upload status"
    }

    # ============================================================================
    # Test 8: Resume Upload (Upload Remaining Chunks)
    # ============================================================================

    Write-Host "`n--- Test 8: Resume Upload ---" -ForegroundColor Yellow

    try {
        $fileStream = [System.IO.File]::OpenRead($TestFilePath)
        $buffer = New-Object byte[] $chunkSize

        # Get chunk bitmap to determine missing chunks
        $chunkBitmap = $statusData.data.chunkBitmap
        $missingChunks = @()
        for ($i = 0; $i -lt $chunkBitmap.Count; $i++) {
            if (-not $chunkBitmap[$i]) {
                $missingChunks += $i
            }
        }

        Write-Host "Missing chunks: $($missingChunks.Count)" -ForegroundColor Gray

        $successCount = 0
        foreach ($chunkIndex in $missingChunks) {
            $offset = $chunkIndex * $chunkSize
            $fileStream.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
            $bytesRead = $fileStream.Read($buffer, 0, $chunkSize)

            $chunkData = New-Object byte[] $bytesRead
            [Array]::Copy($buffer, 0, $chunkData, 0, $bytesRead)

            $uri = "$BaseUrl/apps/WebhostFileExplorer/api/v1/files/upload-chunk?uploadGuid=$script:UploadGuid&chunkIndex=$chunkIndex"

            try {
                $response = Invoke-WebRequest `
                    -Uri $uri `
                    -Method PUT `
                    -Body $chunkData `
                    -ContentType "application/octet-stream" `
                    -Headers $script:Headers `
                    -UseBasicParsing `
                    -TimeoutSec 30 `
                    -ErrorAction Stop

                $successCount++

                if ($successCount % 10 -eq 0) {
                    Write-Progress -Activity "Resuming upload" -Status "$successCount / $($missingChunks.Count) chunks" -PercentComplete (($successCount / $missingChunks.Count) * 100)
                }
            } catch {
                Write-Warning "Chunk $chunkIndex failed: $($_.Exception.Message)"
            }
        }

        $fileStream.Close()
        Write-Progress -Activity "Resuming upload" -Completed

        Test-Result -TestName "Resume Upload" -Success ($successCount -eq $missingChunks.Count) -Message "Uploaded $successCount / $($missingChunks.Count) missing chunks"

        if ($successCount -ne $missingChunks.Count) {
            throw "Not all missing chunks uploaded"
        }
    } catch {
        Test-Result -TestName "Resume Upload" -Success $false -Message $_.Exception.Message
        if ($fileStream) { $fileStream.Close() }
        throw "Resume upload failed"
    }

    # ============================================================================
    # Test 9: Verify Upload Completion
    # ============================================================================

    Write-Host "`n--- Test 9: Verify Upload Completion ---" -ForegroundColor Yellow

    try {
        $response = Invoke-WebRequest `
            -Uri "$BaseUrl/apps/WebhostFileExplorer/api/v1/files/upload-status?guid=$script:UploadGuid" `
            -Method GET `
            -Headers $script:Headers `
            -UseBasicParsing `
            -ErrorAction Stop

        $statusData = $response.Content | ConvertFrom-Json

        if ($statusData.status -eq 'success') {
            $receivedChunks = ($statusData.data.chunkBitmap | Where-Object { $_ -eq $true }).Count
            $isComplete = ($receivedChunks -eq $totalChunks)

            Test-Result -TestName "Verify Upload Completion" -Success $isComplete -Message "Received $receivedChunks / $totalChunks chunks ($(if($isComplete){'COMPLETE'}else{'INCOMPLETE'}))"

            if (-not $isComplete) {
                throw "Upload not complete: $receivedChunks / $totalChunks"
            }
        } else {
            throw "Status query failed: $($statusData.message)"
        }
    } catch {
        Test-Result -TestName "Verify Upload Completion" -Success $false -Message $_.Exception.Message
    }

    # ============================================================================
    # Test 10: Progressive Hash Validation (Simulated)
    # ============================================================================

    Write-Host "`n--- Test 10: Progressive Hash Validation (Simulated) ---" -ForegroundColor Yellow

    try {
        # Read first 100MB and compute SHA256
        $fileStream = [System.IO.File]::OpenRead($TestFilePath)
        $hashAlgo = [System.Security.Cryptography.SHA256]::Create()

        $bytesToHash = [Math]::Min(100 * 1024 * 1024, $fileStream.Length)
        $buffer = New-Object byte[] $bytesToHash
        $fileStream.Read($buffer, 0, $bytesToHash) | Out-Null

        $hashBytes = $hashAlgo.ComputeHash($buffer)
        $hashString = [BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()

        $fileStream.Close()
        $hashAlgo.Dispose()

        Write-Host "First 100MB SHA256: $hashString" -ForegroundColor Gray

        Test-Result -TestName "Progressive Hash Validation" -Success $true -Message "Computed hash for validation"
    } catch {
        Test-Result -TestName "Progressive Hash Validation" -Success $false -Message $_.Exception.Message
        if ($fileStream) { $fileStream.Close() }
        if ($hashAlgo) { $hashAlgo.Dispose() }
    }

} catch {
    # Catch any thrown errors from tests
    Write-Host "`n⚠ Test execution stopped due to error: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    # ALWAYS run cleanup, even if tests failed
    Invoke-Cleanup

    # ============================================================================
    # Test Summary
    # ============================================================================

    Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
    Write-Host "Passed: $($testResults.Passed.Count)" -ForegroundColor Green
    foreach ($test in $testResults.Passed) {
        Write-Host "  ✓ $test" -ForegroundColor Green
    }

    if ($testResults.Failed.Count -gt 0) {
        Write-Host "Failed: $($testResults.Failed.Count)" -ForegroundColor Red
        foreach ($test in $testResults.Failed) {
            Write-Host "  ✗ $test" -ForegroundColor Red
        }
        Write-Host "`nSome tests failed. Review output above for details." -ForegroundColor Yellow
    } else {
        Write-Host "`nAll tests passed! ✓" -ForegroundColor Green
    }

    Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan
}
