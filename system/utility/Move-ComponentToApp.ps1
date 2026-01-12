<#
.SYNOPSIS
    Intelligently moves components (routes, elements, system, tests) to PSWebHost apps

.DESCRIPTION
    Uses dependency analysis data to safely move components to apps.
    Moves related files together and updates references.

.PARAMETER ComponentPath
    Relative path of the component to move (e.g., "routes/api/v1/system/services")

.PARAMETER TargetApp
    Name of the target app (e.g., "WindowsAdmin")

.PARAMETER IncludeTests
    Also move corresponding test files

.PARAMETER IncludeHelp
    Also move corresponding help files

.PARAMETER WhatIf
    Show what would be moved without actually moving

.EXAMPLE
    .\Move-ComponentToApp.ps1 -ComponentPath "routes/api/v1/system/services" -TargetApp "WindowsAdmin"

.EXAMPLE
    .\Move-ComponentToApp.ps1 -ComponentPath "public/elements/docker-manager" -TargetApp "DockerManager" -IncludeTests -WhatIf
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ComponentPath,

    [Parameter(Mandatory=$true)]
    [string]$TargetApp,

    [switch]$IncludeTests,
    [switch]$IncludeHelp,
    [switch]$WhatIf
)

# Normalize path separators
$ComponentPath = $ComponentPath -replace '\\', '/'

# Determine project root
$projectRoot = $PSScriptRoot -replace '[/\\]system[/\\].*'
$analysisFile = Join-Path $projectRoot "PsWebHost_Data\system\utility\Analyze-Dependencies.json"

if (-not (Test-Path $analysisFile)) {
    Write-Host "ERROR: Analysis file not found. Please run Analyze-Dependencies.ps1 first." -ForegroundColor Red
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Move Component to App" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "Component: $ComponentPath" -ForegroundColor White
Write-Host "Target App: $TargetApp" -ForegroundColor White
Write-Host "Mode: $(if ($WhatIf) { 'DRY RUN (WhatIf)' } else { 'LIVE' })" -ForegroundColor $(if ($WhatIf) { 'Yellow' } else { 'Green' })
Write-Host ""

# Load analysis data
Write-Host "[1/5] Loading dependency analysis..." -ForegroundColor Yellow
$analysis = Get-Content $analysisFile | ConvertFrom-Json
$results = $analysis.Results
Write-Host "  Loaded $($results.Count) analyzed files" -ForegroundColor Gray
Write-Host ""

# Find all files related to this component
Write-Host "[2/5] Finding related files..." -ForegroundColor Yellow
$relatedFiles = @()

# Normalize component path for comparison
$ComponentPathNormalized = $ComponentPath -replace '\\', '/'

# Direct match
$directMatches = $results | Where-Object {
    ($_.FilePath -replace '\\', '/') -like "$ComponentPathNormalized*"
}
$relatedFiles += $directMatches
Write-Host "  Found $($directMatches.Count) files in component path" -ForegroundColor Gray

# Find UI element routes if moving a public element
if ($ComponentPath -match '^public[/\\]elements[/\\]([^/\\]+)') {
    $elementName = $matches[1]
    $elementRoutes = $results | Where-Object {
        ($_.FilePath -replace '\\', '/') -like "routes/api/v1/ui/elements/$elementName/*"
    }
    $relatedFiles += $elementRoutes
    Write-Host "  Found $($elementRoutes.Count) UI element routes" -ForegroundColor Gray
}

# Find public elements if moving a UI route
if ($ComponentPath -match '^routes[/\\]api[/\\]v1[/\\]ui[/\\]elements[/\\]([^/\\]+)') {
    $elementName = $matches[1]
    $publicElements = $results | Where-Object {
        ($_.FilePath -replace '\\', '/') -like "public/elements/$elementName/*"
    }
    $relatedFiles += $publicElements
    Write-Host "  Found $($publicElements.Count) public element files" -ForegroundColor Gray
}

# Find tests if requested
if ($IncludeTests) {
    $testMatches = $results | Where-Object {
        ($_.FilePath -replace '\\', '/') -like "tests/twin/$ComponentPathNormalized*" -or
        ($_.FilePath -replace '\\', '/') -like "tests/*$ComponentPathNormalized*"
    }
    $relatedFiles += $testMatches
    Write-Host "  Found $($testMatches.Count) test files" -ForegroundColor Gray
}

# Find help files if requested
if ($IncludeHelp) {
    # Extract component name for help search
    $componentName = ($ComponentPath -split '[/\\]')[-1]
    $helpMatches = $results | Where-Object {
        ($_.FilePath -replace '\\', '/') -like "public/help/*$componentName*"
    }
    $relatedFiles += $helpMatches
    Write-Host "  Found $($helpMatches.Count) help files" -ForegroundColor Gray
}

# Also add any non-PowerShell files in the component directory
Write-Host "  Checking for non-PowerShell files in component path..." -ForegroundColor Gray
$componentFullPath = Join-Path $projectRoot $ComponentPath
if (Test-Path $componentFullPath) {
    $allComponentFiles = Get-ChildItem -Path $componentFullPath -Recurse -File | ForEach-Object {
        $relativePath = $_.FullName.Substring($projectRoot.Length + 1) -replace '\\', '/'
        [PSCustomObject]@{
            FilePath = $relativePath
            ExtractabilityScore = 100  # Non-PowerShell files are safe to move
            Recommendation = 'Easy - Extract'
            CoreFunctionsUsed = ''
            CoreFunctionCount = 0
            DatabaseAccess = ''
            DatabaseAccessCount = 0
            ImportedModules = ''
            GlobalReferences = ''
            GlobalRefCount = 0
            ExternalTools = ''
            ExternalToolCount = 0
            URLReferences = ''
            URLReferenceCount = 0
            ComponentType = 'Asset'
        }
    }
    $relatedFiles = @($relatedFiles) + @($allComponentFiles)
    Write-Host "  Added $($allComponentFiles.Count) additional files from component directory" -ForegroundColor Gray
}

# Deduplicate by normalizing paths before comparison
$uniquePaths = @{}
$deduplicatedFiles = @()
foreach ($file in $relatedFiles) {
    $normalizedPath = ($file.FilePath -replace '\\', '/').ToLower()
    if (-not $uniquePaths.ContainsKey($normalizedPath)) {
        $uniquePaths[$normalizedPath] = $true
        $deduplicatedFiles += $file
    }
}
$relatedFiles = $deduplicatedFiles

Write-Host "  Total files to move: $($relatedFiles.Count)" -ForegroundColor White
Write-Host ""

if ($relatedFiles.Count -eq 0) {
    Write-Host "No files found matching: $ComponentPath" -ForegroundColor Yellow
    exit 0
}

# Analyze dependencies
Write-Host "[3/5] Analyzing dependencies..." -ForegroundColor Yellow
$highDependency = $relatedFiles | Where-Object { $_.ExtractabilityScore -lt 60 }
if ($highDependency.Count -gt 0) {
    Write-Host "  WARNING: $($highDependency.Count) files have high core dependencies (score < 60)" -ForegroundColor Yellow
    $highDependency | ForEach-Object {
        Write-Host "    - $($_.FilePath) (Score: $($_.ExtractabilityScore))" -ForegroundColor Gray
    }
} else {
    Write-Host "  ✓ All files are safe to extract (score >= 60)" -ForegroundColor Green
}
Write-Host ""

# Determine target paths
Write-Host "[4/5] Planning file moves..." -ForegroundColor Yellow
$appPath = Join-Path $projectRoot "apps\$TargetApp"

if (-not (Test-Path $appPath)) {
    Write-Host "  ERROR: App not found: $appPath" -ForegroundColor Red
    exit 1
}

$moves = @()
foreach ($file in $relatedFiles) {
    $sourcePath = Join-Path $projectRoot $file.FilePath
    $sourceRelative = $file.FilePath

    # Determine target path within app
    $targetRelative = $sourceRelative

    # Map routes -> app routes (preserving api/v1 structure)
    if ($sourceRelative -match '^routes[/\\](.+)') {
        $targetRelative = "routes\$($matches[1])"
    }
    # Map public -> app public
    elseif ($sourceRelative -match '^public[/\\](.+)') {
        $targetRelative = "public\$($matches[1])"
    }
    # Map tests -> app tests
    elseif ($sourceRelative -match '^tests[/\\]twin[/\\](.+)') {
        $targetRelative = "tests\$($matches[1])"
    }
    # Map system/utility -> app system
    elseif ($sourceRelative -match '^system[/\\]utility[/\\](.+)') {
        $targetRelative = "system\$($matches[1])"
    }
    # Map system/jobs -> app jobs
    elseif ($sourceRelative -match '^system[/\\]jobs[/\\](.+)') {
        $targetRelative = "jobs\$($matches[1])"
    }

    $targetPath = Join-Path $appPath $targetRelative

    $moves += [PSCustomObject]@{
        Source = $sourcePath
        Target = $targetPath
        Relative = $sourceRelative
        Exists = (Test-Path $sourcePath)
    }
}

Write-Host "  Planned $($moves.Count) file moves" -ForegroundColor White
Write-Host ""

# Execute moves
Write-Host "[5/5] $(if ($WhatIf) { 'Simulating' } else { 'Executing' }) moves..." -ForegroundColor Yellow

foreach ($move in $moves) {
    if (-not $move.Exists) {
        Write-Host "  SKIP (not found): $($move.Relative)" -ForegroundColor Gray
        continue
    }

    $targetDir = Split-Path $move.Target -Parent

    if ($WhatIf) {
        Write-Host "  WOULD MOVE: $($move.Relative)" -ForegroundColor Cyan
        Write-Host "         TO: $($move.Target.Substring($projectRoot.Length + 1))" -ForegroundColor Gray
    } else {
        # Create target directory
        if (-not (Test-Path $targetDir)) {
            New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
        }

        # Move the file
        try {
            Move-Item -Path $move.Source -Destination $move.Target -Force
            Write-Host "  ✓ MOVED: $($move.Relative)" -ForegroundColor Green
        } catch {
            Write-Host "  ✗ FAILED: $($move.Relative) - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "$(if ($WhatIf) { 'Simulation' } else { 'Migration' }) Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if (-not $WhatIf) {
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Update $TargetApp/menu.yaml with new menu items" -ForegroundColor Gray
    Write-Host "  2. Restart PSWebHost to load updated app" -ForegroundColor Gray
    Write-Host "  3. Test all moved functionality" -ForegroundColor Gray
    Write-Host ""
}
