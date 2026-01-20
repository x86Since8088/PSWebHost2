param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata,
    [switch]$Test,
    [string[]]$Roles = @(),
    [hashtable]$Query = @{}
)

# Dot-source File Explorer helper functions
try {
    $helperPath = Join-Path $PSScriptRoot "..\..\..\..\modules\FileExplorerHelper.ps1"

    if (-not (Test-Path $helperPath)) {
        throw "Helper file not found: $helperPath"
    }

    # Always dot-source (each script scope needs its own copy)
    . $helperPath
}
catch {
    if ($Test) {
        Write-Host "`n=== File Explorer Helper Load Error ===" -ForegroundColor Red
        Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Stack Trace:" -ForegroundColor Gray
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
        Write-Host "`n=== End Error ===" -ForegroundColor Red
        return
    }
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Failed to load FileExplorerHelper.ps1: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode 500 -String $Report.body -ContentType $Report.contentType
    return
}

# Handle test mode
if ($Test) {
    # Create mock sessiondata
    if ($Roles.Count -eq 0) {
        $Roles = @('authenticated')
    }
    $sessiondata = @{
        Roles = $Roles
        UserID = 'test-user-123'
        SessionID = 'test-session'
    }
    Write-Host "`n=== VersionInfo GET Test Mode ===" -ForegroundColor Cyan
    Write-Host "UserID: $($sessiondata.UserID)" -ForegroundColor Yellow
    Write-Host "Roles: $($Roles -join ', ')" -ForegroundColor Yellow
}

# Validate session
if ($Test) {
    $userID = $sessiondata.UserID
} else {
    $userID = Test-WebHostFileExplorerSession -SessionData $sessiondata -Response $Response
    if (-not $userID) { return }
}

# Get path parameter (e.g., "local|localhost|user:me/Documents/file.exe")
if ($Test -and $Query.Count -gt 0) {
    $path = $Query['path']
} else {
    $path = $Request.QueryString['path']
}

if (-not $path) {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Missing path parameter'
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
    return
}

if ($Test) {
    Write-Host "Path: $path" -ForegroundColor Yellow
}

try {
    # Parse path format: local|localhost|user:me/Documents/file.exe
    if ($path -match '^([^|]+)\|([^|]+)\|(.+)$') {
        $node = $matches[1]        # "local"
        $nodeName = $matches[2]    # "localhost"
        $logicalPath = $matches[3] # "user:me/Documents/file.exe"

        if ($Test) {
            Write-Host "Parsed Path Components:" -ForegroundColor Cyan
            Write-Host "  Node: $node" -ForegroundColor Yellow
            Write-Host "  NodeName: $nodeName" -ForegroundColor Yellow
            Write-Host "  Logical Path: $logicalPath" -ForegroundColor Yellow
        }
    }
    else {
        # Fallback: treat entire path as logical path
        $logicalPath = $path

        if ($Test) {
            Write-Host "Using fallback parsing for path: $path" -ForegroundColor Yellow
        }
    }

    # Resolve logical path to physical path with authorization
    $pathResult = Resolve-WebHostFileExplorerPath -LogicalPath $logicalPath -UserID $userID -Roles $sessiondata.Roles -Response $Response -RequiredPermission 'read'
    if (-not $pathResult) { return }

    $fullPath = $pathResult.PhysicalPath

    if ($Test) {
        Write-Host "Physical Path: $fullPath" -ForegroundColor Yellow
    }

    if (-not (Test-Path $fullPath)) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'File not found'
        if ($Test) {
            Write-Host "`n=== Test Result: 404 Not Found ===" -ForegroundColor Red
            Write-Host "Message: File not found" -ForegroundColor Yellow
            Write-Host "Physical Path: $fullPath" -ForegroundColor Yellow
            return
        }
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 404 -JsonContent $json
        return
    }

    $fileInfo = Get-Item $fullPath

    if ($fileInfo -is [System.IO.DirectoryInfo]) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Cannot get version info for a folder'
        if ($Test) {
            Write-Host "`n=== Test Result: 400 Bad Request ===" -ForegroundColor Red
            Write-Host "Message: Cannot get version info for a folder" -ForegroundColor Yellow
            return
        }
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
        return
    }

    # Build version info structure
    $versionInfo = @{
        fileMetadata = @{
            size = $fileInfo.Length
            created = $fileInfo.CreationTime.ToString("o")
            modified = $fileInfo.LastWriteTime.ToString("o")
            accessed = $fileInfo.LastAccessTime.ToString("o")
            attributes = @($fileInfo.Attributes.ToString().Split(',').Trim())
            extension = $fileInfo.Extension.ToLower()
        }
    }

    # PE Version Info (for .exe, .dll, .sys)
    if ($fileInfo.Extension.ToLower() -in @('.exe', '.dll', '.sys', '.ocx', '.cpl', '.scr')) {
        try {
            $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($fileInfo.FullName)
            $versionInfo.peVersionInfo = @{
                fileVersion = $vi.FileVersion
                productVersion = $vi.ProductVersion
                fileVersionRaw = @{
                    major = $vi.FileMajorPart
                    minor = $vi.FileMinorPart
                    build = $vi.FileBuildPart
                    revision = $vi.FilePrivatePart
                }
                productVersionRaw = @{
                    major = $vi.ProductMajorPart
                    minor = $vi.ProductMinorPart
                    build = $vi.ProductBuildPart
                    revision = $vi.ProductPrivatePart
                }
                companyName = $vi.CompanyName
                fileDescription = $vi.FileDescription
                productName = $vi.ProductName
                legalCopyright = $vi.LegalCopyright
                originalFilename = $vi.OriginalFilename
                internalName = $vi.InternalName
                isDebug = $vi.IsDebug
                isPatched = $vi.IsPatched
                isPreRelease = $vi.IsPreRelease
                isPrivateBuild = $vi.IsPrivateBuild
                isSpecialBuild = $vi.IsSpecialBuild
                language = $vi.Language
            }

            if ($Test) {
                Write-Host "`nPE Version Info:" -ForegroundColor Cyan
                Write-Host "  File Version: $($vi.FileVersion)" -ForegroundColor Yellow
                Write-Host "  Product Version: $($vi.ProductVersion)" -ForegroundColor Yellow
                Write-Host "  Company: $($vi.CompanyName)" -ForegroundColor Yellow
            }
        }
        catch {
            if ($Test) {
                Write-Host "`nWarning: Could not read PE version info: $($_.Exception.Message)" -ForegroundColor Yellow
            }
            Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Could not read PE version info for $($fileInfo.Name): $($_.Exception.Message)"
        }
    }

    # Document Properties (for Office docs, PDFs)
    if ($fileInfo.Extension.ToLower() -in @('.docx', '.xlsx', '.pptx', '.doc', '.xls', '.ppt', '.pdf')) {
        try {
            $shell = New-Object -ComObject Shell.Application
            $folder = $shell.NameSpace($fileInfo.DirectoryName)
            $item = $folder.ParseName($fileInfo.Name)

            $versionInfo.documentProperties = @{
                author = $folder.GetDetailsOf($item, 20)   # Author
                title = $folder.GetDetailsOf($item, 21)    # Title
                subject = $folder.GetDetailsOf($item, 22)  # Subject
                tags = $folder.GetDetailsOf($item, 18)     # Tags
                comments = $folder.GetDetailsOf($item, 24) # Comments
                category = $folder.GetDetailsOf($item, 256) # Category
                pages = $folder.GetDetailsOf($item, 13)    # Pages
            }

            # Remove empty properties
            $versionInfo.documentProperties = $versionInfo.documentProperties.GetEnumerator() |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_.Value) } |
                ForEach-Object -Begin { $h = @{} } -Process { $h[$_.Name] = $_.Value } -End { $h }

            if ($Test -and $versionInfo.documentProperties.Count -gt 0) {
                Write-Host "`nDocument Properties:" -ForegroundColor Cyan
                $versionInfo.documentProperties.GetEnumerator() | ForEach-Object {
                    Write-Host "  $($_.Name): $($_.Value)" -ForegroundColor Yellow
                }
            }
        }
        catch {
            if ($Test) {
                Write-Host "`nWarning: Could not read document properties: $($_.Exception.Message)" -ForegroundColor Yellow
            }
            Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Could not read document properties for $($fileInfo.Name): $($_.Exception.Message)"
        }
    }

    # Image EXIF (for images)
    if ($fileInfo.Extension.ToLower() -in @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.tif', '.webp')) {
        try {
            # Use System.Drawing for basic image properties (works on Windows)
            Add-Type -AssemblyName System.Drawing
            $image = [System.Drawing.Image]::FromFile($fileInfo.FullName)

            $versionInfo.imageProperties = @{
                width = $image.Width
                height = $image.Height
                pixelFormat = $image.PixelFormat.ToString()
                horizontalResolution = $image.HorizontalResolution
                verticalResolution = $image.VerticalResolution
                rawFormat = $image.RawFormat.ToString()
            }

            # Parse EXIF data from PropertyItems
            $exifData = @{}
            foreach ($property in $image.PropertyItems) {
                # Common EXIF tag IDs
                $tagName = switch ($property.Id) {
                    0x010F { "Make" }              # Camera manufacturer
                    0x0110 { "Model" }             # Camera model
                    0x0132 { "DateTime" }          # Date/time original
                    0x829A { "ExposureTime" }      # Exposure time
                    0x829D { "FNumber" }           # F-number
                    0x8827 { "ISO" }               # ISO speed
                    0x9003 { "DateTimeOriginal" }  # Date/time original (more specific)
                    0x9004 { "DateTimeDigitized" } # Date/time digitized
                    0x920A { "FocalLength" }       # Focal length
                    0x9286 { "UserComment" }       # User comment
                    0xA002 { "PixelWidth" }        # Image width
                    0xA003 { "PixelHeight" }       # Image height
                    default { $null }
                }

                if ($tagName) {
                    try {
                        # Try to decode value based on type
                        $value = switch ($property.Type) {
                            1 { [System.Text.Encoding]::ASCII.GetString($property.Value).TrimEnd([char]0) }  # ASCII
                            2 { [System.Text.Encoding]::ASCII.GetString($property.Value).TrimEnd([char]0) }  # ASCII
                            3 { [BitConverter]::ToUInt16($property.Value, 0) }  # Short
                            4 { [BitConverter]::ToUInt32($property.Value, 0) }  # Long
                            5 { # Rational
                                if ($property.Value.Length -ge 8) {
                                    $num = [BitConverter]::ToUInt32($property.Value, 0)
                                    $den = [BitConverter]::ToUInt32($property.Value, 4)
                                    if ($den -ne 0) { [double]$num / $den } else { 0 }
                                } else { 0 }
                            }
                            default { [System.Text.Encoding]::ASCII.GetString($property.Value).TrimEnd([char]0) }
                        }
                        $exifData[$tagName] = $value
                    }
                    catch {
                        # Skip problematic EXIF values
                    }
                }
            }

            if ($exifData.Count -gt 0) {
                $versionInfo.imageProperties.exif = $exifData
            }

            $image.Dispose()

            if ($Test) {
                Write-Host "`nImage Properties:" -ForegroundColor Cyan
                Write-Host "  Dimensions: $($versionInfo.imageProperties.width) x $($versionInfo.imageProperties.height)" -ForegroundColor Yellow
                Write-Host "  DPI: $($versionInfo.imageProperties.horizontalResolution) x $($versionInfo.imageProperties.verticalResolution)" -ForegroundColor Yellow
                if ($exifData.Count -gt 0) {
                    Write-Host "  EXIF Tags: $($exifData.Count) found" -ForegroundColor Yellow
                }
            }
        }
        catch {
            if ($Test) {
                Write-Host "`nWarning: Could not read image properties: $($_.Exception.Message)" -ForegroundColor Yellow
            }
            Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Could not read image properties for $($fileInfo.Name): $($_.Exception.Message)"
        }
    }

    # Return version info
    $responseData = @{
        status = "success"
        message = "Version info retrieved"
        path = $path
        versionInfo = $versionInfo
    }

    # Test mode output
    if ($Test) {
        Write-Host "`n=== VersionInfo GET Test Results ===" -ForegroundColor Cyan
        Write-Host "Status: 200 OK" -ForegroundColor Green
        Write-Host "Content-Type: application/json" -ForegroundColor Gray
        Write-Host "`nVersion Info:" -ForegroundColor Cyan
        $versionInfo | ConvertTo-Json -Depth 10 | Write-Host
        Write-Host "`n=== Summary ===" -ForegroundColor Cyan
        Write-Host "Path: $path" -ForegroundColor Yellow
        Write-Host "Physical Path: $fullPath" -ForegroundColor Yellow
        Write-Host "File Size: $($fileInfo.Length) bytes" -ForegroundColor Yellow
        Write-Host "Extension: $($fileInfo.Extension)" -ForegroundColor Yellow
        Write-Host "`n=== End Test Results ===" -ForegroundColor Cyan
        return
    }

    $jsonResponse = $responseData | ConvertTo-Json -Depth 10 -Compress
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $jsonResponse
}
catch {
    if ($Test) {
        Write-Host "`n=== VersionInfo GET Test Error ===" -ForegroundColor Red
        Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Stack Trace:" -ForegroundColor Gray
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
        Write-Host "`n=== End Test Error ===" -ForegroundColor Red
        return
    }
    Send-WebHostFileExplorerError -ErrorRecord $_ -Context $Context -Request $Request -Response $Response -SessionData $sessiondata -LogData @{ UserID = $userID; Path = $path }
}
