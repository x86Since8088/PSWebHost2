using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using Microsoft.Diagnostics.Runtime;

namespace MemoryAnalyzer
{
    class Program
    {
        static void Main(string[] args)
        {
            if (args.Length == 0)
            {
                Console.WriteLine("Usage: MemoryAnalyzer <dump_file_path> [options]");
                Console.WriteLine();
                Console.WriteLine("Options:");
                Console.WriteLine("  -top <N>          Show top N types by size (default: 50)");
                Console.WriteLine("  -strings          Analyze string objects and duplicates");
                Console.WriteLine("  -hashtables       Analyze hashtable contents");
                Console.WriteLine("  -large <SizeKB>   Show objects larger than SizeKB (default: 85 for LOH)");
                Console.WriteLine("  -roots <address>  Show GC roots for specific object address");
                Console.WriteLine("  -export <path>    Export detailed analysis to CSV");
                Console.WriteLine();
                Console.WriteLine("Examples:");
                Console.WriteLine("  MemoryAnalyzer dump.dmp -top 20");
                Console.WriteLine("  MemoryAnalyzer dump.dmp -strings -export strings.csv");
                Console.WriteLine("  MemoryAnalyzer dump.dmp -hashtables");
                return;
            }

            string dumpPath = args[0];
            if (!File.Exists(dumpPath))
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"Error: Dump file not found: {dumpPath}");
                Console.ResetColor();
                return;
            }

            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine($"=== PowerShell Memory Dump Analyzer ===");
            Console.WriteLine($"Dump File: {dumpPath}");
            Console.WriteLine($"File Size: {new FileInfo(dumpPath).Length / 1024.0 / 1024.0:F2} MB");
            Console.ResetColor();
            Console.WriteLine();

            try
            {
                using DataTarget dataTarget = DataTarget.LoadDump(dumpPath);

                if (dataTarget.ClrVersions.Length == 0)
                {
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine("Error: No CLR runtime found in dump");
                    Console.ResetColor();
                    return;
                }

                using ClrRuntime runtime = dataTarget.ClrVersions[0].CreateRuntime();

                Console.WriteLine($"CLR Version: {runtime.ClrInfo.Version}");
                Console.WriteLine($"Process: {dataTarget.DataReader.ProcessId}");
                Console.WriteLine();

                // Parse options
                int topCount = 50;
                bool showStrings = false;
                bool showHashtables = false;
                int? largeObjectSizeKB = null;
                ulong? rootAddress = null;
                string? exportPath = null;

                for (int i = 1; i < args.Length; i++)
                {
                    switch (args[i].ToLower())
                    {
                        case "-top":
                            if (i + 1 < args.Length && int.TryParse(args[i + 1], out int n))
                            {
                                topCount = n;
                                i++;
                            }
                            break;
                        case "-strings":
                            showStrings = true;
                            break;
                        case "-hashtables":
                            showHashtables = true;
                            break;
                        case "-large":
                            if (i + 1 < args.Length && int.TryParse(args[i + 1], out int kb))
                            {
                                largeObjectSizeKB = kb;
                                i++;
                            }
                            else
                            {
                                largeObjectSizeKB = 85; // LOH threshold
                            }
                            break;
                        case "-roots":
                            if (i + 1 < args.Length && TryParseHex(args[i + 1], out ulong addr))
                            {
                                rootAddress = addr;
                                i++;
                            }
                            break;
                        case "-export":
                            if (i + 1 < args.Length)
                            {
                                exportPath = args[i + 1];
                                i++;
                            }
                            break;
                    }
                }

                // Analyze heap
                var analyzer = new HeapAnalyzer(runtime);

                // Show overall statistics
                ShowHeapStatistics(runtime);
                Console.WriteLine();

                // Show top types
                var stats = analyzer.GetTypeStatistics(topCount);
                ShowTypeStatistics(stats, topCount);

                // String analysis
                if (showStrings)
                {
                    Console.WriteLine();
                    ShowStringAnalysis(runtime, exportPath);
                }

                // Hashtable analysis
                if (showHashtables)
                {
                    Console.WriteLine();
                    ShowHashtableAnalysis(runtime);
                }

                // Large objects
                if (largeObjectSizeKB.HasValue)
                {
                    Console.WriteLine();
                    ShowLargeObjects(runtime, largeObjectSizeKB.Value);
                }

                // GC roots
                if (rootAddress.HasValue)
                {
                    Console.WriteLine();
                    ShowGCRoots(runtime, rootAddress.Value);
                }

                // Export if requested
                if (!string.IsNullOrEmpty(exportPath))
                {
                    ExportDetailedAnalysis(stats, exportPath);
                }

                Console.WriteLine();
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("Analysis complete!");
                Console.ResetColor();
            }
            catch (Exception ex)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"Error analyzing dump: {ex.Message}");
                Console.WriteLine(ex.StackTrace);
                Console.ResetColor();
            }
        }

        static void ShowHeapStatistics(ClrRuntime runtime)
        {
            var heap = runtime.Heap;

            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine("=== GC Heap Statistics ===");
            Console.ResetColor();

            // Calculate stats by enumerating
            long totalSize = 0;
            long objectCount = 0;
            foreach (var obj in heap.EnumerateObjects())
            {
                totalSize += (long)obj.Size;
                objectCount++;
            }

            Console.WriteLine($"Total Heap Size:     {totalSize / 1024.0 / 1024.0:F2} MB");
            Console.WriteLine($"Number of Objects:   {objectCount:N0}");
            Console.WriteLine($"Number of Segments:  {heap.Segments.Length}");

            // Generation statistics
            long gen0Size = 0, gen1Size = 0, gen2Size = 0, lohSize = 0;
            int gen0Count = 0, gen1Count = 0, gen2Count = 0, lohCount = 0;

            foreach (var obj in heap.EnumerateObjects())
            {
                var segment = heap.GetSegmentByAddress(obj.Address);
                var gen = segment?.Generation ?? 2;
                var size = obj.Size;

                switch (gen)
                {
                    case 0:
                        gen0Size += (long)size;
                        gen0Count++;
                        break;
                    case 1:
                        gen1Size += (long)size;
                        gen1Count++;
                        break;
                    case 2:
                        if (size >= 85000) // LOH threshold
                        {
                            lohSize += (long)size;
                            lohCount++;
                        }
                        else
                        {
                            gen2Size += (long)size;
                            gen2Count++;
                        }
                        break;
                }
            }

            Console.WriteLine();
            Console.WriteLine("Generation Breakdown:");
            Console.WriteLine($"  Gen 0: {gen0Count:N0} objects, {gen0Size / 1024.0 / 1024.0:F2} MB");
            Console.WriteLine($"  Gen 1: {gen1Count:N0} objects, {gen1Size / 1024.0 / 1024.0:F2} MB");
            Console.WriteLine($"  Gen 2: {gen2Count:N0} objects, {gen2Size / 1024.0 / 1024.0:F2} MB");
            Console.WriteLine($"  LOH:   {lohCount:N0} objects, {lohSize / 1024.0 / 1024.0:F2} MB");
        }

        static void ShowTypeStatistics(List<TypeStats> stats, int topCount)
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine($"=== Top {topCount} Types by Total Size ===");
            Console.ResetColor();

            Console.WriteLine("{0,-60} {1,12} {2,15} {3,10}", "Type Name", "Count", "Total Size", "Avg Size");
            Console.WriteLine(new string('-', 100));

            foreach (var stat in stats.Take(topCount))
            {
                var color = stat.TotalSizeMB > 10 ? ConsoleColor.Red :
                           stat.TotalSizeMB > 1 ? ConsoleColor.Yellow :
                           ConsoleColor.White;

                Console.ForegroundColor = color;
                Console.WriteLine("{0,-60} {1,12:N0} {2,12:F2} MB {3,10:N0}",
                    stat.TypeName.Length > 60 ? stat.TypeName.Substring(0, 57) + "..." : stat.TypeName,
                    stat.Count,
                    stat.TotalSizeMB,
                    stat.AverageSizeBytes);
                Console.ResetColor();
            }
        }

        static void ShowStringAnalysis(ClrRuntime runtime, string? exportPath)
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine("=== String Analysis ===");
            Console.ResetColor();

            var stringStats = new Dictionary<string, (int count, long totalSize)>();
            int totalStrings = 0;
            long totalStringSize = 0;

            foreach (var obj in runtime.Heap.EnumerateObjects())
            {
                if (obj.Type?.Name == "System.String")
                {
                    totalStrings++;
                    var size = obj.Size;
                    totalStringSize += (long)size;

                    var strValue = obj.AsString() ?? "<null>";

                    // Limit string length for dictionary key
                    if (strValue.Length > 100)
                        strValue = strValue.Substring(0, 100);

                    if (!stringStats.ContainsKey(strValue))
                        stringStats[strValue] = (0, 0);

                    var current = stringStats[strValue];
                    stringStats[strValue] = (current.count + 1, current.totalSize + (long)size);
                }
            }

            Console.WriteLine($"Total Strings: {totalStrings:N0}");
            Console.WriteLine($"Total Size: {totalStringSize / 1024.0 / 1024.0:F2} MB");
            Console.WriteLine($"Unique Strings: {stringStats.Count:N0}");
            Console.WriteLine($"Duplication Rate: {(1.0 - (double)stringStats.Count / totalStrings) * 100:F2}%");
            Console.WriteLine();

            // Show top duplicates
            Console.WriteLine("Top 20 Duplicated Strings:");
            Console.WriteLine("{0,-50} {1,10} {2,12}", "String Value", "Count", "Size");
            Console.WriteLine(new string('-', 75));

            foreach (var kvp in stringStats.OrderByDescending(x => x.Value.count).Take(20))
            {
                var displayStr = kvp.Key.Length > 50 ? kvp.Key.Substring(0, 47) + "..." : kvp.Key;
                var color = kvp.Value.count > 1000 ? ConsoleColor.Red :
                           kvp.Value.count > 100 ? ConsoleColor.Yellow :
                           ConsoleColor.White;

                Console.ForegroundColor = color;
                Console.WriteLine("{0,-50} {1,10:N0} {2,9:F2} KB",
                    displayStr.Replace("\r", "\\r").Replace("\n", "\\n"),
                    kvp.Value.count,
                    kvp.Value.totalSize / 1024.0);
                Console.ResetColor();
            }
        }

        static void ShowHashtableAnalysis(ClrRuntime runtime)
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine("=== Hashtable Analysis ===");
            Console.ResetColor();

            var hashtables = runtime.Heap.EnumerateObjects()
                .Where(obj => obj.Type?.Name?.Contains("Hashtable") == true)
                .ToList();

            Console.WriteLine($"Total Hashtables: {hashtables.Count:N0}");

            long totalSize = 0;
            var largeHashtables = new List<(ulong address, string typeName, ulong size, int? count)>();

            foreach (var ht in hashtables)
            {
                totalSize += (long)ht.Size;

                // Try to get count
                int? count = null;
                try
                {
                    var countField = ht.Type?.GetFieldByName("count");
                    if (countField != null)
                    {
                        var countValue = countField.Read<int>(ht.Address, false);
                        count = countValue;
                    }
                }
                catch { }

                if (ht.Size > 10240) // > 10KB
                {
                    largeHashtables.Add((ht.Address, ht.Type?.Name ?? "Unknown", ht.Size, count));
                }
            }

            Console.WriteLine($"Total Size: {totalSize / 1024.0 / 1024.0:F2} MB");
            Console.WriteLine($"Average Size: {(hashtables.Count > 0 ? totalSize / hashtables.Count : 0) / 1024.0:F2} KB");
            Console.WriteLine();

            if (largeHashtables.Any())
            {
                Console.WriteLine("Large Hashtables (> 10KB):");
                Console.WriteLine("{0,-18} {1,-50} {2,12} {3,10}", "Address", "Type", "Size", "Count");
                Console.WriteLine(new string('-', 95));

                foreach (var (address, typeName, size, count) in largeHashtables.OrderByDescending(x => x.size).Take(20))
                {
                    Console.ForegroundColor = size > 1024 * 1024 ? ConsoleColor.Red : ConsoleColor.Yellow;
                    Console.WriteLine("{0:X16} {1,-50} {2,9:F2} KB {3,10}",
                        address,
                        typeName.Length > 50 ? typeName.Substring(0, 47) + "..." : typeName,
                        size / 1024.0,
                        count?.ToString("N0") ?? "N/A");
                    Console.ResetColor();
                }
            }
        }

        static void ShowLargeObjects(ClrRuntime runtime, int minSizeKB)
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine($"=== Large Objects (> {minSizeKB}KB) ===");
            Console.ResetColor();

            var largeObjects = runtime.Heap.EnumerateObjects()
                .Where(obj => obj.Size >= (ulong)minSizeKB * 1024)
                .OrderByDescending(obj => obj.Size)
                .Take(50)
                .ToList();

            Console.WriteLine($"Found {largeObjects.Count} objects larger than {minSizeKB}KB");
            Console.WriteLine();

            Console.WriteLine("{0,-18} {1,-50} {2,12} {3,5}", "Address", "Type", "Size", "Gen");
            Console.WriteLine(new string('-', 90));

            foreach (var obj in largeObjects)
            {
                var segment = runtime.Heap.GetSegmentByAddress(obj.Address);
                var gen = segment?.Generation ?? 2;
                var color = obj.Size > 1024 * 1024 ? ConsoleColor.Red : ConsoleColor.Yellow;

                Console.ForegroundColor = color;
                Console.WriteLine("{0:X16} {1,-50} {2,9:F2} KB {3,5}",
                    obj.Address,
                    (obj.Type?.Name ?? "Unknown").Length > 50 ? (obj.Type?.Name ?? "Unknown").Substring(0, 47) + "..." : (obj.Type?.Name ?? "Unknown"),
                    obj.Size / 1024.0,
                    gen);
                Console.ResetColor();
            }
        }

        static void ShowGCRoots(ClrRuntime runtime, ulong address)
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine($"=== GC Roots for Object 0x{address:X} ===");
            Console.ResetColor();

            try
            {
                var obj = runtime.Heap.GetObject(address);
                if (!obj.IsValid)
                {
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine("Invalid object address");
                    Console.ResetColor();
                    return;
                }

                Console.WriteLine($"Object Type: {obj.Type?.Name ?? "Unknown"}");
                Console.WriteLine($"Object Size: {obj.Size:N0} bytes");
                Console.WriteLine();

                Console.WriteLine("Root Paths:");
                var paths = runtime.Heap.EnumerateRoots().Where(root => root.Object == address).ToList();

                if (paths.Any())
                {
                    foreach (var root in paths)
                    {
                        Console.WriteLine($"  {root.RootKind}: {root.Address:X}");
                    }
                }
                else
                {
                    Console.WriteLine("  No direct roots found (object may be reachable through other objects)");
                }
            }
            catch (Exception ex)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"Error finding roots: {ex.Message}");
                Console.ResetColor();
            }
        }

        static void ExportDetailedAnalysis(List<TypeStats> stats, string exportPath)
        {
            Console.WriteLine();
            Console.WriteLine($"Exporting detailed analysis to: {exportPath}");

            var sb = new StringBuilder();
            sb.AppendLine("TypeName,Count,TotalSizeBytes,TotalSizeMB,AverageSizeBytes");

            foreach (var stat in stats)
            {
                sb.AppendLine($"\"{stat.TypeName}\",{stat.Count},{stat.TotalSizeBytes},{stat.TotalSizeMB:F2},{stat.AverageSizeBytes}");
            }

            File.WriteAllText(exportPath, sb.ToString());
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine($"✓ Exported {stats.Count} type statistics");
            Console.ResetColor();
        }

        static bool TryParseHex(string hex, out ulong value)
        {
            hex = hex.Replace("0x", "").Replace("0X", "");
            return ulong.TryParse(hex, System.Globalization.NumberStyles.HexNumber, null, out value);
        }
    }

    class HeapAnalyzer
    {
        private readonly ClrRuntime _runtime;

        public HeapAnalyzer(ClrRuntime runtime)
        {
            _runtime = runtime;
        }

        public List<TypeStats> GetTypeStatistics(int topCount = 50)
        {
            var stats = new Dictionary<string, TypeStats>();

            foreach (var obj in _runtime.Heap.EnumerateObjects())
            {
                var typeName = obj.Type?.Name ?? "Unknown";

                if (!stats.ContainsKey(typeName))
                {
                    stats[typeName] = new TypeStats { TypeName = typeName };
                }

                stats[typeName].Count++;
                stats[typeName].TotalSizeBytes += (long)obj.Size;
            }

            return stats.Values.OrderByDescending(s => s.TotalSizeBytes).ToList();
        }
    }

    class TypeStats
    {
        public string TypeName { get; set; } = "";
        public int Count { get; set; }
        public long TotalSizeBytes { get; set; }
        public double TotalSizeMB => TotalSizeBytes / 1024.0 / 1024.0;
        public long AverageSizeBytes => Count > 0 ? TotalSizeBytes / Count : 0;
    }
}
