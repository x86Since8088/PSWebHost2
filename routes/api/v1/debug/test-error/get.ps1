param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

try {
    # Deliberately create some local variables for testing
    $testString = "Hello World"
    $testNumber = 42
    $testArray = @(1, 2, 3, 4, 5)
    $testHash = @{
        Name = "Test User"
        Age = 30
        Email = "test@example.com"
    }

    # Get the error type from query parameter
    $errorType = $Request.QueryString['type']

    switch ($errorType) {
        'division' {
            # Division by zero error
            $result = 100 / 0
        }
        'null' {
            # Null reference error
            $null.NonExistentProperty
        }
        'type' {
            # Type conversion error
            [int]"not a number"
        }
        'file' {
            # File not found error
            Get-Content "C:\NonExistent\File.txt" -ErrorAction Stop
        }
        default {
            # Default: throw a generic error
            throw "This is a test error to demonstrate the error reporting system. Variables in scope: testString='$testString', testNumber=$testNumber"
        }
    }

    # This should never execute
    $successResponse = @{
        status = 'success'
        message = 'No error occurred'
    } | ConvertTo-Json -Compress
    context_reponse -Response $Response -StatusCode 200 -String $successResponse -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'TestError' -Message "Test error triggered: $($_.Exception.Message)"

    # Generate detailed error report based on user role
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    context_reponse -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
