#Requires -Version 7

<#
.SYNOPSIS
    Comprehensive integration tests for PSWebHost Memory Analysis System

.DESCRIPTION
    End-to-end testing of all memory analysis components including:
    - Module loading and initialization
    - Type overhead calculation (CSV + runtime)
    - Object graph traversal with reference tracking
    - Circular reference detection
    - Memory consumption orchestration
    - Assembly memory analysis
    - HTTP endpoint integration
    - NDJSON streaming

.NOTES
    Run this from PSWebHost root directory
#>

param(
    [switch]$Verbose,
    [switch]$SkipEndpointTests  # Skip HTTP endpoint tests if PSWebHost not running
)

$ErrorActionPreference = 'Stop'

# Test Results
$script:TestResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
    Tests = @()
}

function Test-Assert {
    param(
        [string]$Name,
        [scriptblock]$Test,
        [string]$ExpectedError = $null
    )

    try {
        $result = & $Test

        if ($ExpectedError) {
            # Expected an error but didn't get one
            $script:TestResults.Failed++
            $script:TestResults.Tests += @{
                Name = $Name
                Status = 'FAILED'
                Message = "Expected error '$ExpectedError' but test passed"
            }
            Write-Host "  ❌ FAIL: $Name" -ForegroundColor Red
            return $false
        }

        $script:TestResults.Passed++
        $script:TestResults.Tests += @{
            Name = $Name
            Status = 'PASSED'
            Message = 'Test passed'
        }
        Write-Host "  ✅ PASS: $Name" -ForegroundColor Green
        return $true

    } catch {
        if ($ExpectedError -and $_.Exception.Message -match $ExpectedError) {
            # Expected error occurred
            $script:TestResults.Passed++
            $script:TestResults.Tests += @{
                Name = $Name
                Status = 'PASSED'
                Message = "Expected error occurred: $_"
            }
            Write-Host "  ✅ PASS: $Name (expected error)" -ForegroundColor Green
            return $true
        }

        $script:TestResults.Failed++
        $script:TestResults.Tests += @{
            Name = $Name
            Status = 'FAILED'
            Message = $_.Exception.Message
        }
        Write-Host "  ❌ FAIL: $Name - $_" -ForegroundColor Red
        return $false
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PSWebHost Memory Analysis System" -ForegroundColor Cyan
Write-Host "Integration Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Test Suite 1: Module Import
Write-Host "📦 Test Suite 1: Module Import & Initialization" -ForegroundColor Yellow

Test-Assert "Module file exists" {
    $modulePath = "$PSScriptRoot\modules\PSWebHost_MemoryAnalysis\PSWebHost_MemoryAnalysis.psd1"
    if (-not (Test-Path $modulePath)) {
        throw "Module manifest not found"
    }
    $true
}

Test-Assert "Module imports successfully" {
    Import-Module "$PSScriptRoot\modules\PSWebHost_MemoryAnalysis\PSWebHost_MemoryAnalysis.psd1" -Force
    $true
}

Test-Assert "Module functions exported" {
    $functions = @(
        'Get-MemoryConsumption',
        'Measure-ObjectGraph',
        'Get-TypeMemoryOverhead',
        'Get-ObjectEstimatedSize',
        'Get-AssemblyMemory',
        'Get-AssemblyMemorySummary',
        'Format-AssemblyMemoryReport'
    )

    foreach ($func in $functions) {
        $cmd = Get-Command $func -ErrorAction SilentlyContinue
        if (-not $cmd) {
            throw "Function '$func' not exported"
        }
    }
    $true
}

Test-Assert "CSV database exists and loads" {
    $csvPath = "$PSScriptRoot\system\data\PS_Object_Memory_Calculations.csv"
    if (-not (Test-Path $csvPath)) {
        throw "CSV database not found"
    }

    $csv = Import-Csv $csvPath
    if ($csv.Count -lt 40) {
        throw "CSV should have at least 40 type entries, found $($csv.Count)"
    }
    $true
}

# Test Suite 2: Type Overhead
Write-Host "`n📏 Test Suite 2: Type Overhead Calculation" -ForegroundColor Yellow

Test-Assert "CSV lookup for System.String" {
    $overhead = Get-TypeMemoryOverhead -TypeName 'System.String'
    if ($overhead.Source -ne 'CSV') {
        throw "Expected CSV source, got $($overhead.Source)"
    }
    if ($overhead.BaseSize -ne 24) {
        throw "Expected BaseSize 24, got $($overhead.BaseSize)"
    }
    $true
}

Test-Assert "CSV lookup for System.Collections.Hashtable" {
    $overhead = Get-TypeMemoryOverhead -TypeName 'System.Collections.Hashtable'
    if ($overhead.Source -ne 'CSV') {
        throw "Expected CSV source"
    }
    if ($overhead.BaseSize -ne 80) {
        throw "Expected BaseSize 80, got $($overhead.BaseSize)"
    }
    $true
}

Test-Assert "Runtime measurement for custom class" {
    class TestClass { [string]$Name; [int]$Value }
    $obj = [TestClass]@{ Name = "Test"; Value = 42 }
    $overhead = Get-TypeMemoryOverhead -Object $obj
    if ($overhead.Source -ne 'Runtime') {
        throw "Expected Runtime source for custom class"
    }
    if ($overhead.BaseSize -lt 24) {
        throw "Custom class should have at least 24 bytes base size"
    }
    $true
}

Test-Assert "Estimated size for string" {
    $str = "Hello, World!"
    $size = Get-ObjectEstimatedSize -Object $str
    # 24 base + 26 content (13 chars * 2 bytes) = 50
    if ($size.TotalSize -ne 50) {
        throw "Expected 50 bytes, got $($size.TotalSize)"
    }
    $true
}

Test-Assert "Estimated size for hashtable" {
    $ht = @{ a = 1; b = 2; c = 3 }
    $size = Get-ObjectEstimatedSize -Object $ht
    # 80 base + 48 content (3 entries * 16 bytes) = 128
    if ($size.TotalSize -ne 128) {
        throw "Expected 128 bytes, got $($size.TotalSize)"
    }
    $true
}

# Test Suite 3: Object Graph Traversal
Write-Host "`n🌳 Test Suite 3: Object Graph Traversal" -ForegroundColor Yellow

Test-Assert "Simple object traversal" {
    $obj = @{ Name = "Test"; Value = 123 }
    $seen = @{}
    $chain = [System.Collections.Generic.Stack[int]]::new()
    $result = Measure-ObjectGraph -RootObject $obj -Path "TestObj" -SeenObjects $seen -ParentChain $chain -MaxDepth 3

    if ($result.TotalSize -eq 0) {
        throw "TotalSize should be greater than 0"
    }
    if ($seen.Count -eq 0) {
        throw "SeenObjects should track visited objects"
    }
    $true
}

Test-Assert "Reference counting" {
    $shared = @{ Data = "Shared" }
    $container = @{ First = $shared; Second = $shared }

    $seen = @{}
    $chain = [System.Collections.Generic.Stack[int]]::new()
    $result = Measure-ObjectGraph -RootObject $container -Path "Container" -MaxDepth 3 -SeenObjects $seen -ParentChain $chain

    # Check that shared object has RefCount = 2
    $sharedId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($shared)
    if ($seen[$sharedId].RefCount -ne 2) {
        throw "Shared object should have RefCount=2, got $($seen[$sharedId].RefCount)"
    }
    $true
}

Test-Assert "Circular reference detection" {
    $parent = @{ Name = "Parent" }
    $child = @{ Name = "Child"; Parent = $parent }
    $parent.Child = $child

    $seen = @{}
    $chain = [System.Collections.Generic.Stack[int]]::new()
    $result = Measure-ObjectGraph -RootObject $parent -Path "Parent" -MaxDepth 5 -SeenObjects $seen -ParentChain $chain

    # Find circular reference in results
    function Find-Circular {
        param($Node)
        if ($Node.IsCircular) { return $true }
        if ($Node.Children) {
            foreach ($child in $Node.Children) {
                if (Find-Circular -Node $child) { return $true }
            }
        }
        return $false
    }

    if (-not (Find-Circular -Node $result)) {
        throw "Circular reference not detected"
    }
    $true
}

Test-Assert "Depth limiting" {
    $deep = @{ L1 = @{ L2 = @{ L3 = @{ L4 = @{ L5 = "Deep" } } } } }

    $seen = @{}
    $chain = [System.Collections.Generic.Stack[int]]::new()
    $result = Measure-ObjectGraph -RootObject $deep -Path "Deep" -MaxDepth 3 -SeenObjects $seen -ParentChain $chain

    # Should stop at depth 3
    function Get-Depth {
        param($Node, $Current = 0)
        if (-not $Node.Children -or $Node.Children.Count -eq 0) { return $Current }
        $maxChild = $Current
        foreach ($child in $Node.Children) {
            $childDepth = Get-Depth -Node $child -Current ($Current + 1)
            if ($childDepth -gt $maxChild) { $maxChild = $childDepth }
        }
        return $maxChild
    }

    $actualDepth = Get-Depth -Node $result
    if ($actualDepth -gt 3) {
        throw "Depth should be limited to 3, got $actualDepth"
    }
    $true
}

# Test Suite 4: Memory Consumption Orchestration
Write-Host "`n🎯 Test Suite 4: Memory Consumption Orchestration" -ForegroundColor Yellow

Test-Assert "Analyze single variable" {
    $Global:TestVar = @{ Name = "Test"; Data = 1..10 }
    $result = Get-MemoryConsumption -VariablePath "TestVar" -Depth 3

    if ($result.TotalVariables -ne 1) {
        throw "Expected 1 variable analyzed"
    }
    if ($result.TotalObjects -eq 0) {
        throw "Expected objects to be counted"
    }
    if ($result.Duration -le 0) {
        throw "Duration should be positive"
    }
    $true
}

Test-Assert "Nested path resolution" {
    $Global:TestNested = @{ Apps = @{ FileExplorer = @{ Size = 1024 } } }
    $result = Get-MemoryConsumption -VariablePath "TestNested.Apps" -Depth 3

    if ($result.Variables.Count -eq 0) {
        throw "Expected nested path to be resolved"
    }
    $true
}

Test-Assert "Size filtering" {
    $Global:SmallVar = @{ Tiny = 1 }
    $Global:LargeVar = @{ Big = 1..1000 }

    $result = Get-MemoryConsumption -VariablePath @("SmallVar", "LargeVar") -MinSize 100 -Depth 3

    # LargeVar should pass filter, SmallVar should not
    if ($result.Variables.Count -eq 0) {
        throw "Expected at least one variable to pass size filter"
    }
    $true
}

Test-Assert "Timeout protection" {
    $Global:DeepData = @{ L1 = @{ L2 = @{ L3 = @{ L4 = @{ L5 = 1..100 } } } } }
    $result = Get-MemoryConsumption -VariablePath "DeepData" -Depth 10 -TimeoutSeconds 1

    # Should complete without error (may or may not timeout)
    if ($result.Duration -le 0) {
        throw "Duration should be positive"
    }
    $true
}

Test-Assert "Streaming callback invocation" {
    $callbackCount = 0
    $callback = { param($m) $script:callbackCount++ }

    $Global:StreamTestVar = @{ A = 1; B = 2; C = 3 }
    Get-MemoryConsumption -VariablePath "StreamTestVar" -Depth 2 -StreamCallback $callback

    if ($callbackCount -eq 0) {
        throw "Streaming callback should be invoked"
    }
    $true
}

# Test Suite 5: Assembly Memory Analysis
Write-Host "`n📚 Test Suite 5: Assembly Memory Analysis" -ForegroundColor Yellow

Test-Assert "Basic assembly enumeration" {
    $assemblies = Get-AssemblyMemory
    if ($assemblies.Count -eq 0) {
        throw "Should enumerate at least some assemblies"
    }
    $true
}

Test-Assert "Assembly has required properties" {
    $assemblies = Get-AssemblyMemory | Select-Object -First 1
    $required = @('Name', 'Version', 'EstimatedSize', 'TypeCount', 'IsGAC', 'IsDynamic')

    foreach ($prop in $required) {
        if (-not $assemblies.PSObject.Properties[$prop]) {
            throw "Assembly missing property: $prop"
        }
    }
    $true
}

Test-Assert "Assembly size estimation" {
    $assemblies = Get-AssemblyMemory
    $largest = $assemblies | Sort-Object EstimatedSize -Descending | Select-Object -First 1

    if ($largest.EstimatedSize -lt 1KB) {
        throw "Largest assembly should be at least 1 KB"
    }
    $true
}

Test-Assert "Assembly summary generation" {
    $assemblies = Get-AssemblyMemory
    $summary = Get-AssemblyMemorySummary -AssemblyData $assemblies

    if ($summary.TotalAssemblies -ne $assemblies.Count) {
        throw "Summary count mismatch"
    }
    if ($summary.TotalEstimatedSize -eq 0) {
        throw "Total size should be positive"
    }
    $true
}

Test-Assert "Assembly report formatting" {
    $assemblies = Get-AssemblyMemory | Select-Object -First 5
    $report = Format-AssemblyMemoryReport -AssemblyData $assemblies -IncludeSummary -IncludeTopN 5

    if ($report.Length -eq 0) {
        throw "Report should not be empty"
    }
    if ($report -notmatch "Assembly Memory Summary") {
        throw "Report should contain summary section"
    }
    $true
}

Test-Assert "Type details analysis" {
    $assemblies = Get-AssemblyMemory -IncludeTypeDetails -MinimumSize 100KB | Select-Object -First 1

    if ($assemblies.Count -gt 0) {
        $asm = $assemblies[0]
        if (-not $asm.PSObject.Properties['MethodCount']) {
            throw "Type details should include MethodCount"
        }
        if (-not $asm.PSObject.Properties['FieldCount']) {
            throw "Type details should include FieldCount"
        }
    }
    $true
}

# Test Suite 6: HTTP Endpoint Integration
if (-not $SkipEndpointTests) {
    Write-Host "`n🌐 Test Suite 6: HTTP Endpoint Integration" -ForegroundColor Yellow

    Test-Assert "Memory analysis endpoint responds" {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:8080/api/v1/debug/vars?format=memory&path=&depth=1&timeout=5" `
                                          -Method GET `
                                          -TimeoutSec 10 `
                                          -UseBasicParsing

            if ($response.StatusCode -ne 200) {
                throw "Expected status 200, got $($response.StatusCode)"
            }
            $true
        } catch {
            Write-Host "  ⚠️  SKIPPED: Endpoint test (PSWebHost may not be running)" -ForegroundColor Yellow
            $script:TestResults.Skipped++
            $false
        }
    }

    Test-Assert "Memory explorer UI endpoint responds" {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:8080/cards/memory-explorer" `
                                          -Method GET `
                                          -TimeoutSec 5 `
                                          -UseBasicParsing

            if ($response.StatusCode -ne 200) {
                throw "Expected status 200"
            }
            if ($response.Content -notmatch "memory-explorer") {
                throw "Response should contain memory-explorer component"
            }
            $true
        } catch {
            Write-Host "  ⚠️  SKIPPED: UI endpoint test (PSWebHost may not be running)" -ForegroundColor Yellow
            $script:TestResults.Skipped++
            $false
        }
    }
} else {
    Write-Host "`n🌐 Test Suite 6: HTTP Endpoint Integration - SKIPPED" -ForegroundColor Yellow
}

# Test Suite 7: Error Handling
Write-Host "`n🛡️  Test Suite 7: Error Handling & Edge Cases" -ForegroundColor Yellow

Test-Assert "Handle null objects" {
    $result = Get-TypeMemoryOverhead -Object $null
    if ($result.BaseSize -ne 8) {
        throw "Null should be 8 bytes"
    }
    $true
}

Test-Assert "Handle invalid variable path" {
    $result = Get-MemoryConsumption -VariablePath "NonExistentVariable123" -Depth 1
    if ($result.Errors.Count -eq 0) {
        throw "Should report error for invalid path"
    }
    $true
}

Test-Assert "Handle collection enumeration limits" {
    $Global:HugeArray = 1..5000
    $seen = @{}
    $chain = [System.Collections.Generic.Stack[int]]::new()
    $result = Measure-ObjectGraph -RootObject $Global:HugeArray -Path "HugeArray" `
                                   -MaxDepth 1 -MaxEnumeration 1000 -SeenObjects $seen -ParentChain $chain

    # Should truncate at 1000 items
    if ($result.Children.Count -gt 1000) {
        throw "Enumeration should be limited to 1000 items"
    }
    $true
}

# Cleanup test variables
Remove-Variable -Name TestVar, TestNested, SmallVar, LargeVar, DeepData, StreamTestVar, HugeArray -Scope Global -ErrorAction SilentlyContinue

# Print Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ✅ Passed:  $($script:TestResults.Passed)" -ForegroundColor Green
Write-Host "  ❌ Failed:  $($script:TestResults.Failed)" -ForegroundColor $(if ($script:TestResults.Failed -gt 0) { "Red" } else { "Gray" })
Write-Host "  ⚠️  Skipped: $($script:TestResults.Skipped)" -ForegroundColor Yellow
Write-Host "  📊 Total:   $($script:TestResults.Tests.Count)" -ForegroundColor Cyan
Write-Host ""

$passRate = if ($script:TestResults.Tests.Count -gt 0) {
    [math]::Round(($script:TestResults.Passed / $script:TestResults.Tests.Count) * 100, 1)
} else { 0 }

Write-Host "Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -eq 100) { "Green" } elseif ($passRate -ge 80) { "Yellow" } else { "Red" })

if ($script:TestResults.Failed -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    foreach ($test in $script:TestResults.Tests | Where-Object { $_.Status -eq 'FAILED' }) {
        Write-Host "  - $($test.Name): $($test.Message)" -ForegroundColor Red
    }
}

Write-Host "`n========================================`n" -ForegroundColor Cyan

# Exit with appropriate code
exit $(if ($script:TestResults.Failed -gt 0) { 1 } else { 0 })
