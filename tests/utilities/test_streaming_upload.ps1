# Test streaming upload performance and resume functionality

param(
    [string]$ServerUrl = "http://localhost:8080",
    [string]$TestFileSizeMB = 100,
    [string]$TargetPath = "/",
    [switch]$TestResume
)

Write-Host "=== Streaming Upload Test ===" -ForegroundColor Cyan
Write-Host "Server: $ServerUrl"
Write-Host "Test File Size: ${TestFileSizeMB}MB"
Write-Host "Target Path: $TargetPath"
Write-Host ""

# Create test file
$testFileName = "test_streaming_$(Get-Date -Format 'yyyyMMdd_HHmmss').bin"
$testFilePath = Join-Path $env:TEMP $testFileName
$testFileSizeBytes = [long]$TestFileSizeMB * 1024 * 1024

Write-Host "Creating test file: $testFilePath" -ForegroundColor Yellow
$fs = [System.IO.File]::Create($testFilePath)
try {
    $fs.SetLength($testFileSizeBytes)

    # Write some random data at intervals (not the whole file - too slow)
    $random = New-Object System.Random
    $chunkSize = 1MB
    $chunks = [math]::Min(10, $testFileSizeBytes / $chunkSize)

    for ($i = 0; $i -lt $chunks; $i++) {
        $buffer = New-Object byte[] $chunkSize
        $random.NextBytes($buffer)
        $fs.Write($buffer, 0, $buffer.Length)
        Write-Progress -Activity "Generating test file" -Status "$i/$chunks chunks" -PercentComplete (($i/$chunks)*100)
    }

    Write-Progress -Activity "Generating test file" -Completed
}
finally {
    $fs.Close()
}

Write-Host "Test file created: $('{0:N2}' -f ($testFileSizeBytes/1MB))MB" -ForegroundColor Green
Write-Host ""

# Get auth token (assumes you're logged in)
$token = Get-Content "$env:USERPROFILE\.psweb\auth_token" -ErrorAction SilentlyContinue
if (-not $token) {
    Write-Host "Error: No auth token found. Please login first." -ForegroundColor Red
    exit 1
}

# Step 1: Initialize upload
Write-Host "Step 1: Initializing upload session..." -ForegroundColor Yellow
$initUrl = "$ServerUrl/apps/WebhostFileExplorer/api/v1/files/upload-stream"
$initBody = @{
    fileName = $testFileName
    fileSize = $testFileSizeBytes
    targetPath = $TargetPath
} | ConvertTo-Json

try {
    $initResponse = Invoke-RestMethod -Uri $initUrl -Method PUT -Headers @{
        Authorization = "Bearer $token"
        'Content-Type' = 'application/json'
    } -Body $initBody

    $uploadGuid = $initResponse.data.guid
    $startOffset = $initResponse.data.startOffset

    Write-Host "Upload session initialized:" -ForegroundColor Green
    Write-Host "  GUID: $uploadGuid"
    Write-Host "  Start Offset: $startOffset"
    Write-Host ""
}
catch {
    Write-Host "Error initializing upload: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Step 2: Upload file data
Write-Host "Step 2: Uploading file data..." -ForegroundColor Yellow
$uploadUrl = "$ServerUrl/apps/WebhostFileExplorer/api/v1/files/upload-stream?guid=$uploadGuid"

# Read file into memory (for small test files this is OK)
$fileBytes = [System.IO.File]::ReadAllBytes($testFilePath)

$startTime = Get-Date

try {
    # Create WebRequest for better control
    $request = [System.Net.HttpWebRequest]::Create($uploadUrl)
    $request.Method = "PUT"
    $request.Headers.Add("Authorization", "Bearer $token")
    $request.ContentLength = $fileBytes.Length
    $request.Timeout = 300000  # 5 minute timeout
    $request.SendChunked = $false

    # Write to request stream
    $requestStream = $request.GetRequestStream()
    try {
        $requestStream.Write($fileBytes, 0, $fileBytes.Length)
        $requestStream.Flush()
    }
    finally {
        $requestStream.Close()
    }

    # Get response
    $response = $request.GetResponse()
    $responseStream = $response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($responseStream)
    $responseText = $reader.ReadToEnd()

    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    $speedMBps = ($testFileSizeBytes / 1MB) / $duration

    Write-Host "Upload completed successfully!" -ForegroundColor Green
    Write-Host "  Duration: $([math]::Round($duration, 2))s"
    Write-Host "  Speed: $([math]::Round($speedMBps, 2)) MB/s"
    Write-Host "  Response: $responseText"
    Write-Host ""

    $reader.Close()
    $response.Close()
}
catch {
    Write-Host "Error uploading file: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.InnerException.Message)" -ForegroundColor Red
    exit 1
}

# Cleanup
Write-Host "Cleaning up test file..." -ForegroundColor Yellow
Remove-Item -Path $testFilePath -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== Test Complete ===" -ForegroundColor Cyan
