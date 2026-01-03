# Test-Helpers.psm1
# Common helper functions for PSWebHost twin tests

function Get-TestWebHost {
    <#
    .SYNOPSIS
        Starts a test instance of PSWebHost

    .DESCRIPTION
        Starts PSWebHost on a random port for testing purposes.
        Returns an object with webHost details including URL and Process.

    .PARAMETER ProjectRoot
        Path to PSWebHost project root

    .PARAMETER Port
        Specific port to use (default: auto-select)

    .EXAMPLE
        $webHost = Get-TestWebHost -ProjectRoot C:\SC\PsWebHost
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [int]$Port = 0
    )

    # Check if Start-WebHostForTest helper exists
    $helperPath = Join-Path $ProjectRoot 'tests\helpers\Start-WebHostForTest.psm1'

    if (Test-Path $helperPath) {
        Import-Module $helperPath -Force
        return Start-WebHostForTest -ProjectRoot $ProjectRoot -Port $Port
    } else {
        throw "WebHost test helper not found at: $helperPath"
    }
}

function Stop-TestWebHost {
    <#
    .SYNOPSIS
        Stops a test webHost instance

    .PARAMETER WebHost
        WebHost object returned from Get-TestWebHost

    .EXAMPLE
        Stop-TestWebHost -WebHost $webHost
    #>
    param(
        [Parameter(Mandatory)]
        $WebHost
    )

    if ($WebHost -and $WebHost.Process) {
        try {
            $WebHost.Process | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        } catch {
            Write-Warning "Error stopping WebHost: $_"
        }
    }
}

function Test-JsonResponse {
    <#
    .SYNOPSIS
        Validates that a response is valid JSON

    .PARAMETER Response
        HTTP response object from Invoke-WebRequest

    .EXAMPLE
        Test-JsonResponse -Response $response | Should -Be $true
    #>
    param(
        [Parameter(Mandatory)]
        $Response
    )

    try {
        $Response.Content | ConvertFrom-Json | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Get-ResponseJson {
    <#
    .SYNOPSIS
        Extracts JSON from HTTP response, handling errors

    .PARAMETER Response
        HTTP response object from Invoke-WebRequest

    .PARAMETER ErrorResponse
        HTTP error response (from catch block)

    .EXAMPLE
        $json = Get-ResponseJson -Response $response
        $json = Get-ResponseJson -ErrorResponse $_.Exception.Response
    #>
    param(
        $Response,
        $ErrorResponse
    )

    try {
        if ($Response) {
            return $Response.Content | ConvertFrom-Json
        } elseif ($ErrorResponse) {
            $stream = $ErrorResponse.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $responseBody = $reader.ReadToEnd()
            return $responseBody | ConvertFrom-Json
        }
    } catch {
        return $null
    }
}

function New-TestUser {
    <#
    .SYNOPSIS
        Creates a test user in the database

    .PARAMETER ProjectRoot
        Path to PSWebHost project root

    .PARAMETER Email
        User email address

    .PARAMETER Password
        User password

    .EXAMPLE
        New-TestUser -ProjectRoot $ProjectRoot -Email 'test@localhost' -Password 'Test123!'
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$Email,

        [string]$Password = 'Test123!'
    )

    # Import authentication module
    Import-Module (Join-Path $ProjectRoot 'modules\PSWebHost_Authentication') -DisableNameChecking -Force

    # Create test user
    try {
        New-PSWebHostUser -Email $Email -Password $Password -ErrorAction Stop
        return $true
    } catch {
        Write-Warning "Failed to create test user: $_"
        return $false
    }
}

function Remove-TestUser {
    <#
    .SYNOPSIS
        Removes a test user from the database

    .PARAMETER ProjectRoot
        Path to PSWebHost project root

    .PARAMETER Email
        User email address to remove

    .EXAMPLE
        Remove-TestUser -ProjectRoot $ProjectRoot -Email 'test@localhost'
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$Email
    )

    # Import database module
    Import-Module (Join-Path $ProjectRoot 'modules\PSWebHost_Database') -DisableNameChecking -Force

    $dbFile = Join-Path $ProjectRoot "PsWebHost_Data\pswebhost.db"

    try {
        $query = "DELETE FROM Users WHERE Email = '$Email';"
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query
        return $true
    } catch {
        Write-Warning "Failed to remove test user: $_"
        return $false
    }
}

function Assert-HttpStatus {
    <#
    .SYNOPSIS
        Validates HTTP status code

    .PARAMETER Response
        HTTP response object

    .PARAMETER ExpectedStatus
        Expected status code

    .EXAMPLE
        Assert-HttpStatus -Response $response -ExpectedStatus 200
    #>
    param(
        [Parameter(Mandatory)]
        $Response,

        [Parameter(Mandatory)]
        [int]$ExpectedStatus
    )

    $Response.StatusCode | Should -Be $ExpectedStatus
}

function Assert-JsonProperty {
    <#
    .SYNOPSIS
        Validates that JSON response has expected property

    .PARAMETER Json
        JSON object

    .PARAMETER PropertyName
        Property name to check

    .PARAMETER ExpectedValue
        Expected property value (optional)

    .EXAMPLE
        Assert-JsonProperty -Json $json -PropertyName 'status' -ExpectedValue 'success'
    #>
    param(
        [Parameter(Mandatory)]
        $Json,

        [Parameter(Mandatory)]
        [string]$PropertyName,

        $ExpectedValue
    )

    $Json.PSObject.Properties.Name | Should -Contain $PropertyName

    if ($PSBoundParameters.ContainsKey('ExpectedValue')) {
        $Json.$PropertyName | Should -Be $ExpectedValue
    }
}

Export-ModuleMember -Function @(
    'Get-TestWebHost'
    'Stop-TestWebHost'
    'Test-JsonResponse'
    'Get-ResponseJson'
    'New-TestUser'
    'Remove-TestUser'
    'Assert-HttpStatus'
    'Assert-JsonProperty'
)
