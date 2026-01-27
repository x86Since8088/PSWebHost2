# Test script for delete operation debugging

param(
    [string]$TestFilePath = "C:\Temp\testfile.txt"
)

# Dot-source the helper file
    Import-TrackedModule "FileExplorerHelper"
Write-Host "`n=== Testing Delete Operation ===" -ForegroundColor Cyan

# Create test file if it doesn't exist
if (-not (Test-Path $TestFilePath)) {
    $testDir = Split-Path $TestFilePath -Parent
    if (-not (Test-Path $testDir)) {
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null
    }
    "Test content" | Set-Content -Path $TestFilePath
    Write-Host "Created test file: $TestFilePath" -ForegroundColor Yellow
}

# Mock session data
$mockSessionData = @{
    UserID = 'test-user-123'
    Username = 'testuser'
    Email = 'test@example.com'
    Roles = @('authenticated')
}

# Mock items to delete
$mockItems = @(
    @{
        PhysicalPath = $TestFilePath
        LogicalPath = "local|localhost|$TestFilePath"
    }
)

Write-Host "`nTesting Move-WebHostFileExplorerToTrash..." -ForegroundColor Yellow
Write-Host "UserID: $($mockSessionData.UserID)"
Write-Host "Items: $($mockItems.Count)"
Write-Host "File: $TestFilePath"

try {
    $result = Move-WebHostFileExplorerToTrash `
        -UserID $mockSessionData.UserID `
        -Items $mockItems `
        -Action 'delete' `
        -SessionData $mockSessionData

    Write-Host "`n=== Success ===" -ForegroundColor Green
    Write-Host "Moved Items: $($result.movedItems.Count)"
    Write-Host "Errors: $($result.errors.Count)"
    Write-Host "Operation ID: $($result.operation.id)"

    if ($result.movedItems.Count -gt 0) {
        Write-Host "`nMoved Item Details:"
        $result.movedItems | ForEach-Object {
            Write-Host "  Original: $($_.originalPath)"
            Write-Host "  Trash: $($_.trashPath)"
            Write-Host "  Metadata: $($_.metadataPath)"
            Write-Host "  Is Remote: $($_.isRemote)"
        }
    }

    if ($result.errors.Count -gt 0) {
        Write-Host "`nErrors:" -ForegroundColor Red
        $result.errors | ForEach-Object {
            Write-Host "  Path: $($_.path)"
            Write-Host "  Error: $($_.error)"
        }
    }
}
catch {
    Write-Host "`n=== Error ===" -ForegroundColor Red
    Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "`nStack Trace:" -ForegroundColor Gray
    Write-Host $_.ScriptStackTrace
}

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan
