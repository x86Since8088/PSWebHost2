#Requires -Version 7

# Test script for Get-MemoryConsumption orchestrator

Import-Module "$PSScriptRoot\modules\PSWebHost_MemoryAnalysis\PSWebHost_MemoryAnalysis.psd1" -Force

Write-Host "`n=== Test 1: Analyze Single Variable ===" -ForegroundColor Cyan
$Global:TestVar = @{
    Name = "TestApp"
    Config = @{ Port = 8080; Host = "localhost" }
    Data = 1..100
}

$result = Get-MemoryConsumption -VariablePath "TestVar" -Depth 3 -Verbose
Write-Host "Variable: TestVar"
Write-Host "  Total Objects: $($result.TotalObjects)"
Write-Host "  Total Size: $($result.TotalSize) bytes"
Write-Host "  Total References: $($result.TotalReferences)"
Write-Host "  Duration: $([math]::Round($result.Duration, 3))s"
Write-Host "  Variables Analyzed: $($result.Variables.Count)"

Write-Host "`n=== Test 2: Analyze Nested Path ===" -ForegroundColor Cyan
$Global:TestNested = @{
    Apps = @{
        FileExplorer = @{ Size = 1024; Active = $true }
        Metrics = @{ Size = 2048; Active = $false }
    }
}

$result = Get-MemoryConsumption -VariablePath "TestNested.Apps" -Depth 3
Write-Host "Path: TestNested.Apps"
Write-Host "  Total Objects: $($result.TotalObjects)"
Write-Host "  Total Size: $($result.TotalSize) bytes"

Write-Host "`n=== Test 3: Streaming Callback ===" -ForegroundColor Cyan
$streamMessages = @()
$streamCallback = {
    param($Message)

    $script:streamMessages += $Message

    $type = $Message.type
    switch ($type) {
        'start' {
            Write-Host "  [START] Analysis started at $($Message.timestamp)"
        }
        'progress' {
            Write-Host "  [PROGRESS] $($Message.variable) - $($Message.percentComplete)%"
        }
        'variable' {
            Write-Host "  [VARIABLE] $($Message.name) = $($Message.result.TotalSize) bytes"
        }
        'complete' {
            Write-Host "  [COMPLETE] Analysis finished - $($Message.summary.TotalObjects) objects"
        }
        'error' {
            Write-Host "  [ERROR] $($Message.message)" -ForegroundColor Red
        }
    }
}

$Global:StreamTest = @{ A = 1; B = 2; C = 3 }

$result = Get-MemoryConsumption -VariablePath "StreamTest" -Depth 2 -StreamCallback $streamCallback
Write-Host "  Stream messages received: $($streamMessages.Count)"
Write-Host "  Message types: $($streamMessages.type -join ', ')"

Write-Host "`n=== Test 4: Size Filtering ===" -ForegroundColor Cyan
$Global:SmallData = @{ Tiny = 1 }
$Global:LargeData = @{ Big = 1..1000 }

$result = Get-MemoryConsumption -VariablePath @("SmallData", "LargeData") -MinSize 100 -Depth 3
Write-Host "MinSize: 100 bytes"
Write-Host "  Variables Analyzed: $($result.TotalVariables)"
Write-Host "  Variables Meeting Filter: $($result.Variables.Count)"

foreach ($var in $result.Variables) {
    Write-Host "    $($var.Path) = $($var.TotalSize) bytes"
}

Write-Host "`n=== Test 5: Circular Reference Detection ===" -ForegroundColor Cyan
$Global:Parent = @{ Name = "Parent" }
$Global:Child = @{ Name = "Child"; Parent = $Global:Parent }
$Global:Parent.Child = $Global:Child

$result = Get-MemoryConsumption -VariablePath "Parent" -Depth 5
Write-Host "Variable with circular reference:"
Write-Host "  Total Objects: $($result.TotalObjects)"
Write-Host "  Circular References Detected: $($result.CircularReferences)"
Write-Host "  Total References: $($result.TotalReferences)"

Write-Host "`n=== Test 6: Exclude Patterns ===" -ForegroundColor Cyan
$Global:TestInclude = @{ Data = 123 }
$Global:Host_TestExclude = @{ Data = 456 }  # Should be excluded by Host* pattern

$result = Get-MemoryConsumption -VariablePath "" -Depth 1 -ExcludePatterns @("Host*", "Test*")
Write-Host "Exclude patterns: Host*, Test*"
Write-Host "  Total Variables Analyzed: $($result.TotalVariables)"

$varNames = $result.Variables | ForEach-Object { $_.Path }
Write-Host "  Variables found: $($varNames -join ', ' | Select-Object -First 100)"

Write-Host "`n=== Test 7: Timeout Protection ===" -ForegroundColor Cyan
$Global:DeepNested = @{ L1 = @{ L2 = @{ L3 = @{ L4 = @{ L5 = @{ Data = 1..100 } } } } } }

$result = Get-MemoryConsumption -VariablePath "DeepNested" -Depth 10 -TimeoutSeconds 1 -Verbose
Write-Host "Analysis with 1 second timeout:"
Write-Host "  Timed Out: $($result.TimedOut)"
Write-Host "  Duration: $([math]::Round($result.Duration, 3))s"
Write-Host "  Objects Analyzed: $($result.TotalObjects)"

Write-Host "`n=== Test 8: Assembly Enumeration ===" -ForegroundColor Cyan
$result = Get-MemoryConsumption -VariablePath "TestVar" -Depth 2 -IncludeAssemblies
Write-Host "With assembly enumeration:"
Write-Host "  Assemblies Loaded: $($result.AssemblyCount)"

if ($result.Assemblies) {
    $sampleAssemblies = $result.Assemblies | Select-Object -First 5
    foreach ($asm in $sampleAssemblies) {
        Write-Host "    - $($asm.Name) v$($asm.Version) (GAC: $($asm.IsGAC))"
    }
}

Write-Host "`n=== All Tests Complete ===" -ForegroundColor Green

# Cleanup
Remove-Variable -Name TestVar, TestNested, StreamTest, SmallData, LargeData, Parent, Child, DeepNested -Scope Global -ErrorAction SilentlyContinue
