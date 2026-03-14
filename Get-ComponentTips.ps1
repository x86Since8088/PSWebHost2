#Requires -Version 7

<#
.SYNOPSIS
    RAG-style component reference query tool

.DESCRIPTION
    Queries the COMPONENT_REFERENCE.csv file for component tips, common issues,
    and implementation guidance. Uses keywords and filters to provide context-efficient
    answers without loading full component code.

.PARAMETER ComponentName
    Name of the component to query

.PARAMETER Keyword
    Keyword to search for across all components

.PARAMETER Type
    Filter by component type (Core, App)

.PARAMETER Status
    Filter by component status (OK, Missing, Placeholder)

.PARAMETER ShowAll
    Display all components

.EXAMPLE
    .\Get-ComponentTips.ps1 -ComponentName "main-menu"
    Shows details for the main-menu component

.EXAMPLE
    .\Get-ComponentTips.ps1 -Keyword "docker"
    Finds all components related to docker

.EXAMPLE
    .\Get-ComponentTips.ps1 -Status Missing
    Lists all components with missing files

.EXAMPLE
    .\Get-ComponentTips.ps1 -Type App -ShowAll
    Lists all app components
#>

param(
    [string]$ComponentName,
    [string]$Keyword,
    [ValidateSet('Core', 'App', '')]
    [string]$Type,
    [ValidateSet('OK', 'Missing', 'Placeholder', '')]
    [string]$Status,
    [switch]$ShowAll
)

$csvPath = Join-Path $PSScriptRoot "COMPONENT_REFERENCE.csv"

if (-not (Test-Path $csvPath)) {
    Write-Host "ERROR: Component reference CSV not found: $csvPath" -ForegroundColor Red
    Write-Host "Run check_all_components.ps1 first to generate the reference." -ForegroundColor Yellow
    exit 1
}

# Load CSV
$components = Import-Csv $csvPath

# Apply filters
$filtered = $components

if ($ComponentName) {
    $filtered = $filtered | Where-Object { $_.ComponentName -like "*$ComponentName*" -or $_.ElementId -like "*$ComponentName*" }
}

if ($Keyword) {
    $filtered = $filtered | Where-Object {
        $_.ComponentName -like "*$Keyword*" -or
        $_.Purpose -like "*$Keyword*" -or
        $_.Keywords -like "*$Keyword*" -or
        $_.Tips -like "*$Keyword*"
    }
}

if ($Type) {
    $filtered = $filtered | Where-Object { $_.Type -eq $Type }
}

if ($Status) {
    $filtered = $filtered | Where-Object { $_.Status -eq $Status }
}

# Display results
if ($filtered.Count -eq 0) {
    Write-Host "No components found matching criteria" -ForegroundColor Yellow
    exit 0
}

Write-Host "`n=== Component Reference Query Results ===" -ForegroundColor Cyan
Write-Host "Found $($filtered.Count) component(s)`n" -ForegroundColor Green

foreach ($comp in $filtered) {
    Write-Host "──────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "Component: " -NoNewline -ForegroundColor Yellow
    Write-Host $comp.ComponentName -ForegroundColor White

    Write-Host "Element ID: " -NoNewline -ForegroundColor Gray
    Write-Host $comp.ElementId

    Write-Host "Type: " -NoNewline -ForegroundColor Gray
    Write-Host "$($comp.Type) " -NoNewline
    Write-Host "| Status: " -NoNewline -ForegroundColor Gray
    $statusColor = switch ($comp.Status) {
        'OK' { 'Green' }
        'Missing' { 'Red' }
        default { 'Yellow' }
    }
    Write-Host $comp.Status -ForegroundColor $statusColor

    Write-Host "Path: " -NoNewline -ForegroundColor Gray
    Write-Host $comp.Path -ForegroundColor DarkCyan

    Write-Host "`nPurpose:" -ForegroundColor Cyan
    Write-Host "  $($comp.Purpose)" -ForegroundColor White

    if ($comp.Props) {
        Write-Host "`nProps: " -NoNewline -ForegroundColor Cyan
        Write-Host $comp.Props -ForegroundColor Gray
    }

    if ($comp.CommonIssues -and $comp.CommonIssues -ne 'None') {
        Write-Host "`nCommon Issues:" -ForegroundColor Yellow
        Write-Host "  $($comp.CommonIssues)" -ForegroundColor White
    }

    Write-Host "`nTips:" -ForegroundColor Green
    Write-Host "  $($comp.Tips)" -ForegroundColor White

    if ($comp.Keywords) {
        Write-Host "`nKeywords: " -NoNewline -ForegroundColor Gray
        Write-Host $comp.Keywords
    }

    Write-Host ""
}

Write-Host "──────────────────────────────────────`n" -ForegroundColor DarkGray

# Show summary
if ($ShowAll) {
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    $summary = $filtered | Group-Object Status | Select-Object Name, Count
    $summary | ForEach-Object {
        $color = switch ($_.Name) {
            'OK' { 'Green' }
            'Missing' { 'Red' }
            default { 'Yellow' }
        }
        Write-Host "  $($_.Name): $($_.Count)" -ForegroundColor $color
    }
    Write-Host ""
}
