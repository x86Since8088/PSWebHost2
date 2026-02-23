<#
.SYNOPSIS
    Generates interactive HTML test report

.DESCRIPTION
    Creates a comprehensive HTML report from Test-AllDebugCards results.
    Includes color-coded status, expandable test details, performance charts,
    and filterable results.

.PARAMETER TestRun
    Test run object from Test-AllDebugCards

.PARAMETER OutputPath
    Optional path to save HTML file (if not specified, returns HTML string)

.EXAMPLE
    $testRun = Test-AllDebugCards
    New-DebugTestReport -TestRun $testRun -OutputPath "C:\Reports\test.html"

.EXAMPLE
    $html = New-DebugTestReport -TestRun $testRun
    $html | Out-File "report.html"

.OUTPUTS
    Returns HTML string
#>
[CmdletBinding()]
param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TestRun,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath
    )

    $MyTag = '[New-DebugTestReport]'

    try {
        Write-Verbose "$MyTag Generating HTML report..."

        # Calculate statistics
        $totalCards = $TestRun.TotalCards
        $passed = $TestRun.Passed
        $warnings = $TestRun.Warnings
        $failed = $TestRun.Failed
        $passRate = if ($totalCards -gt 0) { [math]::Round(($passed / $totalCards) * 100, 1) } else { 0 }

        # Generate HTML
        $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PSWebHost Card Test Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            min-height: 100vh;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: #fff;
            border-radius: 12px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: #fff;
            padding: 30px;
            text-align: center;
        }
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        .header .subtitle {
            font-size: 1.1em;
            opacity: 0.9;
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            padding: 30px;
            background: #f8f9fa;
            border-bottom: 2px solid #e0e0e0;
        }
        .stat-card {
            background: #fff;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            text-align: center;
            transition: transform 0.2s;
        }
        .stat-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
        }
        .stat-card .value {
            font-size: 2.5em;
            font-weight: bold;
            margin-bottom: 5px;
        }
        .stat-card .label {
            color: #666;
            font-size: 0.9em;
            text-transform: uppercase;
        }
        .stat-card.passed .value { color: #28a745; }
        .stat-card.warnings .value { color: #ffc107; }
        .stat-card.failed .value { color: #dc3545; }
        .stat-card.total .value { color: #007bff; }
        .filters {
            padding: 20px 30px;
            background: #fff;
            border-bottom: 1px solid #e0e0e0;
            display: flex;
            gap: 15px;
            flex-wrap: wrap;
            align-items: center;
        }
        .filters label {
            font-weight: 600;
            color: #333;
        }
        .filters select, .filters input {
            padding: 8px 12px;
            border: 1px solid #ccc;
            border-radius: 4px;
            font-size: 0.95em;
        }
        .results {
            padding: 30px;
        }
        .result-item {
            background: #fff;
            border: 1px solid #e0e0e0;
            border-left: 4px solid #ccc;
            border-radius: 6px;
            margin-bottom: 15px;
            overflow: hidden;
            transition: all 0.3s;
        }
        .result-item.pass { border-left-color: #28a745; }
        .result-item.warn { border-left-color: #ffc107; }
        .result-item.fail { border-left-color: #dc3545; }
        .result-item:hover {
            box-shadow: 0 4px 12px rgba(0,0,0,0.1);
        }
        .result-header {
            padding: 15px 20px;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: space-between;
            background: #f8f9fa;
        }
        .result-header:hover {
            background: #e9ecef;
        }
        .result-title {
            font-weight: 600;
            font-size: 1.1em;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .status-badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 0.85em;
            font-weight: bold;
            text-transform: uppercase;
        }
        .status-badge.pass {
            background: #d4edda;
            color: #155724;
        }
        .status-badge.warn {
            background: #fff3cd;
            color: #856404;
        }
        .status-badge.fail {
            background: #f8d7da;
            color: #721c24;
        }
        .result-meta {
            font-size: 0.9em;
            color: #666;
        }
        .result-details {
            padding: 20px;
            display: none;
            border-top: 1px solid #e0e0e0;
            background: #fff;
        }
        .result-details.expanded {
            display: block;
        }
        .test-list {
            margin-top: 10px;
        }
        .test-item {
            padding: 8px 12px;
            margin: 5px 0;
            background: #f8f9fa;
            border-radius: 4px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .test-item .test-name {
            font-weight: 500;
        }
        .test-status {
            padding: 2px 8px;
            border-radius: 8px;
            font-size: 0.85em;
            font-weight: bold;
        }
        .test-status.pass {
            background: #d4edda;
            color: #155724;
        }
        .test-status.fail {
            background: #f8d7da;
            color: #721c24;
        }
        .test-status.warn {
            background: #fff3cd;
            color: #856404;
        }
        .metrics {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 10px;
            margin-top: 15px;
        }
        .metric {
            background: #f0f0f0;
            padding: 10px;
            border-radius: 4px;
            text-align: center;
        }
        .metric .metric-value {
            font-size: 1.3em;
            font-weight: bold;
            color: #333;
        }
        .metric .metric-label {
            font-size: 0.85em;
            color: #666;
            margin-top: 5px;
        }
        .errors, .warnings {
            margin-top: 15px;
        }
        .error-item, .warning-item {
            padding: 8px 12px;
            margin: 5px 0;
            border-radius: 4px;
            font-family: 'Consolas', 'Monaco', monospace;
            font-size: 0.9em;
        }
        .error-item {
            background: #f8d7da;
            color: #721c24;
            border-left: 3px solid #dc3545;
        }
        .warning-item {
            background: #fff3cd;
            color: #856404;
            border-left: 3px solid #ffc107;
        }
        .footer {
            padding: 20px 30px;
            background: #f8f9fa;
            text-align: center;
            color: #666;
            font-size: 0.9em;
            border-top: 1px solid #e0e0e0;
        }
        .expand-icon {
            transition: transform 0.3s;
        }
        .expand-icon.expanded {
            transform: rotate(180deg);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>PSWebHost Card Test Report</h1>
            <div class="subtitle">Generated on $(Get-Date -Format 'dddd, MMMM dd, yyyy HH:mm:ss')</div>
        </div>

        <div class="stats">
            <div class="stat-card total">
                <div class="value">$totalCards</div>
                <div class="label">Total Cards</div>
            </div>
            <div class="stat-card passed">
                <div class="value">$passed</div>
                <div class="label">Passed</div>
            </div>
            <div class="stat-card warnings">
                <div class="value">$warnings</div>
                <div class="label">Warnings</div>
            </div>
            <div class="stat-card failed">
                <div class="value">$failed</div>
                <div class="label">Failed</div>
            </div>
            <div class="stat-card">
                <div class="value" style="color: #6c757d;">$passRate%</div>
                <div class="label">Pass Rate</div>
            </div>
            <div class="stat-card">
                <div class="value" style="color: #6c757d;">$([math]::Round($TestRun.Duration, 2))s</div>
                <div class="label">Duration</div>
            </div>
        </div>

        <div class="filters">
            <label>Filter by Status:</label>
            <select id="statusFilter" onchange="filterResults()">
                <option value="all">All</option>
                <option value="fail">Failed Only</option>
                <option value="warn">Warnings Only</option>
                <option value="pass">Passed Only</option>
            </select>

            <label>Search:</label>
            <input type="text" id="searchInput" placeholder="Card name..." oninput="filterResults()">

            <button onclick="expandAll()" style="padding: 8px 16px; background: #007bff; color: #fff; border: none; border-radius: 4px; cursor: pointer;">
                Expand All
            </button>
            <button onclick="collapseAll()" style="padding: 8px 16px; background: #6c757d; color: #fff; border: none; border-radius: 4px; cursor: pointer;">
                Collapse All
            </button>
        </div>

        <div class="results">
"@

        # Generate result items
        foreach ($result in $TestRun.Results) {
            $status = $result.Status.ToLower()
            $cardName = $result.CardName -replace '"', '&quot;'
            $duration = [math]::Round($result.Duration, 2)

            $html += @"
            <div class="result-item $status" data-status="$status" data-name="$cardName">
                <div class="result-header" onclick="toggleDetails(this)">
                    <div class="result-title">
                        <span class="status-badge $status">$($result.Status)</span>
                        <span>$cardName</span>
                    </div>
                    <div class="result-meta">
                        <span>$($result.AppName)</span> |
                        <span>${duration}s</span>
                        <span class="expand-icon">▼</span>
                    </div>
                </div>
                <div class="result-details">
                    <h4>Test Details</h4>
                    <div class="test-list">
"@

            # Add test items
            foreach ($test in $result.Tests) {
                $testStatus = $test.Result.ToLower()
                $testDuration = if ($test.Duration) { " ($([math]::Round($test.Duration, 2))s)" } else { "" }

                $html += @"
                        <div class="test-item">
                            <span class="test-name">$($test.Name)$testDuration</span>
                            <span class="test-status $testStatus">$($test.Result)</span>
                        </div>
"@
            }

            $html += "</div>"

            # Add metrics
            if ($result.Metrics -and $result.Metrics.Count -gt 0) {
                $html += @"
                    <h4 style="margin-top: 20px;">Metrics</h4>
                    <div class="metrics">
"@

                foreach ($metricKey in $result.Metrics.Keys) {
                    $metricValue = $result.Metrics[$metricKey]
                    if ($metricValue -is [hashtable]) {
                        $metricValue = ($metricValue.Keys | ForEach-Object { "$_`: $($metricValue[$_])" }) -join ", "
                    }

                    $html += @"
                        <div class="metric">
                            <div class="metric-value">$metricValue</div>
                            <div class="metric-label">$metricKey</div>
                        </div>
"@
                }

                $html += "</div>"
            }

            # Add errors
            if ($result.Errors -and $result.Errors.Count -gt 0) {
                $html += @"
                    <div class="errors">
                        <h4>Errors</h4>
"@
                foreach ($error in $result.Errors) {
                    $html += "<div class='error-item'>$($error -replace '<', '&lt;' -replace '>', '&gt;')</div>"
                }
                $html += "</div>"
            }

            # Add warnings
            if ($result.Warnings -and $result.Warnings.Count -gt 0) {
                $html += @"
                    <div class="warnings">
                        <h4>Warnings</h4>
"@
                foreach ($warning in $result.Warnings) {
                    $html += "<div class='warning-item'>$($warning -replace '<', '&lt;' -replace '>', '&gt;')</div>"
                }
                $html += "</div>"
            }

            $html += @"
                </div>
            </div>
"@
        }

        # Close HTML
        $html += @"
        </div>

        <div class="footer">
            PSWebHost Comprehensive Card Testing Framework v1.0<br>
            Generated by New-DebugTestReport
        </div>
    </div>

    <script>
        function toggleDetails(header) {
            const details = header.nextElementSibling;
            const icon = header.querySelector('.expand-icon');
            details.classList.toggle('expanded');
            icon.classList.toggle('expanded');
        }

        function expandAll() {
            document.querySelectorAll('.result-details').forEach(el => {
                el.classList.add('expanded');
                el.previousElementSibling.querySelector('.expand-icon').classList.add('expanded');
            });
        }

        function collapseAll() {
            document.querySelectorAll('.result-details').forEach(el => {
                el.classList.remove('expanded');
                el.previousElementSibling.querySelector('.expand-icon').classList.remove('expanded');
            });
        }

        function filterResults() {
            const statusFilter = document.getElementById('statusFilter').value;
            const searchTerm = document.getElementById('searchInput').value.toLowerCase();

            document.querySelectorAll('.result-item').forEach(item => {
                const status = item.getAttribute('data-status');
                const name = item.getAttribute('data-name').toLowerCase();

                const statusMatch = statusFilter === 'all' || status === statusFilter;
                const searchMatch = searchTerm === '' || name.includes(searchTerm);

                item.style.display = (statusMatch && searchMatch) ? 'block' : 'none';
            });
        }
    </script>
</body>
</html>
"@

    # Save if path specified
    if ($OutputPath) {
        $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
        Write-Verbose "$MyTag Report saved to: $OutputPath"
    }

    return $html

} catch {
    Write-Error "$MyTag Failed to generate report: $_"
    throw
}
