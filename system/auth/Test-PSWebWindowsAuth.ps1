param (
    [pscredential]$credential
)
$MyTag = '[Test-PSWebWindowsAuth.ps1]'

$isLocalAccountDomainName = $credential.GetNetworkCredential().Domain -in ('.','localhost',$env:computername)
Write-PSWebHostLog -Severity 'Verbose' -Category 'Auth' -Message "$MyTag $($credential.UserName) isLocalAccountDomainName:$isLocalAccountDomainName" -WriteHost
if ($credential.GetNetworkCredential().Domain -in ('.', 'localhost', $env:computername)) {
    $scriptBlock = {
        param($credential)
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement
        $DS = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Machine)
        return $DS.ValidateCredentials($credential.GetNetworkCredential().UserName, $credential.GetNetworkCredential().password)
    }

    $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $credential
    $null = $job | Wait-Job -Timeout 5
    if ($job.State -eq 'Running') {
        Stop-Job $job
        Remove-Job $job
        Write-PSWebHostLog -Severity 'Warning' -Category 'Auth' -Message "$MyTag PrincipalContext auth timed out after 5s" -WriteHost
        return $false
    }

    $isAuthenticated = Receive-Job $job
    Remove-Job $job
    Write-PSWebHostLog -Severity 'Verbose' -Category 'Auth' -Message "$MyTag Tested via PrincipalContext - Result: $isAuthenticated" -WriteHost
    return $isAuthenticated
}

# Get current domain using logged-on user's credentials
$scriptBlock = {
    param($credential)
    $domainEntry = New-Object System.DirectoryServices.DirectoryEntry(
        ($credential.GetNetworkCredential().domain, 'localhost' | Select-Object -First 1),
        $credential.GetNetworkCredential().username,
        $credential.GetNetworkCredential().password
    )
    return $null -ne $domainEntry.name
}

$job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $credential
$null = $job | Wait-Job -Timeout 5
if ($job.State -eq 'Running') {
    Stop-Job $job
    Remove-Job $job
    Write-PSWebHostLog -Severity 'Warning' -Category 'Auth' -Message "$MyTag DirectoryEntry auth timed out after 5s" -WriteHost
    return $false
}

$isAuthenticated = Receive-Job $job
Remove-Job $job
Write-PSWebHostLog -Severity 'Verbose' -Category 'Auth' -Message "$MyTag Tested via DirectoryEntry - Result: $isAuthenticated" -WriteHost
return $isAuthenticated