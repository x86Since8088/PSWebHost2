param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    Batch file hash validation endpoint

.DESCRIPTION
    Validates multiple byte ranges of a file by computing and comparing SHA256 hashes.
    Accepts CSV input with ByteIndex, Length, and expected Sha256 hash.
    Returns CSV with ByteIndex, Length, Sha256 (actual), and Score (pass/fail).

    Can validate either:
    - Upload GUID (from active uploads or Upload_Sessions table)
    - Logical file path (from FileExplorer path format)

.EXAMPLE
    POST /api/v1/files/validation?guid=d8058f21-69ab-413e-9454-515bffa51951
    Content-Type: text/csv

    ByteIndex,Length,Sha256
    0,131072,abc123...
    10485760,131072,def456...

    Response:
    ByteIndex,Length,Sha256,Score
    0,131072,abc123...,pass
    10485760,131072,def456...,pass

.EXAMPLE
    POST /api/v1/files/validation?path=User:me/test.iso
    Content-Type: text/csv

    ByteIndex,Length,Sha256
    0,131072,abc123...
    10485760,131072,def456...
#>

# Import File Explorer helper module functions
try {
    Import-TrackedModule "FileExplorerHelper"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Failed to import FileExplorerHelper module: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode 500 -String $Report.body -ContentType $Report.contentType
    return
}

# Validate session
$userID = Test-WebHostFileExplorerSession -SessionData $sessiondata -Response $Response
if (-not $userID) { return }

# Get GUID or path from query string
$guid = $Request.QueryString['guid']
$logicalPath = $Request.QueryString['path']

if (-not $guid -and -not $logicalPath) {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Missing required parameter: guid or path'
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
    return
}

# Resolve file path
$physicalPath = $null

try {
    if ($guid) {
        # Try to find upload by GUID
        Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Looking up upload by GUID: $guid"

        # Check database first
        $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/pswebhost.db"
        $query = "SELECT TempFilePath, UserID FROM Upload_Sessions WHERE UploadGuid = @Guid"
        $result = Invoke-SqliteQuery -DataSource $dbFile -Query $query -SqlParameters @{ Guid = $guid }

        if ($result) {
            if ($result.UserID -ne $userID) {
                $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Access denied: upload belongs to another user'
                Send-WebHostFileExplorerResponse -Response $Response -StatusCode 403 -JsonContent $json
                return
            }
            $physicalPath = $result.TempFilePath
        }
        elseif ($Global:PSWebServer.Uploads -and $Global:PSWebServer.Uploads.ContainsKey($guid)) {
            # Check in-memory
            $uploadInfo = $Global:PSWebServer.Uploads[$guid]
            if ($uploadInfo.UserID -ne $userID) {
                $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Access denied: upload belongs to another user'
                Send-WebHostFileExplorerResponse -Response $Response -StatusCode 403 -JsonContent $json
                return
            }
            $physicalPath = $uploadInfo.TempFilePath
        }
        else {
            # GUID not found - check for orphaned temp file
            $tempFileName = "NewUploadTemp_$guid.tmp"
            $tempSearchPath = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data"

            $tempFiles = Get-ChildItem -Path $tempSearchPath -Recurse -Filter $tempFileName -ErrorAction SilentlyContinue
            if ($tempFiles -and $tempFiles.Count -gt 0) {
                Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Found orphaned temp file for GUID: $guid"
                $physicalPath = $tempFiles[0].FullName
            }
            else {
                $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Upload not found: $guid (no database entry, no in-memory entry, no temp file)"
                Send-WebHostFileExplorerResponse -Response $Response -StatusCode 404 -JsonContent $json
                return
            }
        }
    }
    elseif ($logicalPath) {
        # Resolve logical path to physical path
        Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Resolving logical path: $logicalPath"

        $resolveResult = Path_Resolve -LogicalPath $logicalPath -UserID $userID -RequireRead
        if (-not $resolveResult.success) {
            $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Path resolution failed: $($resolveResult.Message)"
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
            return
        }

        $physicalPath = $resolveResult.PhysicalPath
    }

    # Verify physical path exists
    if (-not (Test-Path $physicalPath)) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "File not found: $physicalPath"
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 404 -JsonContent $json
        return
    }

    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Validating file: $physicalPath"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Failed to resolve file path: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode 500 -String $Report.body -ContentType $Report.contentType
    return
}

# Read CSV input from request body
try {
    $requestBody = [System.IO.StreamReader]::new($Request.InputStream).ReadToEnd()

    if ([string]::IsNullOrWhiteSpace($requestBody)) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Empty request body'
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
        return
    }

    # Parse CSV
    $csvLines = $requestBody -split "`n" | Where-Object { $_.Trim() }
    if ($csvLines.Count -lt 2) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'CSV must have header and at least one data row'
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
        return
    }

    # Parse header
    $header = $csvLines[0] -split ','
    if ($header[0].Trim() -ne 'ByteIndex' -or $header[1].Trim() -ne 'Length' -or $header[2].Trim() -ne 'Sha256') {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'CSV header must be: ByteIndex,Length,Sha256'
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
        return
    }

    # Parse data rows
    $validationRequests = @()
    for ($i = 1; $i -lt $csvLines.Count; $i++) {
        $fields = $csvLines[$i] -split ','
        if ($fields.Count -ge 3) {
            $validationRequests += @{
                ByteIndex = [long]$fields[0].Trim()
                Length = [int]$fields[1].Trim()
                ExpectedHash = $fields[2].Trim()
            }
        }
    }

    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Received $($validationRequests.Count) validation requests"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Failed to parse CSV: $($_.Exception.Message)"
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "CSV parsing error: $($_.Exception.Message)"
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
    return
}

# Perform validations
try {
    $fileItem = Get-Item $physicalPath -ErrorAction Stop
    $fileSize = $fileItem.Length

    $stream = [System.IO.File]::OpenRead($physicalPath)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()

    $results = @()

    foreach ($req in $validationRequests) {
        $byteIndex = $req.ByteIndex
        $length = $req.Length
        $expectedHash = $req.ExpectedHash

        # Check if byte range is within file
        if ($byteIndex -ge $fileSize) {
            # Byte index beyond file size - return fail
            $results += @{
                ByteIndex = $byteIndex
                Length = $length
                Sha256 = ''
                Score = 'fail'
                Reason = 'ByteIndex beyond file size'
            }
            continue
        }

        # Adjust length if it extends beyond file
        $actualLength = $length
        if (($byteIndex + $length) -gt $fileSize) {
            $actualLength = $fileSize - $byteIndex
        }

        # Read and hash the range
        $buffer = New-Object byte[] $actualLength
        $stream.Position = $byteIndex
        $bytesRead = $stream.Read($buffer, 0, $actualLength)

        if ($bytesRead -gt 0) {
            $hashBytes = $sha256.ComputeHash($buffer, 0, $bytesRead)
            $actualHash = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()

            $score = if ($actualHash -eq $expectedHash.ToLower()) { 'pass' } else { 'fail' }

            $results += @{
                ByteIndex = $byteIndex
                Length = $actualLength
                Sha256 = $actualHash
                Score = $score
            }
        }
        else {
            # Read failed
            $results += @{
                ByteIndex = $byteIndex
                Length = $length
                Sha256 = ''
                Score = 'fail'
                Reason = 'Read failed'
            }
        }
    }

    $stream.Close()
    $stream.Dispose()
    $sha256.Dispose()

    # Build CSV response
    $csvOutput = "ByteIndex,Length,Sha256,Score`n"
    foreach ($result in $results) {
        $csvOutput += "$($result.ByteIndex),$($result.Length),$($result.Sha256),$($result.Score)`n"
    }

    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Completed $($results.Count) validations, $(($results | Where-Object { $_.Score -eq 'pass' }).Count) passed"

    # Send CSV response
    $Response.ContentType = 'text/csv'
    $Response.StatusCode = 200
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($csvOutput)
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.Close()

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Validation error: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode 500 -String $Report.body -ContentType $Report.contentType
    return
}
