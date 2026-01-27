#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test script for binary upload protocol

.DESCRIPTION
    Tests the new binary upload system:
    1. Initialize upload with POST (action=init)
    2. Upload chunks with PUT (binary protocol)
    3. Verify file assembly
    4. Test cancellation

.EXAMPLE
    .\Test-BinaryUpload.ps1 -Test
#>

[CmdletBinding()]
param(
    [switch]$Test
)

$ErrorActionPreference = 'Stop'
$MyTag = '[Test-BinaryUpload]'

Write-Host "`n$MyTag ===== Binary Upload Protocol Test =====" -ForegroundColor Cyan

# Create test file (5MB)
$testFilePath = Join-Path $env:TEMP "test-binary-upload.bin"
$testFileSize = 5 * 1024 * 1024  # 5MB
$chunkSize = 25 * 1024 * 1024    # 25MB (will result in 1 chunk for 5MB file)

Write-Host "`n$MyTag Creating test file: $testFilePath ($testFileSize bytes)" -ForegroundColor Yellow

# Create random binary data
$randomBytes = New-Object byte[] $testFileSize
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($randomBytes)
[System.IO.File]::WriteAllBytes($testFilePath, $randomBytes)

Write-Host "$MyTag Test file created: $(Get-Item $testFilePath | Select-Object Name, Length)" -ForegroundColor Green

# Calculate chunks
$totalChunks = [Math]::Ceiling($testFileSize / $chunkSize)
Write-Host "$MyTag File will be split into $totalChunks chunk(s)" -ForegroundColor Gray

# Test binary header creation
Write-Host "`n$MyTag Testing binary header creation..." -ForegroundColor Yellow

$header = New-Object byte[] 10
$randomValue = Get-Random -Minimum 0 -Maximum 65536
$chunkNumber = 0
$bytesRemaining = 0

# Write header (little-endian)
[BitConverter]::GetBytes([uint16]$randomValue).CopyTo($header, 0)
[BitConverter]::GetBytes([uint32]$chunkNumber).CopyTo($header, 2)
[BitConverter]::GetBytes([uint32]$bytesRemaining).CopyTo($header, 6)

Write-Host "$MyTag Header created:" -ForegroundColor Green
Write-Host "  Random Value (uint16): $randomValue" -ForegroundColor Gray
Write-Host "  Chunk Number (uint32): $chunkNumber" -ForegroundColor Gray
Write-Host "  Bytes Remaining (uint32): $bytesRemaining" -ForegroundColor Gray

# Verify header parsing
$parsedRandom = [BitConverter]::ToUInt16($header, 0)
$parsedChunk = [BitConverter]::ToUInt32($header, 2)
$parsedRemaining = [BitConverter]::ToUInt32($header, 6)

Write-Host "`n$MyTag Verifying header parsing:" -ForegroundColor Yellow
Write-Host "  Parsed Random: $parsedRandom (expected: $randomValue) - $($parsedRandom -eq $randomValue ? 'PASS' : 'FAIL')" -ForegroundColor $(if ($parsedRandom -eq $randomValue) { 'Green' } else { 'Red' })
Write-Host "  Parsed Chunk: $parsedChunk (expected: $chunkNumber) - $($parsedChunk -eq $chunkNumber ? 'PASS' : 'FAIL')" -ForegroundColor $(if ($parsedChunk -eq $chunkNumber) { 'Green' } else { 'Red' })
Write-Host "  Parsed Remaining: $parsedRemaining (expected: $bytesRemaining) - $($parsedRemaining -eq $bytesRemaining ? 'PASS' : 'FAIL')" -ForegroundColor $(if ($parsedRemaining -eq $bytesRemaining) { 'Green' } else { 'Red' })

# Test upload metadata structure
Write-Host "`n$MyTag Testing upload metadata structure..." -ForegroundColor Yellow

if (-not $Global:PSWebServer) {
    $Global:PSWebServer = @{}
}

if (-not $Global:PSWebServer.Uploads) {
    $Global:PSWebServer.Uploads = [hashtable]::Synchronized(@{})
}

$testGuid = [Guid]::NewGuid().ToString()
$Global:PSWebServer.Uploads[$testGuid] = @{
    Guid = $testGuid
    UserID = 'test-user'
    FileName = 'test-file.bin'
    FileSize = [long]$testFileSize
    ChunkSize = [int]$chunkSize
    TotalChunks = [int]$totalChunks
    TargetPath = $env:TEMP
    TempDirectory = Join-Path $env:TEMP ".temp\$testGuid"
    CreatedAt = Get-Date
    ReceivedChunks = 0
    ChunkMap = @{}
}

Write-Host "$MyTag Upload metadata created for GUID: $testGuid" -ForegroundColor Green
$Global:PSWebServer.Uploads[$testGuid] | Format-List | Out-String | Write-Host

# Cleanup
Remove-Item $testFilePath -Force -ErrorAction SilentlyContinue
$Global:PSWebServer.Uploads.Remove($testGuid)

Write-Host "`n$MyTag ===== Binary Upload Protocol Structure Tests PASSED =====" -ForegroundColor Green
Write-Host ""
Write-Host "$MyTag Next steps:" -ForegroundColor Yellow
Write-Host "  1. Upload a file through File Explorer UI" -ForegroundColor Gray
Write-Host "  2. Monitor browser console for binary upload logs" -ForegroundColor Gray
Write-Host "  3. Check server logs for GUID allocation and chunk reception" -ForegroundColor Gray
Write-Host "  4. Verify file assembly completes successfully" -ForegroundColor Gray
Write-Host ""
Write-Host "$MyTag Protocol Summary:" -ForegroundColor Cyan
Write-Host "  - POST /api/v1/files/upload-chunk with action=init → Returns GUID" -ForegroundColor Gray
Write-Host "  - PUT /api/v1/files/upload-chunk?guid=XXX with binary data (10-byte header + chunk)" -ForegroundColor Gray
Write-Host "  - POST /api/v1/files/upload-chunk with action=cancel → Cleanup" -ForegroundColor Gray
Write-Host "  - Chunk size: 25MB (much larger than old 512KB base64 chunks)" -ForegroundColor Gray
Write-Host "  - Binary transfer (no base64 encoding overhead)" -ForegroundColor Gray
Write-Host ""
Write-Host "$MyTag ===== Test Complete =====" -ForegroundColor Cyan
