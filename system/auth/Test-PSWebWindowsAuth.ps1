param (
    [pscredential]$credential
)

$isLocalAccountDomainName = $credential.GetNetworkCredential().Domain -in ('.','localhost',$env:computername)
Write-Host "[Test-PSWebWindowsAuth.ps1] $($credential.UserName) isLocalAccountDomainName:$isLocalAccountDomainName"
if ($credential.GetNetworkCredential().Domain -in ('.', 'localhost', $env:computername)) {
    $scriptBlock = {
        param($credential)
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement
        $DS = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Machine)
        return $DS.ValidateCredentials($credential.GetNetworkCredential().UserName, $credential.GetNetworkCredential().password)
    }

    $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $credential
    $job | Wait-Job -Timeout 5
    $job
    if ($job.State -eq 'Running') {
        Stop-Job $job
        Remove-Job $job
        Write-Warning "failed authentication using System.DirectoryServices.AccountManagement.PrincipalContext"
        return $false
    }

    $isAuthenticated = Receive-Job $job
    Remove-Job $job
    Write-Host "Tested Authentication using System.DirectoryServices.AccountManagement.PrincipalContext $isAuthenticated"
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
$job | Wait-Job -Timeout 5
$job
if ($job.State -eq 'Running') {
    Stop-Job $job
    Remove-Job $job
    Write-Warning "failed authentication using System.DirectoryServices.DirectoryEntry"
    return $false
}

$isAuthenticated = Receive-Job $job
Remove-Job $job
Write-Host "Tested Authentication using System.DirectoryServices.DirectoryEntry $isAuthenticated"
return $isAuthenticated