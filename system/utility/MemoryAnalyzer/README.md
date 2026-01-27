# Memory Analyzer Tool

A C# command-line tool for analyzing PowerShell memory dumps using ClrMD (Microsoft.Diagnostics.Runtime).

## Features

- **Heap Statistics**: Overall GC heap statistics including generations and LOH
- **Type Analysis**: Shows top types by memory consumption with counts and sizes
- **String Analysis**: Identifies duplicate strings and memory waste
- **Hashtable Analysis**: Deep dive into hashtable objects and their contents
- **Large Object Detection**: Finds objects in the Large Object Heap (LOH)
- **GC Root Tracing**: Shows what's keeping objects alive
- **CSV Export**: Export detailed analysis for further processing

## Building

```powershell
cd C:\SC\PsWebHost\system\utility\MemoryAnalyzer
dotnet build -c Release
```

## Usage

### Basic Analysis
```powershell
.\MemoryAnalyzer.exe dump.dmp
```

### Show Top 20 Types
```powershell
.\MemoryAnalyzer.exe dump.dmp -top 20
```

### Analyze Strings
```powershell
.\MemoryAnalyzer.exe dump.dmp -strings
```

### Analyze Hashtables
```powershell
.\MemoryAnalyzer.exe dump.dmp -hashtables
```

### Find Large Objects
```powershell
# Find objects > 85KB (LOH threshold)
.\MemoryAnalyzer.exe dump.dmp -large 85

# Find objects > 1MB
.\MemoryAnalyzer.exe dump.dmp -large 1024
```

### Find GC Roots
```powershell
.\MemoryAnalyzer.exe dump.dmp -roots 0x00007FF8A1234567
```

### Export to CSV
```powershell
.\MemoryAnalyzer.exe dump.dmp -top 100 -export analysis.csv
```

### Combined Analysis
```powershell
.\MemoryAnalyzer.exe dump.dmp -top 50 -strings -hashtables -large 85 -export full_analysis.csv
```

## Example Output

```
=== PowerShell Memory Dump Analyzer ===
Dump File: pwsh_high_memory.dmp
File Size: 1234.56 MB

CLR Version: 8.0.0
Process: 12345

=== GC Heap Statistics ===
Total Heap Size:     987.65 MB
Number of Objects:   1,234,567
Number of Segments:  15

Generation Breakdown:
  Gen 0: 123,456 objects, 45.67 MB
  Gen 1: 234,567 objects, 89.12 MB
  Gen 2: 876,544 objects, 752.86 MB
  LOH:   1,234 objects, 100.00 MB

=== Top 50 Types by Total Size ===
Type Name                                                    Count      Total Size   Avg Size
----------------------------------------------------------------------------------------------------
System.String                                              456,789       234.56 MB        538
System.Collections.Hashtable                                12,345        98.76 MB      8,192
System.Object[]                                             23,456        87.65 MB      3,824
System.Management.Automation.PSObject                       45,678        54.32 MB      1,216
...

=== String Analysis ===
Total Strings: 456,789
Total Size: 234.56 MB
Unique Strings: 123,456
Duplication Rate: 72.98%

Top 20 Duplicated Strings:
String Value                                       Count        Size
---------------------------------------------------------------------------
                                                  12,345      123.45 KB
\\r\\n                                             8,901       89.01 KB
localhost                                          5,678       56.78 KB
...

=== Hashtable Analysis ===
Total Hashtables: 12,345
Total Size: 98.76 MB
Average Size: 8.19 KB

Large Hashtables (> 10KB):
Address            Type                                               Size     Count
-----------------------------------------------------------------------------------------------
00007FF8A1234567   System.Collections.Hashtable                    1.23 MB     5,678
00007FF8A2345678   System.Collections.Specialized.OrderedDictionary  987.65 KB     3,456
...

=== Large Objects (> 85KB) ===
Found 234 objects larger than 85KB

Address            Type                                               Size   Gen
------------------------------------------------------------------------------------------
00007FF8A3456789   System.Byte[]                                   5.67 MB     2
00007FF8A4567890   System.String                                   2.34 MB     2
...
```

## Integration with PSWebHost

### Automated Analysis Script

```powershell
# Analyze-MemoryDumps.ps1
param(
    [string]$DumpDirectory = "C:\SC\PsWebHost\dumps"
)

$analyzerPath = "C:\SC\PsWebHost\system\utility\MemoryAnalyzer\bin\Release\net8.0\MemoryAnalyzer.exe"

if (-not (Test-Path $analyzerPath)) {
    Write-Host "Building MemoryAnalyzer..." -ForegroundColor Yellow
    Push-Location "C:\SC\PsWebHost\system\utility\MemoryAnalyzer"
    dotnet build -c Release
    Pop-Location
}

$dumps = Get-ChildItem -Path $DumpDirectory -Filter "*.dmp" | Sort-Object LastWriteTime -Descending

foreach ($dump in $dumps) {
    Write-Host "`n=== Analyzing $($dump.Name) ===" -ForegroundColor Cyan

    $outputDir = Join-Path $DumpDirectory "analysis"
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($dump.Name)
    $csvPath = Join-Path $outputDir "${baseName}_analysis.csv"
    $logPath = Join-Path $outputDir "${baseName}_analysis.txt"

    & $analyzerPath $dump.FullName -top 100 -strings -hashtables -large 85 -export $csvPath | Tee-Object -FilePath $logPath

    Write-Host "`nResults saved to:" -ForegroundColor Green
    Write-Host "  CSV: $csvPath" -ForegroundColor Gray
    Write-Host "  Log: $logPath" -ForegroundColor Gray
}
```

## Common Issues and Solutions

### Issue: "No CLR runtime found in dump"
**Solution**: Ensure you're capturing a full dump with `--type Full` option in dotnet-dump

### Issue: "Cannot load Microsoft.Diagnostics.Runtime"
**Solution**: Run `dotnet restore` in the MemoryAnalyzer directory

### Issue: Large dump files (>2GB) fail to load
**Solution**: Increase available memory or analyze on a machine with more RAM

## Advanced Usage

### Finding Memory Leaks

1. **Capture multiple dumps over time**:
```powershell
# Capture dump every 5 minutes
for ($i = 1; $i -le 5; $i++) {
    dotnet-dump collect -p <PID> -o "dump_$i.dmp" --type Full
    Start-Sleep -Seconds 300
}
```

2. **Analyze growth patterns**:
```powershell
# Compare type counts across dumps
.\MemoryAnalyzer.exe dump_1.dmp -export dump1.csv
.\MemoryAnalyzer.exe dump_5.dmp -export dump5.csv

# Use PowerShell to compare
$dump1 = Import-Csv dump1.csv
$dump5 = Import-Csv dump5.csv

# Find types that grew significantly
foreach ($type5 in $dump5) {
    $type1 = $dump1 | Where-Object { $_.TypeName -eq $type5.TypeName }
    if ($type1) {
        $growth = [int]$type5.Count - [int]$type1.Count
        if ($growth -gt 1000) {
            Write-Host "$($type5.TypeName): +$growth objects" -ForegroundColor Yellow
        }
    }
}
```

### Identifying Specific Leaks

1. Find suspicious objects:
```powershell
.\MemoryAnalyzer.exe dump.dmp -top 10
# Note addresses of large hashtables
```

2. Trace roots:
```powershell
.\MemoryAnalyzer.exe dump.dmp -roots 0x00007FF8A1234567
```

3. Look for patterns in type names that suggest PowerShell-specific issues:
   - `System.Management.Automation.Runspaces.*`
   - `System.Management.Automation.PSObject`
   - `System.Collections.Concurrent.ConcurrentDictionary*`

## Performance Tips

- Use `-top 20` instead of default 50 for faster analysis
- Skip `-strings` analysis for very large dumps (>2GB)
- Export to CSV and use Excel/PowerShell for further analysis
- Analyze dumps on a machine with SSD for faster I/O

## See Also

- [MEMORY_ANALYSIS_GUIDE.md](../../../docs/MEMORY_ANALYSIS_GUIDE.md) - Comprehensive memory analysis guide
- [Monitor-AndCaptureDumps.ps1](../Monitor-AndCaptureDumps.ps1) - Automated dump capture script
