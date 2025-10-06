param (
    [pscredential]$credential
)

if ($credential.GetNetworkCredential().Domain -in ('.','localhost',$env:computername)){
    Add-Type -AssemblyName System.DirectoryServices.AccountManagement
    $DS = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Machine)
    # Returns $true or $false
    return $DS.ValidateCredentials($credential.GetNetworkCredential().UserName, $credential.GetNetworkCredential().password)
}

# Get current domain using logged-on user's credentials
$domain = New-Object System.DirectoryServices.DirectoryEntry(
    ($credential.GetNetworkCredential().domain,'localhost'|Select-Object -First 1),
    $credential.GetNetworkCredential().username,
    $credential.GetNetworkCredential().password
)

return $null -ne ($domain).name