# Delete Temporary Upload File
# Deletes a temporary file from the upload directory

param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    # Extract filename from URL
    $pathParts = $Request.Url.AbsolutePath -split '/'
    $fileName = $pathParts[-2]  # Filename is second to last part

    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $errorResponse = @{
            success = $false
            error = 'Filename is required'
        } | ConvertTo-Json
        context_response -Response $Response -StatusCode 400 -String $errorResponse -ContentType 'application/json'
        return
    }

    # Get temp directory
    $tempDir = Join-Path $Global:PSWebServer.Project_Root.Path 'PsWebHost_Data\temp\uploads'

    # Ensure temp directory exists
    if (-not (Test-Path $tempDir)) {
        $errorResponse = @{
            success = $false
            error = 'Temp directory does not exist'
        } | ConvertTo-Json
        context_response -Response $Response -StatusCode 404 -String $errorResponse -ContentType 'application/json'
        return
    }

    # Build full file path
    $filePath = Join-Path $tempDir $fileName

    # Security check: Ensure the file is within temp directory (prevent path traversal)
    $resolvedPath = Resolve-Path -Path $filePath -ErrorAction SilentlyContinue
    if ($resolvedPath -and $resolvedPath.Path.StartsWith($tempDir)) {
        # File exists and is in temp directory - delete it
        if (Test-Path $filePath) {
            Remove-Item $filePath -Force -ErrorAction Stop

            Write-PSWebHostLog -Message "Deleted temp file: $fileName" -Level 'Info' -Facility 'FileExplorer'

            $successResponse = @{
                success = $true
                message = "Temp file deleted successfully"
                fileName = $fileName
            } | ConvertTo-Json
            context_response -Response $Response -StatusCode 200 -String $successResponse -ContentType 'application/json'
        } else {
            # File doesn't exist
            $errorResponse = @{
                success = $false
                error = 'File not found'
                fileName = $fileName
            } | ConvertTo-Json
            context_response -Response $Response -StatusCode 404 -String $errorResponse -ContentType 'application/json'
        }
    } else {
        # Path traversal attempt or file outside temp directory
        Write-PSWebHostLog -Message "Blocked attempt to delete file outside temp directory: $fileName" -Level 'Warning' -Facility 'FileExplorer'

        $errorResponse = @{
            success = $false
            error = 'Invalid file path'
        } | ConvertTo-Json
        context_response -Response $Response -StatusCode 403 -String $errorResponse -ContentType 'application/json'
    }

} catch {
    Write-PSWebHostLog -Message "Error deleting temp file: $($_.Exception.Message)" -Level 'Error' -Facility 'FileExplorer'

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
