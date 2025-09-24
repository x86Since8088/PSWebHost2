param (
    [string]$Name,
    [string]$Path,
    #[validateset('png', 'svg', 'ico', 'gif', 'jpg', 'jpeg', 'webp')]
    #[string]$Format,
    $OutputDir,
    [byte[]]$Bytes,
    [string]$Base64
)

<#
.SYNOPSIS
    Converts a source image into a standard set of favicons and generates an HTML file for them.
.DESCRIPTION
    This script takes a source image and a base name to generate multiple favicon formats (.ico, .png, .svg)
    in various resolutions. It places the generated files in '/public/icon/' and creates a 'favicon.html'
    file with the optimal HTML <link> tags for web implementation.

    Generated PNG Sizes: 16x16, 32x32, 48x48, 180x180, 192x192, 512x512.
.PARAMETER Name
    The base name for the output icon files (e.g., 'my-app').
.PARAMETER Path
    The full path to the source image file (e.g., C:\temp\logo.png).
.EXAMPLE
    PS > .\makefavicon.ps1 -Name "my-app" -Path "C:\Users\Me\Pictures\logo.png"

    This command will generate icons like 'my-app_16x16.png', 'favicon.ico', etc.,
    in the 'e:\sc\git\PsWebHost\public\icon' directory and create 'favicon.html' there.
#>

try{
        Add-Type -AssemblyName System.Drawing | Out-Null
}
catch{
    
}

if ($Base64) {
    $Bytes = [System.Convert]::FromBase64String($Base64)
}


try {
    $outputDir = Split-Path $DestinationPath
    If (!(Test-Path $outputDir)) {mkdir $outputDir}
    # Ensure the System.Drawing assembly is available for image manipulation

    # --- 1. Setup Paths and Validate Inputs ---
    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Source image file not found at: $Path"
    }

    # Create the output directory if it doesn't exist
    if (-not (Test-Path -Path $outputDir)) {
        Write-Host "Creating output directory: $outputDir"
        New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    }

    if ($Bytes.count -ne 0) {
        # Load the byte array into a MemoryStream
        $memoryStream = New-Object System.IO.MemoryStream($Bytes)

        # Create a System.Drawing.Image from the MemoryStream
        $sourceImage = [System.Drawing.Image]::FromStream($memoryStream)
    }
    elseif($Path) {
        Write-Host "Processing source image: $Path"
        $sourceImage = [System.Drawing.Image]::FromFile($Path)
    }
    else {
        Write-Error "No source image provided. Please provide Bytes, Base64, or Path."
        return
    }

    # --- 2. Generate PNG Icons for Various Resolutions ---
    $pngSizes = @(16, 32, 48, 180, 192, 512)
    $generatedPngFiles = @()

    foreach ($size in $pngSizes) {
        $outputPath = Join-Path -Path $outputDir -ChildPath "${Name}_${size}x${size}.png"
        Write-Host "Generating ${size}x${size} PNG: $outputPath"

        $resizedImage = New-Object System.Drawing.Bitmap($size, $size)
        $graphics = [System.Drawing.Graphics]::FromImage($resizedImage)

        # Use high-quality settings for resizing
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

        $graphics.DrawImage($sourceImage, 0, 0, $size, $size)

        $resizedImage.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)

        $graphics.Dispose()
        $resizedImage.Dispose()
        $generatedPngFiles += $outputPath
    }

    # --- 3. Generate favicon.ico ---
    $icoPath = Join-Path -Path $outputDir -ChildPath "$Name`_favicon.ico"
    Write-Host "Generating favicon.ico (32x32): $icoPath"
    $icoBitmap = New-Object System.Drawing.Bitmap($sourceImage, 32, 32)
    $icoBitmap.Save($icoPath, [System.Drawing.Imaging.ImageFormat]::Icon)
    $icoBitmap.Dispose()

    # --- 4. Handle SVG ---
    $svgHref = $null
    if ($Path -like '*.svg') {
        $svgDestPath = Join-Path -Path $outputDir -ChildPath "${Name}.svg"
        Copy-Item -Path $Path -Destination $svgDestPath
        $svgHref = "/icon/${Name}.svg"
        Write-Host "Copied SVG source to: $svgDestPath"
    }

    # --- 5. Generate favicon.html ---
    $htmlPath = Join-Path -Path $outputDir -ChildPath "favicon.html"

    Write-Host "`nFavicon generation complete."
    Write-Host "Files are located in: $outputDir"

}
catch {
    Write-Error "An error occurred during favicon generation: $_"
}
finally {
    # --- 6. Clean up ---
    if ($sourceImage) {
        $sourceImage.Dispose()
    }
}
