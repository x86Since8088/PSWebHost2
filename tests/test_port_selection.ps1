# Test port selection logic directly
$ProjectRoot = "e:\sc\git\PsWebHost"
$logFile = "$env:temp\port_test.log"

"=== Port Selection Test ===" | Tee-Object -FilePath $logFile -Append

try {
    Remove-Module Start-WebHostForTest -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ProjectRoot 'tests\helpers\Start-WebHostForTest.psm1') -Force
    
    "Module imported successfully" | Tee-Object -FilePath $logFile -Append
    
    # Call the function to start webhost
    $result = Start-WebHostForTest -ProjectRoot $ProjectRoot -Verbose *>&1
    
    $result | Tee-Object -FilePath $logFile -Append
    
    # Stop the process
    if ($result.Process) {
        Stop-Process -InputObject $result.Process -Force -ErrorAction SilentlyContinue
        "Process stopped" | Tee-Object -FilePath $logFile -Append
    }
    
} catch {
    "ERROR: $($_.Exception.Message)" | Tee-Object -FilePath $logFile -Append
    "Stack: $($_.ScriptStackTrace)" | Tee-Object -FilePath $logFile -Append
}

"Log saved to: $logFile" | Tee-Object -FilePath $logFile -Append
"=== Test Complete ===" | Tee-Object -FilePath $logFile -Append
