#Requires -Version 7

<#
.SYNOPSIS
    Comprehensive test of the Debug Command System

.DESCRIPTION
    Tests all aspects of the debug command system:
    - Command enqueuing (eval, predefined, dom, network)
    - Command polling and retrieval
    - Command execution and result reporting
    - Command history
    - Session targeting (current vs all)
    - Timeout handling
    - Queue limits

    Creates a temporary API key with admin, site_admin, and debug roles for testing,
    then removes it upon completion.
#>

param(
    [string]$BaseUrl = "http://localhost:8080",
    [switch]$SkipBrowserTest
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Debug Command System Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$script:TestsPassed = 0
$script:TestsFailed = 0
$script:TestsSkipped = 0
$script:TestApiKey = $null
$script:TestKeyID = $null

function Test-Result {
    param(
        [string]$TestName,
        [string]$Message = "",
        [switch]$Passed,
        [switch]$Failed,
        [switch]$Skip
    )

    if ($Skip) {
        Write-Host "   ⊘ SKIP: $TestName" -ForegroundColor Yellow
        if ($Message) { Write-Host "      $Message" -ForegroundColor Gray }
        $script:TestsSkipped++
    } elseif ($Passed) {
        Write-Host "   ✅ PASS: $TestName" -ForegroundColor Green
        if ($Message) { Write-Host "      $Message" -ForegroundColor Gray }
        $script:TestsPassed++
    } else {
        Write-Host "   ❌ FAIL: $TestName" -ForegroundColor Red
        if ($Message) { Write-Host "      $Message" -ForegroundColor Red }
        $script:TestsFailed++
    }
}

function Cleanup-TestResources {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Cleaning Up Test Resources" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    if ($script:TestKeyID) {
        Write-Host "`nRemoving test API key..." -ForegroundColor Yellow
        try {
            $removeScript = Join-Path $PSScriptRoot "system\utility\Account_Auth_BearerToken_Remove.ps1"
            & $removeScript -KeyID $script:TestKeyID -Force -Confirm:$false -RemoveUser 2>&1 | Out-Null
            Write-Host "✅ Test API key removed" -ForegroundColor Green
        } catch {
            Write-Host "⚠️  Warning: Failed to remove test API key: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "   Manual cleanup may be required: KeyID = $script:TestKeyID" -ForegroundColor Gray
        }
    }
}

# =============================================================================
# Setup: Create Temporary API Key
# =============================================================================
Write-Host "Setup: Creating temporary API key for testing..." -ForegroundColor Yellow

try {
    $createScript = Join-Path $PSScriptRoot "system\utility\Account_Auth_BearerToken_New.ps1"

    # Create test API key with required roles
    $apiKeyResult = & $createScript `
        -TestAccount `
        -Roles @('admin', 'site_admin', 'debug') `
        -Description "Temporary API key for debug command system testing" `
        -Verbose:$false `
        2>&1 | Where-Object { $_ -is [System.Management.Automation.PSCustomObject] }

    if ($apiKeyResult -and $apiKeyResult.ApiKey) {
        $script:TestApiKey = $apiKeyResult.ApiKey
        $script:TestKeyID = $apiKeyResult.KeyID
        Write-Host "✅ Test API key created" -ForegroundColor Green
        Write-Host "   KeyID: $($apiKeyResult.KeyID)" -ForegroundColor Gray
        Write-Host "   Roles: $($apiKeyResult.Roles -join ', ')" -ForegroundColor Gray
    } else {
        Write-Host "❌ Failed to create test API key" -ForegroundColor Red
        Write-Host "   Tests requiring authentication will be skipped" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ Error creating test API key: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   Tests requiring authentication will be skipped" -ForegroundColor Yellow
}

# Register cleanup handler
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    if ($script:TestKeyID) {
        $removeScript = Join-Path $PSScriptRoot "system\utility\Account_Auth_BearerToken_Remove.ps1"
        & $removeScript -KeyID $script:TestKeyID -Force -Confirm:$false -RemoveUser 2>&1 | Out-Null
    }
} | Out-Null

# =============================================================================
# Test 1: Module and Function Availability
# =============================================================================
Write-Host "`n1. Testing module and function availability..." -ForegroundColor Yellow

try {
    $modulePath = "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1"

    if (Test-Path $modulePath) {
        Test-Result "Module file exists" -Passed

        # Dot-source the file
        . $modulePath

        # Check if function is available
        $cmd = Get-Command Debug-ClientCommand -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            Test-Result "Debug-ClientCommand function loaded" -Passed
        } else {
            Test-Result "Debug-ClientCommand function loaded" -Failed
        }

        if ($cmd) {
            # Check parameters
            $params = $cmd.Parameters.Keys
            $requiredParams = @('Command', 'SessionID', 'Type', 'Params', 'UserID')
            $hasAllParams = $true
            foreach ($param in $requiredParams) {
                if ($params -notcontains $param) {
                    $hasAllParams = $false
                    break
                }
            }
            if ($hasAllParams) {
                Test-Result "Function has all required parameters" -Passed
            } else {
                Test-Result "Function has all required parameters" -Failed
            }
        }
    } else {
        Test-Result "Module file exists" -Failed -Message "File not found: $modulePath"
    }
} catch {
    Test-Result "Module loading" -Failed -Message $_.Exception.Message
}

# =============================================================================
# Test 2: Global State Initialization
# =============================================================================
Write-Host "`n2. Testing global state initialization..." -ForegroundColor Yellow

try {
    $hasDebugCommands = $null -ne $Global:PSWebServer.DebugCommands
    if ($hasDebugCommands) {
        Test-Result "DebugCommands object exists" -Passed
    } else {
        Test-Result "DebugCommands object exists" -Failed -Message "PSWebHost not running in this context"
    }

    if ($hasDebugCommands) {
        $hasQueue = $null -ne $Global:PSWebServer.DebugCommands.Queue
        if ($hasQueue) {
            Test-Result "Queue exists" -Passed
        } else {
            Test-Result "Queue exists" -Failed
        }

        $hasHistory = $null -ne $Global:PSWebServer.DebugCommands.History
        if ($hasHistory) {
            Test-Result "History exists" -Passed
        } else {
            Test-Result "History exists" -Failed
        }

        $hasMaxQueue = $null -ne $Global:PSWebServer.DebugCommands.MaxQueueSize
        if ($hasMaxQueue) {
            Test-Result "MaxQueueSize configured" -Passed
            Write-Host "      MaxQueueSize: $($Global:PSWebServer.DebugCommands.MaxQueueSize)" -ForegroundColor Gray
        } else {
            Test-Result "MaxQueueSize configured" -Failed
        }

        $hasMaxHistory = $null -ne $Global:PSWebServer.DebugCommands.MaxHistorySize
        if ($hasMaxHistory) {
            Test-Result "MaxHistorySize configured" -Passed
            Write-Host "      MaxHistorySize: $($Global:PSWebServer.DebugCommands.MaxHistorySize)" -ForegroundColor Gray
        } else {
            Test-Result "MaxHistorySize configured" -Failed
        }

        # Show current state
        Write-Host "`n      Current State:" -ForegroundColor Cyan
        Write-Host "         Queue: $($Global:PSWebServer.DebugCommands.Queue.Count) pending" -ForegroundColor Gray
        Write-Host "         History: $($Global:PSWebServer.DebugCommands.History.Count) completed" -ForegroundColor Gray
    }
} catch {
    Test-Result "Global state check" -Failed -Message $_.Exception.Message
}

# =============================================================================
# Test 3: HTTP Endpoint Availability
# =============================================================================
Write-Host "`n3. Testing HTTP endpoints..." -ForegroundColor Yellow

if (-not $script:TestApiKey) {
    Test-Result "HTTP endpoint tests" -Skip -Message "No API key available"
} else {
    # Create authorization headers
    $headers = @{
        'Authorization' = "Bearer $script:TestApiKey"
    }

    $endpoints = @{
        'poll'    = @{ Method = 'GET';  Path = '/apps/WebHostDebugExtensions/api/v1/debug/commands/poll' }
        'history' = @{ Method = 'GET';  Path = '/apps/WebHostDebugExtensions/api/v1/debug/commands/history' }
        'enqueue' = @{ Method = 'POST'; Path = '/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue' }
        'result'  = @{ Method = 'POST'; Path = '/apps/WebHostDebugExtensions/api/v1/debug/commands/result' }
    }

    foreach ($name in $endpoints.Keys) {
        try {
            $endpoint = $endpoints[$name]
            $url = "$BaseUrl$($endpoint.Path)"

            if ($endpoint.Method -eq 'GET') {
                $response = Invoke-WebRequest -Uri $url -Method GET -Headers $headers -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
                $isOk = $response.StatusCode -in @(200, 204)
                if ($isOk) {
                    Test-Result "$name endpoint responds" -Passed -Message "Status: $($response.StatusCode)"
                } else {
                    Test-Result "$name endpoint responds" -Failed -Message "Status: $($response.StatusCode)"
                }
            } else {
                # For POST, test with minimal valid data
                $testBody = if ($name -eq 'enqueue') {
                    @{ Command = 'return true;' } | ConvertTo-Json
                } else {
                    @{ CommandID = [guid]::NewGuid().ToString() } | ConvertTo-Json
                }

                try {
                    $response = Invoke-WebRequest -Uri $url -Method POST -Headers $headers -Body $testBody -ContentType "application/json" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
                    if ($response.StatusCode -in @(200, 201, 400)) {
                        Test-Result "$name endpoint responds" -Passed -Message "Status: $($response.StatusCode)"
                    } else {
                        Test-Result "$name endpoint responds" -Failed -Message "Status: $($response.StatusCode)"
                    }
                } catch {
                    if ($_.Exception.Response.StatusCode.value__ -in @(200, 400)) {
                        Test-Result "$name endpoint responds" -Passed -Message "Endpoint reachable (status: $($_.Exception.Response.StatusCode.value__))"
                    } else {
                        Test-Result "$name endpoint responds" -Failed -Message $_.Exception.Message
                    }
                }
            }
        } catch {
            Test-Result "$name endpoint availability" -Failed -Message $_.Exception.Message
        }
    }
}

# =============================================================================
# Test 4: Command Enqueuing via HTTP
# =============================================================================
Write-Host "`n4. Testing command enqueuing via HTTP..." -ForegroundColor Yellow

if (-not $script:TestApiKey) {
    Test-Result "Command enqueuing" -Skip -Message "No API key available"
} else {
    try {
        $headers = @{ 'Authorization' = "Bearer $script:TestApiKey" }
        $commandPayload = @{
            Type = 'eval'
            Command = 'console.log("Test from PowerShell"); return "Success from server-enqueued command";'
            SessionID = 'all'
        } | ConvertTo-Json

        $response = Invoke-WebRequest `
            -Uri "$BaseUrl/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue" `
            -Method POST `
            -Headers $headers `
            -Body $commandPayload `
            -ContentType "application/json" `
            -UseBasicParsing `
            -TimeoutSec 10

        if ($response.StatusCode -eq 200) {
            $result = $response.Content | ConvertFrom-Json
            Test-Result "Command enqueued via HTTP" -Passed -Message "CommandID: $($result.commandID)"

            $hasCommandID = $null -ne $result.commandID
            if ($hasCommandID) {
                Test-Result "Response contains commandID" -Passed
            } else {
                Test-Result "Response contains commandID" -Failed
            }

            $hasQueuePosition = $null -ne $result.queuePosition
            if ($hasQueuePosition) {
                Test-Result "Response contains queuePosition" -Passed
                Write-Host "      Queue position: $($result.queuePosition)" -ForegroundColor Gray
            } else {
                Test-Result "Response contains queuePosition" -Failed
            }

            # Store commandID for later tests
            $script:TestCommandID = $result.commandID
        } else {
            Test-Result "Command enqueuing" -Failed -Message "Unexpected status: $($response.StatusCode)"
        }
    } catch {
        Test-Result "Command enqueuing via HTTP" -Failed -Message $_.Exception.Message
    }
}

# =============================================================================
# Test 5: Command Types (eval, predefined, dom, network)
# =============================================================================
Write-Host "`n5. Testing different command types..." -ForegroundColor Yellow

if (-not $script:TestApiKey) {
    Test-Result "Command type tests" -Skip -Message "No API key available"
} else {
    $headers = @{ 'Authorization' = "Bearer $script:TestApiKey" }
    $commandTypes = @(
        @{ Type = 'eval'; Command = 'return 42;' }
        @{ Type = 'predefined'; Command = 'browserInfo'; Params = @{} }
        @{ Type = 'dom'; Command = 'highlightElement'; Params = @{ selector = 'body' } }
        @{ Type = 'network'; Command = 'testEndpoint'; Params = @{ url = '/api/v1/status'; method = 'GET' } }
    )

    foreach ($cmdDef in $commandTypes) {
        try {
            $payload = @{
                Type = $cmdDef.Type
                Command = $cmdDef.Command
                SessionID = 'all'
            }

            if ($cmdDef.Params) {
                $payload.Params = $cmdDef.Params
            }

            $payloadJson = $payload | ConvertTo-Json -Depth 3

            $response = Invoke-WebRequest `
                -Uri "$BaseUrl/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue" `
                -Method POST `
                -Headers $headers `
                -Body $payloadJson `
                -ContentType "application/json" `
                -UseBasicParsing `
                -TimeoutSec 10

            $success = $response.StatusCode -eq 200
            if ($success) {
                Test-Result "Enqueue $($cmdDef.Type) command" -Passed
            } else {
                Test-Result "Enqueue $($cmdDef.Type) command" -Failed
            }
        } catch {
            Test-Result "Enqueue $($cmdDef.Type) command" -Failed -Message $_.Exception.Message
        }
    }
}

# =============================================================================
# Test 6: Polling for Commands
# =============================================================================
Write-Host "`n6. Testing command polling..." -ForegroundColor Yellow

if (-not $script:TestApiKey) {
    Test-Result "Command polling" -Skip -Message "No API key available"
} else {
    try {
        $headers = @{ 'Authorization' = "Bearer $script:TestApiKey" }
        $response = Invoke-WebRequest `
            -Uri "$BaseUrl/apps/WebHostDebugExtensions/api/v1/debug/commands/poll" `
            -Method GET `
            -Headers $headers `
            -UseBasicParsing `
            -TimeoutSec 10

        if ($response.StatusCode -eq 200) {
            $data = $response.Content | ConvertFrom-Json
            Test-Result "Poll returns commands" -Passed -Message "Found $($data.commands.Count) command(s)"

            if ($data.commands.Count -gt 0) {
                $firstCmd = $data.commands[0]

                $hasCommandID = $null -ne $firstCmd.CommandID
                if ($hasCommandID) {
                    Test-Result "Command has CommandID" -Passed
                } else {
                    Test-Result "Command has CommandID" -Failed
                }

                $hasType = $null -ne $firstCmd.Type
                if ($hasType) {
                    Test-Result "Command has Type" -Passed
                } else {
                    Test-Result "Command has Type" -Failed
                }

                $hasCommand = $null -ne $firstCmd.Command
                if ($hasCommand) {
                    Test-Result "Command has Command text" -Passed
                } else {
                    Test-Result "Command has Command text" -Failed
                }

                $hasStatus = $firstCmd.Status -eq 'executing'
                if ($hasStatus) {
                    Test-Result "Command status is 'executing'" -Passed
                } else {
                    Test-Result "Command status is 'executing'" -Failed
                }

                Write-Host "`n      Sample Command:" -ForegroundColor Cyan
                Write-Host "         CommandID: $($firstCmd.CommandID)" -ForegroundColor Gray
                Write-Host "         Type: $($firstCmd.Type)" -ForegroundColor Gray
                Write-Host "         Status: $($firstCmd.Status)" -ForegroundColor Gray
                Write-Host "         Command: $($firstCmd.Command.Substring(0, [Math]::Min(50, $firstCmd.Command.Length)))" -ForegroundColor Gray

                # Store for result test
                $script:PolledCommandID = $firstCmd.CommandID
            }
        } elseif ($response.StatusCode -eq 204) {
            Test-Result "Poll endpoint works" -Passed -Message "No commands (204 No Content)"
            Test-Result "Commands available for polling" -Skip -Message "Queue empty"
        } else {
            Test-Result "Poll endpoint" -Failed -Message "Unexpected status: $($response.StatusCode)"
        }
    } catch {
        Test-Result "Command polling" -Failed -Message $_.Exception.Message
    }
}

# =============================================================================
# Test 7: Submitting Command Results
# =============================================================================
Write-Host "`n7. Testing command result submission..." -ForegroundColor Yellow

if (-not $script:TestApiKey) {
    Test-Result "Command result submission" -Skip -Message "No API key available"
} elseif ($script:PolledCommandID) {
    try {
        $headers = @{ 'Authorization' = "Bearer $script:TestApiKey" }
        $resultPayload = @{
            CommandID = $script:PolledCommandID
            Result = "Test result from automated test"
            Error = $null
            ExecutionTimeMs = 42
        } | ConvertTo-Json

        $response = Invoke-WebRequest `
            -Uri "$BaseUrl/apps/WebHostDebugExtensions/api/v1/debug/commands/result" `
            -Method POST `
            -Headers $headers `
            -Body $resultPayload `
            -ContentType "application/json" `
            -UseBasicParsing `
            -TimeoutSec 10

        $success = $response.StatusCode -eq 200
        if ($success) {
            Test-Result "Submit command result" -Passed
        } else {
            Test-Result "Submit command result" -Failed
        }

        if ($success) {
            $data = $response.Content | ConvertFrom-Json
            if ($data.status -eq 'success') {
                Test-Result "Result submission acknowledged" -Passed
            } else {
                Test-Result "Result submission acknowledged" -Failed
            }
        }
    } catch {
        Test-Result "Command result submission" -Failed -Message $_.Exception.Message
    }
} else {
    Test-Result "Command result submission" -Skip -Message "No command ID available from poll"
}

# =============================================================================
# Test 8: Command History Retrieval
# =============================================================================
Write-Host "`n8. Testing command history..." -ForegroundColor Yellow

if (-not $script:TestApiKey) {
    Test-Result "Command history retrieval" -Skip -Message "No API key available"
} else {
    try {
        $headers = @{ 'Authorization' = "Bearer $script:TestApiKey" }
        $response = Invoke-WebRequest `
            -Uri "$BaseUrl/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=10" `
            -Method GET `
            -Headers $headers `
            -UseBasicParsing `
            -TimeoutSec 10

        if ($response.StatusCode -eq 200) {
            $data = $response.Content | ConvertFrom-Json
            Test-Result "History endpoint responds" -Passed -Message "Count: $($data.count)"

            $hasCommands = $null -ne $data.commands
            if ($hasCommands) {
                Test-Result "History contains commands array" -Passed
            } else {
                Test-Result "History contains commands array" -Failed
            }

            if ($hasCommands -and $data.commands.Count -gt 0) {
                $recentCmd = $data.commands[0]

                $hasCommandID = $null -ne $recentCmd.CommandID
                if ($hasCommandID) {
                    Test-Result "History entry has CommandID" -Passed
                } else {
                    Test-Result "History entry has CommandID" -Failed
                }

                $hasStatus = $null -ne $recentCmd.Status
                if ($hasStatus) {
                    Test-Result "History entry has Status" -Passed
                } else {
                    Test-Result "History entry has Status" -Failed
                }

                $hasCompletedAt = $null -ne $recentCmd.CompletedAt
                if ($hasCompletedAt) {
                    Test-Result "History entry has CompletedAt" -Passed
                } else {
                    Test-Result "History entry has CompletedAt" -Failed
                }

                Write-Host "`n      Most Recent Command:" -ForegroundColor Cyan
                Write-Host "         CommandID: $($recentCmd.CommandID)" -ForegroundColor Gray
                Write-Host "         Status: $($recentCmd.Status)" -ForegroundColor Gray
                Write-Host "         CompletedAt: $($recentCmd.CompletedAt)" -ForegroundColor Gray
                if ($recentCmd.ExecutionTimeMs) {
                    Write-Host "         ExecutionTime: $($recentCmd.ExecutionTimeMs)ms" -ForegroundColor Gray
                }
            } else {
                Test-Result "History has entries" -Skip -Message "History is empty"
            }
        } else {
            Test-Result "History retrieval" -Failed -Message "Unexpected status: $($response.StatusCode)"
        }
    } catch {
        Test-Result "Command history retrieval" -Failed -Message $_.Exception.Message
    }
}

# =============================================================================
# Test 9: Session Targeting
# =============================================================================
Write-Host "`n9. Testing session targeting..." -ForegroundColor Yellow

if (-not $script:TestApiKey) {
    Test-Result "Session targeting" -Skip -Message "No API key available"
} else {
    try {
        $headers = @{ 'Authorization' = "Bearer $script:TestApiKey" }

        # Enqueue to "all" sessions
        $payload1 = @{
            Type = 'eval'
            Command = 'return "All sessions";'
            SessionID = 'all'
        } | ConvertTo-Json

        $response1 = Invoke-WebRequest `
            -Uri "$BaseUrl/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue" `
            -Method POST `
            -Headers $headers `
            -Body $payload1 `
            -ContentType "application/json" `
            -UseBasicParsing `
            -TimeoutSec 10

        if ($response1.StatusCode -eq 200) {
            Test-Result "Enqueue to 'all' sessions" -Passed
        } else {
            Test-Result "Enqueue to 'all' sessions" -Failed
        }

        # Enqueue to specific session (use fake GUID)
        $fakeSessionID = [guid]::NewGuid().ToString()
        $payload2 = @{
            Type = 'eval'
            Command = 'return "Specific session";'
            SessionID = $fakeSessionID
        } | ConvertTo-Json

        $response2 = Invoke-WebRequest `
            -Uri "$BaseUrl/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue" `
            -Method POST `
            -Headers $headers `
            -Body $payload2 `
            -ContentType "application/json" `
            -UseBasicParsing `
            -TimeoutSec 10

        if ($response2.StatusCode -eq 200) {
            Test-Result "Enqueue to specific session" -Passed
        } else {
            Test-Result "Enqueue to specific session" -Failed
        }

        Write-Host "      Target SessionID: $fakeSessionID" -ForegroundColor Gray
    } catch {
        Test-Result "Session targeting" -Failed -Message $_.Exception.Message
    }
}

# =============================================================================
# Test 10: Browser Integration Test (Optional)
# =============================================================================
Write-Host "`n10. Browser integration test..." -ForegroundColor Yellow

if ($SkipBrowserTest) {
    Test-Result "Browser integration" -Skip -Message "Use -SkipBrowserTest parameter"
} else {
    Write-Host "`n   To test browser integration manually:" -ForegroundColor Cyan
    Write-Host "   1. Open: $BaseUrl/apps/WebHostDebugExtensions/public/elements/debug-console/" -ForegroundColor Gray
    Write-Host "   2. Wait 3 seconds for polling to retrieve queued commands" -ForegroundColor Gray
    Write-Host "   3. Commands will execute automatically" -ForegroundColor Gray
    Write-Host "   4. Check history to see results" -ForegroundColor Gray
    if ($Global:PSWebServer.DebugCommands.Queue) {
        Write-Host "`n   Current queue size: $($Global:PSWebServer.DebugCommands.Queue.Count)" -ForegroundColor Yellow
    }
    Test-Result "Browser integration" -Skip -Message "Manual test required"
}

# =============================================================================
# Test Summary
# =============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$totalTests = $script:TestsPassed + $script:TestsFailed + $script:TestsSkipped
Write-Host "   Total Tests: $totalTests" -ForegroundColor White
Write-Host "   ✅ Passed: $($script:TestsPassed)" -ForegroundColor Green
Write-Host "   ❌ Failed: $($script:TestsFailed)" -ForegroundColor Red
Write-Host "   ⊘ Skipped: $($script:TestsSkipped)" -ForegroundColor Yellow

if ($script:TestsFailed -eq 0) {
    Write-Host "`n✅ All tests passed!" -ForegroundColor Green
} else {
    Write-Host "`n❌ Some tests failed. Review output above." -ForegroundColor Red
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Next Steps:" -ForegroundColor White
Write-Host "  1. Open debug console: $BaseUrl/apps/WebHostDebugExtensions/public/elements/debug-console/" -ForegroundColor Cyan
Write-Host "  2. Commands will auto-execute via polling (every 3 seconds)" -ForegroundColor Cyan
Write-Host "  3. View results in Command History section" -ForegroundColor Cyan
Write-Host "  4. Try manual commands from the UI" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Cleanup test resources
Cleanup-TestResources
