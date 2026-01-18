#Requires -Version 7

<#
.SYNOPSIS
    Analyzes PSWebHost codebase to identify component dependencies and extractability

.DESCRIPTION
    Scans all .ps1, .psm1, and .js files to identify:
    - Import-Module calls
    - Core function usage
    - Database access patterns
    - Global variable references
    - External dependencies
    - Function-level dependencies using AST parsing

    Generates an extractability score and per-function dependency mappings.

.PARAMETER Path
    Root path to analyze. Defaults to project root.

.PARAMETER OutputFormat
    Output format: Table, CSV, JSON. Default: Table

.PARAMETER ExportPath
    Path to export results (for CSV/JSON formats)

.PARAMETER FunctionLevel
    Enable function-level AST analysis. Default: $true

.PARAMETER IncludeJavaScript
    Include JavaScript file analysis. Default: $true

.EXAMPLE
    .\Analyze-Dependencies.ps1
    Analyzes entire project with function-level dependencies

.EXAMPLE
    .\Analyze-Dependencies.ps1 -OutputFormat JSON -ExportPath "analysis.json"
    Exports full dependency analysis to JSON
#>

param(
    [string]$Path,
    [ValidateSet('Table', 'CSV', 'JSON')]
    [string]$OutputFormat = 'Table',
    [string]$ExportPath,
    [switch]$FunctionLevel = $true,
    [switch]$IncludeJavaScript = $true
)

# Determine project root
if (-not $Path) {
    $Path = $PSScriptRoot -replace '[/\\]system[/\\].*'
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PSWebHost Dependency Analyzer (Enhanced)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "Analyzing: $Path" -ForegroundColor Gray
Write-Host "Function-level analysis: $($FunctionLevel.IsPresent)" -ForegroundColor Gray
Write-Host "Include JavaScript: $($IncludeJavaScript.IsPresent)" -ForegroundColor Gray
Write-Host ""

# Define core framework components
$CoreFunctions = @(
    # PSWebHost_Support
    'Process-HttpRequest', 'context_response', 'Get-RequestBody', 'Resolve-RouteScriptPath',
    'New-PSWebHostResult', 'Validate-UserSession', 'Sync-SessionStateToDatabase',
    'Get-PSWebSessions', 'ConvertTo-CompressedBase64',

    # PSWebHost_Authentication
    'Get-LoginSession', 'Set-LoginSession', 'Remove-LoginSession',
    'Get-PSWebHostUser', 'New-PSWebHostUser', 'Register-PSWebHostUser',
    'Add-PSWebHostRole', 'Get-PSWebHostRole', 'Add-PSWebHostGroup',
    'PSWebLogon', 'Test-Authentication_API_Key_Bearer',
    'Protect-String', 'Unprotect-String', 'Test-LoginLockout',
    'Get-CardSettings', 'Set-CardSettings',

    # PSWebHost_Database
    'Get-PSWebSQLiteData', 'Invoke-PSWebSQLiteNonQuery', 'Sanitize-SqlQueryString',
    'Get-PSWebUser', 'Set-PSWebUser', 'Set-PSWebHostRole',

    # Logging
    'Write-PSWebHostLog', 'Get-PSWebHostErrorReport',
    'Start-PSWebHostEvent', 'Complete-PSWebHostEvent',

    # Formatters
    'Convert-ObjectToYaml', 'Inspect-Object', 'New-JsonResponse', 'Get-ObjectSafeWalk',

    # Sanitization
    'Sanitize-*'
)

$CoreModules = @(
    'PSWebHost_Support',
    'PSWebHost_Authentication',
    'PSWebHost_Database',
    'PSWebHost_Logging',
    'PSWebHost_Formatters',
    'PSWebHost_Users',
    'Sanitization',
    'PSWebHost_Metrics'
)

# Function to parse PowerShell AST and extract function definitions
function Get-PowerShellFunctions {
    param(
        [string]$FilePath
    )

    try {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$null, [ref]$null)

        # Find all function definitions
        $functions = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true)

        $result = @()

        foreach ($func in $functions) {
            $functionName = $func.Name

            # Find all command calls within this function
            $commands = $func.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst]
            }, $true)

            $calledFunctions = @()
            foreach ($cmd in $commands) {
                $cmdName = $cmd.GetCommandName()
                if ($cmdName) {
                    $calledFunctions += $cmdName
                }
            }

            # Find variable references
            $variables = $func.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.VariableExpressionAst]
            }, $true)

            $variableRefs = @()
            foreach ($var in $variables) {
                $varPath = $var.VariablePath.UserPath
                if ($varPath -match '^Global:') {
                    $variableRefs += $varPath
                }
            }

            # Find parameters
            $parameters = @()
            if ($func.Parameters) {
                $parameters = $func.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }
            }

            $result += [PSCustomObject]@{
                FunctionName = $functionName
                StartLine = $func.Extent.StartLineNumber
                EndLine = $func.Extent.EndLineNumber
                Parameters = $parameters
                CalledFunctions = ($calledFunctions | Select-Object -Unique)
                GlobalVariables = ($variableRefs | Select-Object -Unique)
                LineCount = $func.Extent.EndLineNumber - $func.Extent.StartLineNumber + 1
            }
        }

        return $result

    } catch {
        Write-Warning "AST parsing failed for $FilePath : $_"
        return @()
    }
}

# Function to parse JavaScript and extract function definitions
function Get-JavaScriptFunctions {
    param(
        [string]$FilePath
    )

    try {
        $content = Get-Content $FilePath -Raw

        $result = @()

        # Pattern 1: function name() { }
        $functionMatches = [regex]::Matches($content, 'function\s+(\w+)\s*\(([^)]*)\)\s*\{')
        foreach ($match in $functionMatches) {
            $functionName = $match.Groups[1].Value
            $params = $match.Groups[2].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }

            # Find function calls within this function (basic approach)
            # We'll look for patterns like functionName(...) after the function definition
            $functionStart = $match.Index

            # Try to find the matching closing brace (simplified - may not work for nested functions)
            $braceCount = 0
            $functionEnd = $functionStart
            $inFunction = $false

            for ($i = $functionStart; $i -lt $content.Length; $i++) {
                if ($content[$i] -eq '{') {
                    $braceCount++
                    $inFunction = $true
                } elseif ($content[$i] -eq '}') {
                    $braceCount--
                    if ($inFunction -and $braceCount -eq 0) {
                        $functionEnd = $i
                        break
                    }
                }
            }

            $functionBody = $content.Substring($functionStart, $functionEnd - $functionStart + 1)

            # Find function calls in body
            $callMatches = [regex]::Matches($functionBody, '(\w+)\s*\(')
            $calledFunctions = $callMatches | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

            # Find fetch/API calls
            $fetchCalls = [regex]::Matches($functionBody, 'fetch\s*\([''"`]([^''"`]+)[''"`]')
            $apiCalls = $fetchCalls | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

            $result += [PSCustomObject]@{
                FunctionName = $functionName
                Type = 'Function'
                Parameters = $params
                CalledFunctions = $calledFunctions
                APICalls = $apiCalls
            }
        }

        # Pattern 2: const name = () => { }
        $arrowMatches = [regex]::Matches($content, '(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?\([^)]*\)\s*=>')
        foreach ($match in $arrowMatches) {
            $functionName = $match.Groups[1].Value
            $result += [PSCustomObject]@{
                FunctionName = $functionName
                Type = 'ArrowFunction'
                Parameters = @()
                CalledFunctions = @()
                APICalls = @()
            }
        }

        # Pattern 3: Class methods
        $methodMatches = [regex]::Matches($content, '(?:async\s+)?(\w+)\s*\([^)]*\)\s*\{', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        foreach ($match in $methodMatches) {
            $methodName = $match.Groups[1].Value
            # Filter out keywords
            if ($methodName -notin @('function', 'if', 'for', 'while', 'switch', 'catch')) {
                $result += [PSCustomObject]@{
                    FunctionName = $methodName
                    Type = 'Method'
                    Parameters = @()
                    CalledFunctions = @()
                    APICalls = @()
                }
            }
        }

        return $result

    } catch {
        Write-Warning "JavaScript parsing failed for $FilePath : $_"
        return @()
    }
}

# Scan all PowerShell and JavaScript files
Write-Host "[1/5] Scanning for files..." -ForegroundColor Yellow

$includePatterns = @('*.ps1', '*.psm1')
if ($IncludeJavaScript) {
    $includePatterns += '*.js'
}

$allFiles = Get-ChildItem -Path $Path -Recurse -Include $includePatterns -ErrorAction SilentlyContinue |
    Where-Object {
        $_.FullName -notmatch '\\\.git\\' -and
        $_.FullName -notmatch '\\node_modules\\' -and
        $_.FullName -notmatch '\\public\\lib\\' -and  # Exclude external libraries
        $_.FullName -notmatch '\.min\.js$'  # Exclude minified files
    }

Write-Host "  Found $($allFiles.Count) files" -ForegroundColor Gray
Write-Host ""

# Analyze each file
Write-Host "[2/5] Analyzing file-level dependencies..." -ForegroundColor Yellow
$results = @()
$functionMappings = @{}
$current = 0

foreach ($file in $allFiles) {
    $current++
    if ($current % 50 -eq 0) {
        Write-Host "  Progress: $current/$($allFiles.Count)" -ForegroundColor Gray
    }

    try {
        $content = Get-Content $file.FullName -Raw -ErrorAction Stop
        $relativePath = $file.FullName.Substring($Path.Length + 1)
        $fileExtension = $file.Extension.ToLower()

        # Determine component type
        $componentType = 'Unknown'
        if ($relativePath -match '^routes[/\\]') { $componentType = 'Route' }
        elseif ($relativePath -match '^public[/\\]elements[/\\]') { $componentType = 'UIElement' }
        elseif ($relativePath -match '^modules[/\\]') { $componentType = 'Module' }
        elseif ($relativePath -match '^system[/\\]') { $componentType = 'System' }
        elseif ($relativePath -match '^apps[/\\]([^/\\]+)') {
            $componentType = 'App'
            $appName = $matches[1]
        }
        elseif ($relativePath -match '^tests[/\\]') { $componentType = 'Test' }

        # Find Import-Module calls (PowerShell only)
        $importedModules = @()
        if ($fileExtension -in @('.ps1', '.psm1')) {
            if ($content -match 'Import-Module') {
                $imports = [regex]::Matches($content, 'Import-Module\s+([^\s\r\n;]+)')
                foreach ($import in $imports) {
                    $moduleName = $import.Groups[1].Value -replace '[''"]'
                    $importedModules += $moduleName
                }
            }
        }

        # Find core function usage
        $coreUsage = @()
        foreach ($func in $CoreFunctions) {
            if ($func -like '*-*') {
                $pattern = $func -replace '\*', '\\w+'
                if ($content -match $pattern) {
                    $matches = [regex]::Matches($content, $pattern)
                    $coreUsage += $matches | ForEach-Object { $_.Value } | Select-Object -Unique
                }
            } else {
                if ($content -match "\b$func\b") {
                    $coreUsage += $func
                }
            }
        }

        # Find database access
        $dbAccess = @()
        $dbPatterns = @(
            'Get-PSWebSQLiteData',
            'Invoke-PSWebSQLiteNonQuery',
            'Invoke-PSWebSQLiteQuery',
            'Get-PSWebUser',
            'Set-PSWebUser'
        )
        foreach ($pattern in $dbPatterns) {
            if ($content -match "\b$pattern\b") {
                $dbAccess += $pattern
            }
        }

        # Find global variable usage
        $globalRefs = @()
        $globalMatches = [regex]::Matches($content, '\$Global:PSWebServer\.([^\s\r\n;.()]+)')
        foreach ($match in $globalMatches) {
            $globalRefs += $match.Groups[1].Value
        }

        # Find external tool usage
        $externalTools = @()
        $toolPatterns = @(
            'docker', 'kubectl', 'systemctl', 'sc.exe', 'schtasks',
            'mysql', 'redis-cli', 'sqlcmd', 'wsl', 'crontab', 'vault'
        )
        foreach ($tool in $toolPatterns) {
            if ($content -match "\b$tool\b") {
                $externalTools += $tool
            }
        }

        # Find URL references
        $urlReferences = @()
        $urlPatterns = @(
            "(?:fetch|psweb_fetchWithAuthHandling|openCard)\s*\(\s*['\`"]([/a-zA-Z0-9_\-\.]+)['\`"]",
            "(?:Invoke-RestMethod|Invoke-WebRequest).*?-Uri\s+['\`"]([^'\`"]+)['\`"]",
            "url\s*[:=]\s*['\`"]([/a-zA-Z0-9_\-\.]+)['\`"]",
            "href\s*=\s*['\`"]([/a-zA-Z0-9_\-\.]+)['\`"]"
        )
        foreach ($pattern in $urlPatterns) {
            $matches = [regex]::Matches($content, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            foreach ($match in $matches) {
                $url = $match.Groups[1].Value
                if ($url -match '^/' -and $url -notmatch '^//(http|https)' -and $url -ne '/') {
                    $urlReferences += $url
                }
            }
        }
        $urlReferences = $urlReferences | Select-Object -Unique

        # Find data path references
        $dataPathRefs = @()
        $dataPathPatterns = @(
            '\$(?:AppRoot|appRoot)[/\\]data',
            'Join-Path.*?[''"]data[''"]',
            '/apps/[^/]+/data',
            '\\apps\\[^\\]+\\data'
        )
        foreach ($pattern in $dataPathPatterns) {
            if ($content -match $pattern) {
                $dataPathRefs += $pattern
            }
        }

        # Calculate extractability score
        $score = 100
        $score -= ($coreUsage.Count * 3)
        $score -= ($dbAccess.Count * 5)
        $score -= ($globalRefs.Count * 2)
        $score -= ($importedModules | Where-Object { $_ -in $CoreModules }).Count * 10

        if ($externalTools.Count -gt 0) { $score += 10 }
        if ($componentType -eq 'UIElement') { $score += 5 }
        if ($dataPathRefs.Count -gt 0) { $score -= 5 }  # Data path refs make migration needed

        if ($score -lt 0) { $score = 0 }
        if ($score -gt 100) { $score = 100 }

        $recommendation = 'Unknown'
        if ($score -ge 80) { $recommendation = 'Easy - Extract' }
        elseif ($score -ge 60) { $recommendation = 'Medium - Review' }
        elseif ($score -ge 40) { $recommendation = 'Hard - Careful' }
        else { $recommendation = 'Keep in Core' }

        $results += [PSCustomObject]@{
            FilePath = $relativePath
            FileExtension = $fileExtension
            ComponentType = $componentType
            AppName = $appName ?? ''
            ExtractabilityScore = $score
            Recommendation = $recommendation
            CoreFunctionsUsed = ($coreUsage -join ', ')
            CoreFunctionCount = $coreUsage.Count
            DatabaseAccess = ($dbAccess -join ', ')
            DatabaseAccessCount = $dbAccess.Count
            ImportedModules = ($importedModules -join ', ')
            GlobalReferences = ($globalRefs -join ', ')
            GlobalRefCount = $globalRefs.Count
            ExternalTools = ($externalTools -join ', ')
            ExternalToolCount = $externalTools.Count
            URLReferences = ($urlReferences -join ', ')
            URLReferenceCount = $urlReferences.Count
            DataPathReferences = ($dataPathRefs -join ', ')
            DataPathRefCount = $dataPathRefs.Count
        }

    } catch {
        Write-Warning "Error analyzing $($file.FullName): $($_.Exception.Message)"
    }
}

Write-Host "  File-level analysis complete" -ForegroundColor Green
Write-Host ""

# Function-level analysis
if ($FunctionLevel) {
    Write-Host "[3/5] Performing function-level AST analysis..." -ForegroundColor Yellow

    $functionResults = @()
    $current = 0

    foreach ($file in $allFiles) {
        $current++
        if ($current % 50 -eq 0) {
            Write-Host "  Progress: $current/$($allFiles.Count)" -ForegroundColor Gray
        }

        $relativePath = $file.FullName.Substring($Path.Length + 1)
        $fileExtension = $file.Extension.ToLower()

        try {
            if ($fileExtension -in @('.ps1', '.psm1')) {
                $functions = Get-PowerShellFunctions -FilePath $file.FullName

                foreach ($func in $functions) {
                    $functionResults += [PSCustomObject]@{
                        FilePath = $relativePath
                        Language = 'PowerShell'
                        FunctionName = $func.FunctionName
                        FunctionType = 'Function'
                        StartLine = $func.StartLine
                        EndLine = $func.EndLine
                        LineCount = $func.LineCount
                        Parameters = ($func.Parameters -join ', ')
                        ParameterCount = $func.Parameters.Count
                        CalledFunctions = ($func.CalledFunctions -join ', ')
                        CalledFunctionCount = $func.CalledFunctions.Count
                        GlobalVariables = ($func.GlobalVariables -join ', ')
                        GlobalVariableCount = $func.GlobalVariables.Count
                        APICalls = ''
                        APICallCount = 0
                    }
                }

                # Store function mapping
                if ($functions.Count -gt 0) {
                    $functionMappings[$relativePath] = $functions
                }

            } elseif ($fileExtension -eq '.js' -and $IncludeJavaScript) {
                $functions = Get-JavaScriptFunctions -FilePath $file.FullName

                foreach ($func in $functions) {
                    $functionResults += [PSCustomObject]@{
                        FilePath = $relativePath
                        Language = 'JavaScript'
                        FunctionName = $func.FunctionName
                        FunctionType = $func.Type
                        StartLine = 0
                        EndLine = 0
                        LineCount = 0
                        Parameters = ($func.Parameters -join ', ')
                        ParameterCount = $func.Parameters.Count
                        CalledFunctions = ($func.CalledFunctions -join ', ')
                        CalledFunctionCount = $func.CalledFunctions.Count
                        GlobalVariables = ''
                        GlobalVariableCount = 0
                        APICalls = ($func.APICalls -join ', ')
                        APICallCount = $func.APICalls.Count
                    }
                }

                if ($functions.Count -gt 0) {
                    $functionMappings[$relativePath] = $functions
                }
            }

        } catch {
            Write-Warning "Function analysis failed for $relativePath : $_"
        }
    }

    Write-Host "  Function-level analysis complete" -ForegroundColor Green
    Write-Host "  Found $($functionResults.Count) functions across $($functionMappings.Count) files" -ForegroundColor Gray
    Write-Host ""
} else {
    $functionResults = @()
}

# Generate summary statistics
Write-Host "[4/5] Generating statistics..." -ForegroundColor Yellow

$summary = @{
    GeneratedAt = Get-Date -Format 'o'
    ProjectPath = $Path
    TotalFiles = $results.Count
    TotalFunctions = $functionResults.Count
    PowerShellFiles = ($results | Where-Object { $_.FileExtension -in @('.ps1', '.psm1') }).Count
    JavaScriptFiles = ($results | Where-Object { $_.FileExtension -eq '.js' }).Count
    ByType = $results | Group-Object ComponentType | ForEach-Object { @{$_.Name = $_.Count} }
    ByRecommendation = $results | Group-Object Recommendation | ForEach-Object { @{$_.Name = $_.Count} }
    HighlyExtractable = ($results | Where-Object { $_.ExtractabilityScore -ge 80 }).Count
    MediumExtractable = ($results | Where-Object { $_.ExtractabilityScore -ge 60 -and $_.ExtractabilityScore -lt 80 }).Count
    LowExtractable = ($results | Where-Object { $_.ExtractabilityScore -lt 60 }).Count
    FilesWithDataPaths = ($results | Where-Object { $_.DataPathRefCount -gt 0 }).Count
    AppsNeedingDataMigration = ($results | Where-Object { $_.ComponentType -eq 'App' -and $_.DataPathRefCount -gt 0 } | Select-Object -ExpandProperty AppName -Unique).Count
}

Write-Host ""
Write-Host "=== Summary Statistics ===" -ForegroundColor Cyan
Write-Host "Total files analyzed: $($summary.TotalFiles)" -ForegroundColor White
Write-Host "  PowerShell: $($summary.PowerShellFiles)" -ForegroundColor Gray
Write-Host "  JavaScript: $($summary.JavaScriptFiles)" -ForegroundColor Gray
Write-Host "Total functions: $($summary.TotalFunctions)" -ForegroundColor White
Write-Host ""
Write-Host "Extractability:" -ForegroundColor Yellow
Write-Host "  Easy (80-100):   $($summary.HighlyExtractable) files" -ForegroundColor Green
Write-Host "  Medium (60-79):  $($summary.MediumExtractable) files" -ForegroundColor Yellow
Write-Host "  Difficult (<60): $($summary.LowExtractable) files" -ForegroundColor Red
Write-Host ""
Write-Host "Data Migration Needed:" -ForegroundColor Yellow
Write-Host "  Files with data paths: $($summary.FilesWithDataPaths)" -ForegroundColor White
Write-Host "  Apps needing migration: $($summary.AppsNeedingDataMigration)" -ForegroundColor White
Write-Host ""

# Output results
Write-Host "[5/5] Outputting results..." -ForegroundColor Yellow

# Always save JSON to PsWebHost_Data\system\utility\
$jsonOutputPath = Join-Path $Path "PsWebHost_Data\system\utility\Analyze-Dependencies.json"
$jsonOutputDir = Split-Path $jsonOutputPath -Parent
if (-not (Test-Path $jsonOutputDir)) {
    New-Item -Path $jsonOutputDir -ItemType Directory -Force | Out-Null
}

$jsonOutput = @{
    GeneratedAt = Get-Date -Format 'o'
    ProjectPath = $Path
    Summary = $summary
    FileResults = $results
    FunctionResults = $functionResults
    FunctionMappings = $functionMappings
}
$jsonOutput | ConvertTo-Json -Depth 10 | Out-File $jsonOutputPath -Encoding UTF8
Write-Host "  Saved JSON data: $jsonOutputPath" -ForegroundColor Green

# Save function mappings separately for easier access
$functionMapPath = Join-Path $Path "PsWebHost_Data\system\utility\Function-Mappings.json"
@{
    GeneratedAt = Get-Date -Format 'o'
    FunctionMappings = $functionMappings
    FunctionResults = $functionResults
} | ConvertTo-Json -Depth 10 | Out-File $functionMapPath -Encoding UTF8
Write-Host "  Saved function mappings: $functionMapPath" -ForegroundColor Green

switch ($OutputFormat) {
    'Table' {
        # Show top extractable candidates
        Write-Host ""
        Write-Host "=== Top 20 Extraction Candidates ===" -ForegroundColor Cyan
        $results |
            Where-Object { $_.ComponentType -ne 'Test' -and $_.ComponentType -ne 'Unknown' } |
            Sort-Object ExtractabilityScore -Descending |
            Select-Object -First 20 |
            Format-Table FilePath, ComponentType, ExtractabilityScore, Recommendation -AutoSize

        # Show files needing data migration
        Write-Host ""
        Write-Host "=== Files Needing Data Path Migration ===" -ForegroundColor Cyan
        $results |
            Where-Object { $_.DataPathRefCount -gt 0 } |
            Sort-Object AppName, FilePath |
            Format-Table AppName, FilePath, DataPathRefCount -AutoSize

        # Show platform-specific components
        Write-Host ""
        Write-Host "=== Platform-Specific Components (External Tools) ===" -ForegroundColor Cyan
        $results |
            Where-Object { $_.ExternalToolCount -gt 0 } |
            Sort-Object ExtractabilityScore -Descending |
            Format-Table FilePath, ExternalTools, ExtractabilityScore -AutoSize

        # Show function statistics
        if ($FunctionLevel -and $functionResults.Count -gt 0) {
            Write-Host ""
            Write-Host "=== Top 15 Complex Functions ===" -ForegroundColor Cyan
            $functionResults |
                Sort-Object CalledFunctionCount -Descending |
                Select-Object -First 15 |
                Format-Table FilePath, FunctionName, CalledFunctionCount, LineCount -AutoSize

            Write-Host ""
            Write-Host "=== Functions with Most Global Variables ===" -ForegroundColor Cyan
            $functionResults |
                Where-Object { $_.GlobalVariableCount -gt 0 } |
                Sort-Object GlobalVariableCount -Descending |
                Select-Object -First 10 |
                Format-Table FilePath, FunctionName, GlobalVariableCount, GlobalVariables -AutoSize -Wrap
        }
    }

    'CSV' {
        if (-not $ExportPath) {
            $ExportPath = Join-Path $Path "dependency-analysis.csv"
        }
        $results | Export-Csv -Path $ExportPath -NoTypeInformation
        Write-Host "  Exported file results to: $ExportPath" -ForegroundColor Green

        if ($FunctionLevel) {
            $functionCsvPath = $ExportPath -replace '\.csv$', '-functions.csv'
            $functionResults | Export-Csv -Path $functionCsvPath -NoTypeInformation
            Write-Host "  Exported function results to: $functionCsvPath" -ForegroundColor Green
        }
    }

    'JSON' {
        if ($ExportPath) {
            $jsonOutput | ConvertTo-Json -Depth 10 | Out-File $ExportPath -Encoding UTF8
            Write-Host "  Exported JSON to: $ExportPath" -ForegroundColor Green
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Analysis Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Return results for scripting
return @{
    FileResults = $results
    FunctionResults = $functionResults
    FunctionMappings = $functionMappings
    Summary = $summary
}
