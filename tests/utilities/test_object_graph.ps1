#Requires -Version 7

# Test script for Measure-ObjectGraph function

Import-Module "$PSScriptRoot\..\..\modules\PSWebHost_MemoryAnalysis\PSWebHost_MemoryAnalysis.psd1" -Force

Write-Host "`n=== Test 1: Simple String ===" -ForegroundColor Cyan
$str = "Hello, World!"
$result = Measure-ObjectGraph -RootObject $str -Path "TestString" -MaxDepth 1
Write-Host "String: '$str'"
Write-Host "  Base: $($result.BaseSize) bytes"
Write-Host "  Content: $($result.ContentSize) bytes ($($ result.ItemCount) chars)"
Write-Host "  Total: $($result.TotalSize) bytes"
Write-Host "  Object ID: $($result.ObjectId)"

Write-Host "`n=== Test 2: Simple Hashtable ===" -ForegroundColor Cyan
$ht = @{ Name = "Test"; Value = 42; Active = $true }
$result = Measure-ObjectGraph -RootObject $ht -Path "TestHashtable" -MaxDepth 2
Write-Host "Hashtable with $($ht.Count) entries"
Write-Host "  Base: $($result.BaseSize) bytes"
Write-Host "  Content: $($result.ContentSize) bytes"
Write-Host "  Total: $($result.TotalSize) bytes"
Write-Host "  Children: $($result.Children.Count)"

Write-Host "`n=== Test 3: Shared Reference (Same object twice) ===" -ForegroundColor Cyan
$sharedObject = @{ Data = "Shared" }
$container = @{
    First = $sharedObject
    Second = $sharedObject
}

$seen = @{}
$chain = [System.Collections.Generic.Stack[int]]::new()
$result = Measure-ObjectGraph -RootObject $container -Path "Container" -MaxDepth 3 `
                               -SeenObjects $seen -ParentChain $chain

Write-Host "Container with 2 references to same object"
Write-Host "  Children: $($result.Children.Count)"

$firstChild = $result.Children[0]
$secondChild = $result.Children[1]

Write-Host "  First child:"
Write-Host "    Path: $($firstChild.Path)"
Write-Host "    IsReference: $($firstChild.IsReference)"
Write-Host "    TotalSize: $($firstChild.TotalSize) bytes"

if ($result.Children.Count -gt 1) {
    Write-Host "  Second child:"
    Write-Host "    Path: $($secondChild.Path)"
    Write-Host "    IsReference: $($secondChild.IsReference)"
    Write-Host "    ReferenceOverhead: $($secondChild.ReferenceOverhead) bytes"
    Write-Host "    OriginalPath: $($secondChild.OriginalPath)"
}

Write-Host "  Seen objects: $($seen.Count)"
foreach ($key in $seen.Keys) {
    Write-Host "    ID $key : RefCount = $($seen[$key].RefCount), Path = $($seen[$key].Path)"
}

Write-Host "`n=== Test 4: Circular Reference ===" -ForegroundColor Cyan
$parent = @{ Name = "Parent" }
$child = @{ Name = "Child"; Parent = $parent }
$parent.Child = $child  # Create circular reference

$seen = @{}
$chain = [System.Collections.Generic.Stack[int]]::new()
$result = Measure-ObjectGraph -RootObject $parent -Path "Parent" -MaxDepth 5 `
                               -SeenObjects $seen -ParentChain $chain

Write-Host "Parent object with circular reference to child"
Write-Host "  Total size: $($result.TotalSize) bytes"
Write-Host "  Children: $($result.Children.Count)"

# Find the circular reference
function Find-CircularRef {
    param($Node)

    if ($Node.IsCircular) {
        return $Node
    }

    foreach ($child in $Node.Children) {
        $circ = Find-CircularRef -Node $child
        if ($circ) { return $circ }
    }

    return $null
}

$circular = Find-CircularRef -Node $result
if ($circular) {
    Write-Host "  Circular reference detected:"
    Write-Host "    Path: $($circular.Path)"
    Write-Host "    IsCircular: $($circular.IsCircular)"
    Write-Host "    Type: $($circular.Type)"
}

Write-Host "`n=== Test 5: Array of Objects ===" -ForegroundColor Cyan
$arr = @(
    @{ ID = 1; Name = "First" },
    @{ ID = 2; Name = "Second" },
    @{ ID = 3; Name = "Third" }
)

$result = Measure-ObjectGraph -RootObject $arr -Path "Array" -MaxDepth 3
Write-Host "Array with $($arr.Count) hashtable elements"
Write-Host "  Base: $($result.BaseSize) bytes"
Write-Host "  Content: $($result.ContentSize) bytes"
Write-Host "  Total: $($result.TotalSize) bytes"
Write-Host "  Children: $($result.Children.Count)"
Write-Host "  Children total size: $($result.ChildrenTotalSize) bytes"

Write-Host "`n=== Test 6: Max Depth Limiting ===" -ForegroundColor Cyan
$deep = @{ L1 = @{ L2 = @{ L3 = @{ L4 = @{ L5 = @{ L6 = "Deep" } } } } } }

$result = Measure-ObjectGraph -RootObject $deep -Path "Deep" -MaxDepth 3
Write-Host "Deeply nested object (depth limited to 3)"
Write-Host "  Total size: $($result.TotalSize) bytes"
Write-Host "  MaxDepthReached: $($result.MaxDepthReached)"

# Count actual depth reached
function Get-MaxDepth {
    param($Node, $CurrentDepth = 0)

    if ($Node.Children.Count -eq 0) {
        return $CurrentDepth
    }

    $maxChildDepth = $CurrentDepth
    foreach ($child in $Node.Children) {
        $childDepth = Get-MaxDepth -Node $child -CurrentDepth ($CurrentDepth + 1)
        if ($childDepth -gt $maxChildDepth) {
            $maxChildDepth = $childDepth
        }
    }

    return $maxChildDepth
}

$actualDepth = Get-MaxDepth -Node $result
Write-Host "  Actual depth traversed: $actualDepth"

Write-Host "`n=== Test 7: Streaming Callback ===" -ForegroundColor Cyan
$streamCount = 0
$streamCallback = {
    param($Result)
    $script:streamCount++
    if ($script:streamCount -le 5) {
        Write-Host "  Stream [$script:streamCount]: $($Result.Path) = $($Result.TotalSize) bytes (Type: $($Result.Type))"
    }
}

$testObj = @{
    App1 = @{ Name = "FileExplorer"; Size = 1024 }
    App2 = @{ Name = "Metrics"; Size = 2048 }
    App3 = @{ Name = "TaskManager"; Size = 512 }
}

$result = Measure-ObjectGraph -RootObject $testObj -Path "Apps" -MaxDepth 3 `
                               -StreamCallback $streamCallback

Write-Host "  Total stream callbacks: $streamCount"
Write-Host "  Total size measured: $($result.TotalSize) bytes"

Write-Host "`n=== All Tests Complete ===" -ForegroundColor Green
