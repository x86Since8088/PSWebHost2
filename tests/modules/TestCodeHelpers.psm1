## TestCodeHelpers - minimal, robust helpers for tests
# PSScriptAnalyzer: disable=PSUseApprovedVerbs

function Assert-Equal {
    [CmdletBinding()]
    param(
        $Actual,
        $Expected,
        [string]$Message = ''
    )

    if ($null -eq $Actual -and $null -eq $Expected) {
        return $true
    }

    try {
        $aJson = $Actual | ConvertTo-Json -Depth 5 -ErrorAction Stop
        $eJson = $Expected | ConvertTo-Json -Depth 5 -ErrorAction Stop
    } catch {
        $aJson = "$Actual"
        $eJson = "$Expected"
    }

    if ($aJson -ne $eJson) {
        throw "Assertion failed. Expected: $eJson Actual: $aJson $Message"
    }

    Write-Output "Assertion passed: $Message"
    return $true
}

function Assert-True {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][bool]$Condition,
        [string]$Message = ''
    )

    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
    Write-Output "Assertion passed: $Message"
    return $true
}

function Fail {
    param([string]$Message)
    throw "Test failed: $Message"
}

function Pending {
    param([string]$Message)
    Write-Warning "Test pending: $Message"
}

function ShouldBe {
    param(
        $Actual,
        $Expected
    )
    function Convert-ToOrderedObject {
        param($obj)
        if ($null -eq $obj) { return $null }

        if ($obj -is [System.Array]) {
            $arr = @()
            foreach ($i in $obj) { $arr += Convert-ToOrderedObject $i }
            return ,$arr
        }

        if ($obj -is [hashtable] -or $obj -is [System.Management.Automation.PSObject] -or $obj -is [pscustomobject]) {
            $ordered = [ordered]@{}
            try { $props = ($obj | Get-Member -MemberType NoteProperty,Property | Select-Object -Expand Name | Sort-Object) } catch { $props = @() }
            foreach ($p in $props) {
                $val = $null
                try { $val = $obj.$p } catch { $val = $null }
                $ordered[$p] = Convert-ToOrderedObject $val
            }
            return $ordered
        }

        return $obj
    }

    function Convert-ToOrderedJson {
        param($o)
        $ordered = Convert-ToOrderedObject $o
        try {
            return $ordered | ConvertTo-Json -Depth 20 -Compress -ErrorAction Stop
        } catch {
            return "$ordered"
        }
    }

    # If actual is a scalar (string or value type), compare directly to avoid JSON serialization differences
    if ($Actual -is [string] -or $Actual -is [System.ValueType]) {
        if ($Actual -ne $Expected) {
            throw "ShouldBe failed: $Actual -ne $Expected"
        }
        return $true
    }

    $aJson = Convert-ToOrderedJson $Actual
    $eJson = Convert-ToOrderedJson $Expected
    if ($aJson -ne $eJson) {
        throw "ShouldBe failed: $aJson -ne $eJson"
    }
    return $true
}

function ShouldNot {
    param(
        $Actual,
        $Expected
    )
    if ($Actual -eq $Expected) {
        throw "ShouldNot failed: $Actual -eq $Expected"
    }
    return $true
}

function ShouldBeOfType {
    param(
        $Actual,
        [Type]$Type
    )
    if ($null -eq $Actual) {
        throw "ShouldBeOfType failed: Actual is null"
    }
    if ($Actual.GetType().FullName -ne $Type.FullName) {
        throw "ShouldBeOfType failed: $($Actual.GetType().FullName) -ne $($Type.FullName)"
    }
    return $true
}

function ShouldThrow {
    param(
        [ScriptBlock]$Script
    )
    try {
        & $Script
    } catch {
        return $true
    }
    throw "ShouldThrow failed: No exception thrown."
}

# Provide a single "Should" function supporting common pipeline usage: <value> | Should -Be <expected>
function Should {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true,Position=0)]
        $InputObject,
        [Parameter(Position=1,ValueFromPipelineByPropertyName=$true)][AllowNull()]$Be,
        [Parameter(ValueFromPipelineByPropertyName=$true)][AllowNull()]$Not,
        [Parameter(ValueFromPipelineByPropertyName=$true)][AllowNull()][Type]$BeOfType,
        [switch]$Throw
    )

    process {
        # If the input is a ScriptBlock, execute it to get the actual value (Pester-like behavior)
        $actualValue = if ($InputObject -is [scriptblock]) { & $InputObject } else { $InputObject }

        if ($PSBoundParameters.ContainsKey('Be')) {
            ShouldBe -Actual $actualValue -Expected $Be
            return $actualValue
        }
        if ($PSBoundParameters.ContainsKey('Not')) {
            ShouldNot -Actual $actualValue -Expected $Not
            return $actualValue
        }
        if ($PSBoundParameters.ContainsKey('BeOfType')) {
            ShouldBeOfType -Actual $actualValue -Type $BeOfType
            return $actualValue
        }
        if ($PSBoundParameters.ContainsKey('Throw')) {
            # For Throw, the InputObject should be a scriptblock; if it's not, wrap it
            $scriptToRun = if ($InputObject -is [scriptblock]) { $InputObject } else { { $InputObject } }
            ShouldThrow -Script $scriptToRun
            return $actualValue
        }

        throw "No supported Should operator provided"
    }
}

# Minimal Pester-like DSL
function Describe {
    param(
        [string]$Name,
        [scriptblock]$Body
    )
    Write-Host "[DESCRIBE] $Name"
    & $Body
}

function Context {
    param(
        [string]$Name,
        [scriptblock]$Body
    )
    Write-Host "  [CONTEXT] $Name"
    & $Body
}

function It {
    param(
        [string]$Name,
        [scriptblock]$Body
    )
    Write-Host "    [IT] $Name"
    try {
        & $Body
        Write-Host "      [PASS] ${Name}"
    } catch {
        Write-Host "      [FAIL] ${Name}: $($_.Exception.Message)"
        throw $_
    }
}

function BeforeAll {
    param([scriptblock]$Body)
    & $Body
}

function AfterAll {
    param([scriptblock]$Body)
    & $Body
}

Export-ModuleMember -Function *
