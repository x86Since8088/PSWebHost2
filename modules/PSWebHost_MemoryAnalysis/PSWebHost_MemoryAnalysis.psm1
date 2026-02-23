#Requires -Version 7

<#
.SYNOPSIS
    PSWebHost Advanced Memory Analysis Module

.DESCRIPTION
    Provides sophisticated memory analysis capabilities for PSWebHost including:
    - Reference-aware object graph traversal
    - Type overhead calculations (CSV database + runtime fallback)
    - Circular reference detection
    - Method ownership analysis
    - Assembly/DLL memory enumeration
    - Streaming NDJSON output for real-time browser updates

.NOTES
    Module: PSWebHost_MemoryAnalysis
    Version: 1.0.0
    Author: PSWebHost
    Created: 2026-02-01
#>

$MyTag = '[PSWebHost_MemoryAnalysis]'

# Module initialization
Write-Verbose "$MyTag Loading PSWebHost_MemoryAnalysis module..."

# Get module root directory
$ModuleRoot = $PSScriptRoot

# ============================================================================
# Load Private Helper Functions
# ============================================================================

$privateFunctions = @(
    'TypeOverheadCache.ps1'
)

foreach ($function in $privateFunctions) {
    $functionPath = Join-Path $ModuleRoot "Private\$function"

    if (Test-Path $functionPath) {
        Write-Verbose "$MyTag Loading private function: $function"
        . $functionPath
    } else {
        Write-Warning "$MyTag Private function not found: $function"
    }
}

# ============================================================================
# Load Public Functions
# ============================================================================

$publicFunctions = @(
    'Get-TypeMemoryOverhead.ps1',
    'Measure-ObjectGraph.ps1',
    'Get-MemoryConsumption.ps1',
    'Get-AssemblyMemory.ps1'
)

foreach ($function in $publicFunctions) {
    $functionPath = Join-Path $ModuleRoot "Public\$function"

    if (Test-Path $functionPath) {
        Write-Verbose "$MyTag Loading public function: $function"
        . $functionPath
    } else {
        Write-Warning "$MyTag Public function not found: $function"
    }
}

# ============================================================================
# Module Initialization
# ============================================================================

# Initialize type overhead cache on module load
try {
    Write-Verbose "$MyTag Initializing type overhead cache..."
    Initialize-TypeOverheadCache -ErrorAction SilentlyContinue | Out-Null

    $cacheStats = Get-TypeOverheadCacheStats
    if ($cacheStats.Loaded) {
        Write-Verbose "$MyTag Type overhead cache initialized: $($cacheStats.TotalEntries) types loaded from CSV"
    } else {
        Write-Verbose "$MyTag Type overhead cache initialized (empty - will use runtime measurement)"
    }
} catch {
    Write-Warning "$MyTag Failed to initialize type overhead cache: $_"
}

# ============================================================================
# Export Module Members
# ============================================================================

# Public functions are automatically exported via module manifest (FunctionsToExport)
# No need to explicitly Export-ModuleMember here

Write-Verbose "$MyTag PSWebHost_MemoryAnalysis module loaded successfully"
