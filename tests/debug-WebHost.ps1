$Path = (Resolve-Path "$PSScriptRoot\..\WebHost.ps1").Path
. $Path -verbose 2>&1 |
    Where-Object{$_}|
    ForEach-Object{
        $OutputItem = $_
        .{
            if ($OutputItem -is [System.Management.Automation.ErrorRecord]) {
                $text = ($_ | out-string).trim('\s')
                if ($Text -match '\w') {
                    [array]$Callstack = Get-PSCallStack | 
                        Select-Object -skip 2 Command, ScriptName, ScriptLineNumber, Location,@{N='Source';E={$_.InvocationInfo.MyCommand.Source}}, Position, 
                        @{N='Definition';E={if ($_.Command[0] -eq '<') {$_.InvocationInfo.Definition}}}
                    write-host "=== Error Start ==="
                    $_
                    write-host "=== Error End ==="
                    write-host "=== PSCallStack Start ==="
                    $Callstack | select -First ($callstack.count - 2)
                    write-host "=== PSCallStack End ==="
                } ELSE {
                    $_|
                        Where-Object{$_}|
                        out-string
                }
            }
            ELSE {
                    $_|
                        Where-Object{$_}|
                        out-string
                }
            }
}