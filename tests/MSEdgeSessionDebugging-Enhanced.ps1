#Requires -Version 7

<#
.SYNOPSIS
    Enhanced MSEdge debugging session for testing web elements and JavaScript modifications
.DESCRIPTION
    Extends the base MSEdgeSessionDebugging.ps1 with:
    - Console.log forwarding to PowerShell
    - JavaScript evaluation and injection
    - DOM element inspection and modification
    - Screenshot capture
    - Performance timing
    - Interactive testing mode
.PARAMETER Url
    The URL to test (defaults to http://localhost:8888)
.PARAMETER Interactive
    Enable interactive mode for manual testing
.PARAMETER CaptureHAR
    Enable HAR file capture (network traffic)
.PARAMETER ForwardConsole
    Enable console.log forwarding from browser to PowerShell
.EXAMPLE
    .\MSEdgeSessionDebugging-Enhanced.ps1 -Url "http://localhost:8888" -Interactive
.EXAMPLE
    .\MSEdgeSessionDebugging-Enhanced.ps1 -Url "http://localhost:8888/apps/uplot/api/v1/ui/elements/bar-chart?chartId=test1" -ForwardConsole
#>

param(
    [string]$Url = "http://localhost:8888",
    [switch]$Interactive,
    [switch]$CaptureHAR,
    [switch]$ForwardConsole = $true,
    [int]$DebugPort = 9222,
    [int]$TimeoutMinutes = 30
)

# ==========================
# Helper Functions
# ==========================

function Send-WebSocketMessage {
    param([System.Net.WebSockets.ClientWebSocket]$Client, [string]$Message)
    Write-Verbose "[WS Send] $Message"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
    $segment = [System.ArraySegment[byte]]::new($bytes)
    $Client.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).Wait()
}

function Receive-WebSocketMessage {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Client,
        [int]$TimeoutMs = 5000
    )

    $buffer = New-Object byte[] 65536
    $segment = [System.ArraySegment[byte]]::new($buffer)
    $ms = New-Object System.IO.MemoryStream

    $cts = [System.Threading.CancellationTokenSource]::new($TimeoutMs)

    try {
        do {
            $task = $Client.ReceiveAsync($segment, $cts.Token)
            $result = $task.Result

            if ($result.Count -gt 0) {
                $ms.Write($buffer, 0, $result.Count)
            }

            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                return $null
            }
        } while (-not $result.EndOfMessage)

        $data = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
        return $data
    }
    catch {
        return $null
    }
    finally {
        $cts.Dispose()
    }
}

# CDP Command ID tracker
$script:cdpId = 1000

function Invoke-CDP {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Client,
        [string]$Method,
        [hashtable]$Params = @{}
    )

    $script:cdpId++
    $command = @{
        id     = $script:cdpId
        method = $Method
        params = $Params
    } | ConvertTo-Json -Compress -Depth 10

    Write-Verbose "[CDP] $Method"
    Send-WebSocketMessage -Client $Client -Message $command

    # Wait for response
    $timeout = [DateTime]::Now.AddSeconds(10)
    while ([DateTime]::Now -lt $timeout) {
        $response = Receive-WebSocketMessage -Client $Client -TimeoutMs 1000

        if ($response) {
            try {
                $obj = $response | ConvertFrom-Json

                # Handle console messages
                if ($obj.method -eq 'Runtime.consoleAPICalled') {
                    Handle-ConsoleMessage -Message $obj
                    continue
                }

                # Handle exceptions
                if ($obj.method -eq 'Runtime.exceptionThrown') {
                    Handle-Exception -Message $obj
                    continue
                }

                # Handle our response
                if ($obj.id -eq $script:cdpId) {
                    if ($obj.error) {
                        Write-Warning "[CDP Error] $($obj.error.message)"
                        return $null
                    }
                    return $obj.result
                }

                # Store other notifications for processing
                if ($obj.method) {
                    $script:PendingNotifications.Add($obj) | Out-Null
                }
            }
            catch {
                Write-Verbose "[CDP] Parse error: $_"
            }
        }
    }

    return $null
}

function Handle-ConsoleMessage {
    param($Message)

    $params = $Message.params
    $type = $params.type
    $args = $params.args

    $output = @()
    foreach ($arg in $args) {
        if ($arg.type -eq 'string') {
            $output += $arg.value
        }
        elseif ($arg.type -eq 'number') {
            $output += $arg.value
        }
        elseif ($arg.type -eq 'object') {
            $output += ($arg | ConvertTo-Json -Compress)
        }
        else {
            $output += $arg.description
        }
    }

    $text = $output -join ' '

    switch ($type) {
        'log' { Write-Host "[Browser Log] $text" -ForegroundColor Gray }
        'info' { Write-Host "[Browser Info] $text" -ForegroundColor Cyan }
        'warning' { Write-Host "[Browser Warning] $text" -ForegroundColor Yellow }
        'error' { Write-Host "[Browser Error] $text" -ForegroundColor Red }
        default { Write-Host "[Browser $type] $text" -ForegroundColor White }
    }
}

function Handle-Exception {
    param($Message)

    $details = $Message.params.exceptionDetails
    $text = $details.exception.description
    $line = $details.lineNumber
    $col = $details.columnNumber
    $url = $details.url

    Write-Host "[Browser Exception] $text at $url`:$line`:$col" -ForegroundColor Red
}

# ==========================
# Testing Helpers
# ==========================

function Invoke-JavaScript {
    param(
        [Parameter(Mandatory)]
        [string]$Script,
        [switch]$ReturnByValue
    )

    $params = @{
        expression    = $Script
        returnByValue = $ReturnByValue.IsPresent
    }

    $result = Invoke-CDP -Client $script:wsClient -Method 'Runtime.evaluate' -Params $params

    if ($result.exceptionDetails) {
        Write-Warning "JavaScript Error: $($result.exceptionDetails.exception.description)"
        return $null
    }

    if ($ReturnByValue) {
        return $result.result.value
    }
    else {
        return $result.result
    }
}

function Get-DOMElement {
    param(
        [Parameter(Mandatory)]
        [string]$Selector
    )

    $js = "document.querySelector('$Selector')"
    return Invoke-JavaScript -Script $js
}

function Set-ElementAttribute {
    param(
        [Parameter(Mandatory)]
        [string]$Selector,
        [Parameter(Mandatory)]
        [string]$Attribute,
        [Parameter(Mandatory)]
        [string]$Value
    )

    $js = "document.querySelector('$Selector')?.setAttribute('$Attribute', '$Value')"
    return Invoke-JavaScript -Script $js -ReturnByValue
}

function Get-ElementText {
    param(
        [Parameter(Mandatory)]
        [string]$Selector
    )

    $js = "document.querySelector('$Selector')?.textContent"
    return Invoke-JavaScript -Script $js -ReturnByValue
}

function Click-Element {
    param(
        [Parameter(Mandatory)]
        [string]$Selector
    )

    $js = "document.querySelector('$Selector')?.click()"
    return Invoke-JavaScript -Script $js -ReturnByValue
}

function Take-Screenshot {
    param(
        [string]$OutputPath
    )

    $result = Invoke-CDP -Client $script:wsClient -Method 'Page.captureScreenshot' -Params @{
        format  = 'png'
        quality = 90
    }

    if ($result.data) {
        if ($OutputPath) {
            $bytes = [Convert]::FromBase64String($result.data)
            [IO.File]::WriteAllBytes($OutputPath, $bytes)
            Write-Host "Screenshot saved: $OutputPath" -ForegroundColor Green
        }
        return $result.data
    }

    return $null
}

function Get-PerformanceMetrics {
    $js = @'
(function() {
    const perf = performance.getEntriesByType('navigation')[0];
    return {
        domContentLoaded: perf.domContentLoadedEventEnd - perf.domContentLoadedEventStart,
        loadComplete: perf.loadEventEnd - perf.loadEventStart,
        domInteractive: perf.domInteractive - perf.fetchStart,
        totalTime: perf.loadEventEnd - perf.fetchStart
    };
})()
'@

    return Invoke-JavaScript -Script $js -ReturnByValue
}

function Test-ElementExists {
    param(
        [Parameter(Mandatory)]
        [string]$Selector
    )

    $js = "document.querySelector('$Selector') !== null"
    return Invoke-JavaScript -Script $js -ReturnByValue
}

function Wait-ForElement {
    param(
        [Parameter(Mandatory)]
        [string]$Selector,
        [int]$TimeoutSeconds = 30
    )

    $deadline = [DateTime]::Now.AddSeconds($TimeoutSeconds)

    while ([DateTime]::Now -lt $deadline) {
        if (Test-ElementExists -Selector $Selector) {
            Write-Host "Element found: $Selector" -ForegroundColor Green
            return $true
        }
        Start-Sleep -Milliseconds 100
    }

    Write-Warning "Timeout waiting for element: $Selector"
    return $false
}

function Get-AllConsoleMessages {
    return $script:ConsoleMessages
}

function Clear-ConsoleMessages {
    $script:ConsoleMessages = @()
}

# ==========================
# Interactive Mode
# ==========================

function Start-InteractiveSession {
    Write-Host "`n=== Interactive Testing Mode ===" -ForegroundColor Cyan
    Write-Host "Available commands:" -ForegroundColor Yellow
    Write-Host "  eval <js>          - Evaluate JavaScript"
    Write-Host "  click <selector>   - Click element"
    Write-Host "  text <selector>    - Get element text"
    Write-Host "  exists <selector>  - Check if element exists"
    Write-Host "  wait <selector>    - Wait for element"
    Write-Host "  screenshot [path]  - Take screenshot"
    Write-Host "  perf               - Show performance metrics"
    Write-Host "  reload             - Reload page"
    Write-Host "  console            - Show console messages"
    Write-Host "  exit               - Exit interactive mode"
    Write-Host ""

    while ($true) {
        $input = Read-Host "Test"

        if ([string]::IsNullOrWhiteSpace($input)) {
            continue
        }

        $parts = $input -split '\s+', 2
        $command = $parts[0].ToLower()
        $arg = if ($parts.Length -gt 1) { $parts[1] } else { $null }

        switch ($command) {
            'exit' { return }
            'eval' {
                if ($arg) {
                    $result = Invoke-JavaScript -Script $arg -ReturnByValue
                    Write-Host "Result: $($result | ConvertTo-Json)" -ForegroundColor Green
                }
            }
            'click' {
                if ($arg) {
                    Click-Element -Selector $arg
                    Write-Host "Clicked: $arg" -ForegroundColor Green
                }
            }
            'text' {
                if ($arg) {
                    $text = Get-ElementText -Selector $arg
                    Write-Host "Text: $text" -ForegroundColor Green
                }
            }
            'exists' {
                if ($arg) {
                    $exists = Test-ElementExists -Selector $arg
                    Write-Host "Exists: $exists" -ForegroundColor $(if ($exists) { 'Green' } else { 'Red' })
                }
            }
            'wait' {
                if ($arg) {
                    Wait-ForElement -Selector $arg
                }
            }
            'screenshot' {
                $path = if ($arg) { $arg } else { "screenshot_$(Get-Date -Format 'yyyyMMdd_HHmmss').png" }
                Take-Screenshot -OutputPath $path
            }
            'perf' {
                $metrics = Get-PerformanceMetrics
                Write-Host ($metrics | ConvertTo-Json) -ForegroundColor Cyan
            }
            'reload' {
                Invoke-CDP -Client $script:wsClient -Method 'Page.reload' -Params @{} | Out-Null
                Write-Host "Page reloaded" -ForegroundColor Green
            }
            'console' {
                $messages = Get-AllConsoleMessages
                $messages | ForEach-Object { Write-Host $_ }
            }
            default {
                Write-Host "Unknown command: $command" -ForegroundColor Yellow
            }
        }
    }
}

# ==========================
# Main Execution
# ==========================

Write-Host "`n=== MSEdge Testing Session ===" -ForegroundColor Cyan
Write-Host "URL: $Url" -ForegroundColor White
Write-Host "Debug Port: $DebugPort" -ForegroundColor White
Write-Host ""

# Initialize storage
$script:ConsoleMessages = @()
$script:PendingNotifications = [System.Collections.ArrayList]::new()

# Launch Edge
$edgePath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edgePath)) {
    $edgePath = "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
}

$tempProfile = Join-Path $env:TEMP "EdgeProfile_$([guid]::NewGuid())"
Write-Host "Launching Edge with debugging on port $DebugPort..." -ForegroundColor Yellow

$proc = Start-Process -FilePath $edgePath `
    -ArgumentList @(
    "--new-window",
    "--remote-debugging-port=$DebugPort",
    "--user-data-dir=$tempProfile",
    $Url
) `
    -PassThru

Write-Host "Edge launched (PID: $($proc.Id))" -ForegroundColor Green

# Wait for debugging endpoint
Start-Sleep -Seconds 2

# Find page target
$pageTarget = $null
for ($i = 0; $i -lt 20 -and -not $pageTarget; $i++) {
    try {
        $targets = Invoke-RestMethod -Uri "http://localhost:$DebugPort/json" -TimeoutSec 3
        $pageTarget = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
    }
    catch {
        Start-Sleep -Milliseconds 500
    }
}

if (-not $pageTarget) {
    Write-Error "Failed to find page target"
    Stop-Process -Id $proc.Id -Force
    exit 1
}

$wsUrl = $pageTarget.webSocketDebuggerUrl
Write-Host "WebSocket URL: $wsUrl" -ForegroundColor Cyan

# Connect WebSocket
$script:wsClient = [System.Net.WebSockets.ClientWebSocket]::new()
$script:wsClient.ConnectAsync([System.Uri]$wsUrl, [Threading.CancellationToken]::None).Wait()
Write-Host "WebSocket connected" -ForegroundColor Green

# Enable Runtime domain for console and JavaScript execution
Invoke-CDP -Client $script:wsClient -Method 'Runtime.enable' -Params @{} | Out-Null
Write-Host "Runtime domain enabled" -ForegroundColor Green

# Enable Page domain for screenshots and navigation
Invoke-CDP -Client $script:wsClient -Method 'Page.enable' -Params @{} | Out-Null
Write-Host "Page domain enabled" -ForegroundColor Green

# Enable DOM domain
Invoke-CDP -Client $script:wsClient -Method 'DOM.enable' -Params @{} | Out-Null
Write-Host "DOM domain enabled" -ForegroundColor Green

# Enable Network if HAR capture requested
if ($CaptureHAR) {
    Invoke-CDP -Client $script:wsClient -Method 'Network.enable' -Params @{} | Out-Null
    Write-Host "Network domain enabled (HAR capture)" -ForegroundColor Green
}

Write-Host "`nSession ready!" -ForegroundColor Green

# Start interactive mode or automated testing
if ($Interactive) {
    Start-InteractiveSession
}
else {
    # Run automated test example
    Write-Host "`nRunning automated tests..." -ForegroundColor Cyan

    # Example: Wait for page load
    Start-Sleep -Seconds 2

    # Example: Check for specific element
    $hasCard = Test-ElementExists -Selector '.card'
    Write-Host "Has .card element: $hasCard" -ForegroundColor $(if ($hasCard) { 'Green' } else { 'Yellow' })

    # Example: Get performance metrics
    $perf = Get-PerformanceMetrics
    Write-Host "Performance Metrics:" -ForegroundColor Cyan
    Write-Host ($perf | ConvertTo-Json) -ForegroundColor White

    # Keep session alive
    Write-Host "`nSession active. Press Ctrl+C to exit." -ForegroundColor Yellow

    $deadline = [DateTime]::Now.AddMinutes($TimeoutMinutes)
    while ([DateTime]::Now -lt $deadline -and !$proc.HasExited) {
        # Process pending notifications
        Start-Sleep -Milliseconds 100

        # Drain any pending messages
        try {
            $msg = Receive-WebSocketMessage -Client $script:wsClient -TimeoutMs 100
            if ($msg) {
                $obj = $msg | ConvertFrom-Json

                if ($obj.method -eq 'Runtime.consoleAPICalled') {
                    Handle-ConsoleMessage -Message $obj
                }
                elseif ($obj.method -eq 'Runtime.exceptionThrown') {
                    Handle-Exception -Message $obj
                }
            }
        }
        catch {
            # Ignore timeout
        }
    }
}

# Cleanup
Write-Host "`nClosing session..." -ForegroundColor Yellow
$script:wsClient.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "Session ended", [Threading.CancellationToken]::None).Wait()
$script:wsClient.Dispose()

Write-Host "Session closed." -ForegroundColor Green
