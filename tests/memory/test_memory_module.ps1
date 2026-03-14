#Requires -Version 7

# Test script for PSWebHost_MemoryAnalysis module

Import-Module "$PSScriptRoot\..\..\modules\PSWebHost_MemoryAnalysis\PSWebHost_MemoryAnalysis.psd1" -Force

Write-Host "`n=== Test 1: CSV Type Lookup (System.String) ===" -ForegroundColor Cyan
$stringOverhead = Get-TypeMemoryOverhead -TypeName 'System.String'
$stringOverhead | ConvertTo-Json | Write-Host

Write-Host "`n=== Test 2: CSV Type Lookup (System.Collections.Hashtable) ===" -ForegroundColor Cyan
$htOverhead = Get-TypeMemoryOverhead -TypeName 'System.Collections.Hashtable'
$htOverhead | ConvertTo-Json | Write-Host

Write-Host "`n=== Test 3: Runtime Type Measurement (Custom Class) ===" -ForegroundColor Cyan
class TestClass {
    [string]$Name
    [int]$Value
    [datetime]$Created
}
$obj = [TestClass]@{ Name = "Test"; Value = 42; Created = Get-Date }
$customOverhead = Get-TypeMemoryOverhead -Object $obj
$customOverhead | ConvertTo-Json | Write-Host

Write-Host "`n=== Test 4: Estimated Size for String ===" -ForegroundColor Cyan
$str = "Hello, World!"
$strSize = Get-ObjectEstimatedSize -Object $str
Write-Host "String: '$str' (Length: $($str.Length) chars)"
$strSize | ConvertTo-Json | Write-Host

Write-Host "`n=== Test 5: Estimated Size for Hashtable ===" -ForegroundColor Cyan
$ht = @{ a = 1; b = 2; c = 3; d = 4; e = 5 }
$htSize = Get-ObjectEstimatedSize -Object $ht
Write-Host "Hashtable with $($ht.Count) entries"
$htSize | ConvertTo-Json -Depth 3 | Write-Host

Write-Host "`n=== Test 6: Estimated Size for Array ===" -ForegroundColor Cyan
$arr = 1..10
$arrSize = Get-ObjectEstimatedSize -Object $arr
Write-Host "Array with $($arr.Count) elements"
$arrSize | ConvertTo-Json -Depth 3 | Write-Host

Write-Host "`n=== All Tests Complete ===" -ForegroundColor Green
