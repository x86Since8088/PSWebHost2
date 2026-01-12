# PSWebVault Module
# Provides secure credential storage using Windows DPAPI or AES encryption
# Supports multiple credential types: Password, Certificate, API_Key

$script:VaultDbPath = $null

# Valid credential types
$script:CredentialTypes = @('Password', 'Certificate', 'API_Key')

function Initialize-VaultDatabase {
    <#
    .SYNOPSIS
        Sets the vault database path for the module
    #>
    param([string]$DatabasePath)
    $script:VaultDbPath = $DatabasePath
}

function Get-VaultDatabasePath {
    <#
    .SYNOPSIS
        Gets the vault database path, auto-detecting if not set
    #>
    if ($script:VaultDbPath) {
        return $script:VaultDbPath
    }

    # Try to get from PSWebServer global
    if ($Global:PSWebServer -and $Global:PSWebServer.Vault -and $Global:PSWebServer.Vault.DatabasePath) {
        return $Global:PSWebServer.Vault.DatabasePath
    }

    # Fallback to discovering from app location
    $modulePath = $PSScriptRoot
    $appRoot = Split-Path $modulePath -Parent
    return Join-Path $appRoot "data\vault.db"
}

function Protect-VaultCredential {
    <#
    .SYNOPSIS
        Encrypts a credential using Windows DPAPI
    .PARAMETER PlainText
        The plain text to encrypt
    .PARAMETER DpapiScope
        DPAPI scope: CurrentUser or LocalMachine
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PlainText,

        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$DpapiScope = 'CurrentUser'
    )

    try {
        $secureString = ConvertTo-SecureString -String $PlainText -AsPlainText -Force
        $encrypted = ConvertFrom-SecureString -SecureString $secureString
        return $encrypted
    } catch {
        Write-Error "Failed to encrypt credential: $($_.Exception.Message)"
        return $null
    }
}

function Unprotect-VaultCredential {
    <#
    .SYNOPSIS
        Decrypts a credential encrypted with Windows DPAPI
    .PARAMETER EncryptedText
        The encrypted credential string
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EncryptedText
    )

    try {
        $secureString = ConvertTo-SecureString -String $EncryptedText
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
        $plainText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        return $plainText
    } catch {
        Write-Error "Failed to decrypt credential: $($_.Exception.Message)"
        return $null
    }
}

function Set-VaultCredential {
    <#
    .SYNOPSIS
        Stores a credential in the vault
    .PARAMETER Name
        Unique name for the credential
    .PARAMETER CredentialType
        Type of credential: Password, Certificate, or API_Key
    .PARAMETER Username
        The username associated with the credential
    .PARAMETER Password
        The password to store (for Password type)
    .PARAMETER ApiKey
        The API key to store (for API_Key type)
    .PARAMETER Certificate
        The certificate data to store (for Certificate type)
    .PARAMETER CertificateFormat
        Format of the certificate: PFX, PEM, CER (for Certificate type)
    .PARAMETER Scope
        Organizational scope (e.g., 'global', 'node', 'service', 'api_key')
    .PARAMETER Description
        Optional description of the credential
    .PARAMETER CreatedBy
        UserID of the user creating the credential
    .PARAMETER Metadata
        Optional JSON metadata
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [ValidateSet('Password', 'Certificate', 'API_Key')]
        [string]$CredentialType = 'Password',

        [string]$Username,

        [string]$Password,

        [string]$ApiKey,

        [string]$Certificate,

        [ValidateSet('PFX', 'PEM', 'CER', '')]
        [string]$CertificateFormat,

        [string]$Scope = 'global',

        [string]$Description,

        [string]$CreatedBy,

        [string]$Metadata
    )

    $dbPath = Get-VaultDatabasePath
    $MyTag = '[Set-VaultCredential]'

    # Determine what to encrypt based on credential type
    $secretToEncrypt = switch ($CredentialType) {
        'Password' { $Password }
        'API_Key' { $ApiKey }
        'Certificate' { $Certificate }
    }

    if (-not $secretToEncrypt) {
        throw "No secret provided for credential type: $CredentialType"
    }

    # Encrypt the secret
    $encryptedSecret = Protect-VaultCredential -PlainText $secretToEncrypt
    if (-not $encryptedSecret) {
        throw "Failed to encrypt secret"
    }

    # Sanitize inputs
    $safeName = Sanitize-SqlQueryString -String $Name
    $safeCredType = Sanitize-SqlQueryString -String $CredentialType
    $safeUsername = if ($Username) { Sanitize-SqlQueryString -String $Username } else { '' }
    $safeScope = Sanitize-SqlQueryString -String $Scope
    $safeCertFormat = if ($CertificateFormat) { Sanitize-SqlQueryString -String $CertificateFormat } else { '' }
    $safeDescription = if ($Description) { Sanitize-SqlQueryString -String $Description } else { '' }
    $safeCreatedBy = if ($CreatedBy) { Sanitize-SqlQueryString -String $CreatedBy } else { '' }
    $safeMetadata = if ($Metadata) { Sanitize-SqlQueryString -String $Metadata } else { '' }

    # Check if credential already exists
    $existingQuery = "SELECT ID FROM Vault_Credentials WHERE Name = '$safeName' AND Scope = '$safeScope';"
    $existing = Get-PSWebSQLiteData -File $dbPath -Query $existingQuery

    if ($existing) {
        # Update existing
        $updateQuery = @"
UPDATE Vault_Credentials
SET CredentialType = '$safeCredType',
    Username = '$safeUsername',
    EncryptedSecret = '$encryptedSecret',
    CertificateFormat = '$safeCertFormat',
    Description = '$safeDescription',
    UpdatedAt = datetime('now'),
    Metadata = '$safeMetadata'
WHERE Name = '$safeName' AND Scope = '$safeScope';
"@
        Invoke-PSWebSQLiteNonQuery -File $dbPath -Query $updateQuery
        Write-Verbose "$MyTag Updated credential: $Name (Type: $CredentialType, Scope: $Scope)"

        # Audit log
        Add-VaultAuditLog -Action 'Update' -CredentialName $Name -Scope $Scope -UserID $CreatedBy -Details "Type: $CredentialType"
    } else {
        # Insert new
        $insertQuery = @"
INSERT INTO Vault_Credentials (Name, CredentialType, Username, EncryptedSecret, CertificateFormat, Scope, Description, CreatedBy, Metadata)
VALUES ('$safeName', '$safeCredType', '$safeUsername', '$encryptedSecret', '$safeCertFormat', '$safeScope', '$safeDescription', '$safeCreatedBy', '$safeMetadata');
"@
        Invoke-PSWebSQLiteNonQuery -File $dbPath -Query $insertQuery
        Write-Verbose "$MyTag Created credential: $Name (Type: $CredentialType, Scope: $Scope)"

        # Audit log
        Add-VaultAuditLog -Action 'Create' -CredentialName $Name -Scope $Scope -UserID $CreatedBy -Details "Type: $CredentialType"
    }

    return $true
}

function Get-VaultCredential {
    <#
    .SYNOPSIS
        Retrieves a credential from the vault
    .PARAMETER Name
        Name of the credential to retrieve
    .PARAMETER Scope
        Scope of the credential
    .PARAMETER DecryptSecret
        If set, decrypts and returns the secret
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$Scope = 'global',

        [switch]$DecryptSecret
    )

    $dbPath = Get-VaultDatabasePath
    $safeName = Sanitize-SqlQueryString -String $Name
    $safeScope = Sanitize-SqlQueryString -String $Scope

    $query = "SELECT * FROM Vault_Credentials WHERE Name = '$safeName' AND Scope = '$safeScope';"
    $credential = Get-PSWebSQLiteData -File $dbPath -Query $query

    if (-not $credential) {
        return $null
    }

    $result = [PSCustomObject]@{
        ID = $credential.ID
        Name = $credential.Name
        CredentialType = $credential.CredentialType
        Username = $credential.Username
        CertificateFormat = $credential.CertificateFormat
        Scope = $credential.Scope
        Description = $credential.Description
        CreatedBy = $credential.CreatedBy
        CreatedAt = $credential.CreatedAt
        UpdatedAt = $credential.UpdatedAt
        Metadata = $credential.Metadata
    }

    if ($DecryptSecret -and $credential.EncryptedSecret) {
        $decrypted = Unprotect-VaultCredential -EncryptedText $credential.EncryptedSecret

        # Return with appropriate property name based on type
        switch ($credential.CredentialType) {
            'Password' { $result | Add-Member -MemberType NoteProperty -Name 'Password' -Value $decrypted }
            'API_Key' { $result | Add-Member -MemberType NoteProperty -Name 'ApiKey' -Value $decrypted }
            'Certificate' { $result | Add-Member -MemberType NoteProperty -Name 'Certificate' -Value $decrypted }
            default { $result | Add-Member -MemberType NoteProperty -Name 'Secret' -Value $decrypted }
        }
    }

    return $result
}

function Get-VaultCredentials {
    <#
    .SYNOPSIS
        Lists all credentials in a scope (without secrets)
    .PARAMETER Scope
        Filter by scope (optional, returns all if not specified)
    .PARAMETER CredentialType
        Filter by credential type
    #>
    [CmdletBinding()]
    param(
        [string]$Scope,

        [ValidateSet('Password', 'Certificate', 'API_Key', '')]
        [string]$CredentialType
    )

    $dbPath = Get-VaultDatabasePath
    $whereClause = @()

    if ($Scope) {
        $safeScope = Sanitize-SqlQueryString -String $Scope
        $whereClause += "Scope = '$safeScope'"
    }

    if ($CredentialType) {
        $safeType = Sanitize-SqlQueryString -String $CredentialType
        $whereClause += "CredentialType = '$safeType'"
    }

    $query = "SELECT ID, Name, CredentialType, Username, CertificateFormat, Scope, Description, CreatedBy, CreatedAt, UpdatedAt FROM Vault_Credentials"

    if ($whereClause.Count -gt 0) {
        $query += " WHERE " + ($whereClause -join " AND ")
    }

    $query += " ORDER BY Scope, Name;"

    $credentials = Get-PSWebSQLiteData -File $dbPath -Query $query
    return $credentials
}

function Remove-VaultCredential {
    <#
    .SYNOPSIS
        Removes a credential from the vault
    .PARAMETER Name
        Name of the credential to remove
    .PARAMETER Scope
        Scope of the credential
    .PARAMETER RemovedBy
        UserID of the user removing the credential
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$Scope = 'global',

        [string]$RemovedBy
    )

    $dbPath = Get-VaultDatabasePath
    $safeName = Sanitize-SqlQueryString -String $Name
    $safeScope = Sanitize-SqlQueryString -String $Scope

    # Check if exists
    $existing = Get-PSWebSQLiteData -File $dbPath -Query "SELECT ID, CredentialType FROM Vault_Credentials WHERE Name = '$safeName' AND Scope = '$safeScope';"

    if (-not $existing) {
        throw "Credential not found: $Name (Scope: $Scope)"
    }

    $deleteQuery = "DELETE FROM Vault_Credentials WHERE Name = '$safeName' AND Scope = '$safeScope';"
    Invoke-PSWebSQLiteNonQuery -File $dbPath -Query $deleteQuery

    # Audit log
    Add-VaultAuditLog -Action 'Delete' -CredentialName $Name -Scope $Scope -UserID $RemovedBy -Details "Type: $($existing.CredentialType)"

    return $true
}

function Add-VaultAuditLog {
    <#
    .SYNOPSIS
        Adds an entry to the vault audit log
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,

        [string]$CredentialName,

        [string]$Scope,

        [string]$UserID,

        [string]$IPAddress,

        [string]$Details
    )

    $dbPath = Get-VaultDatabasePath

    $safeAction = Sanitize-SqlQueryString -String $Action
    $safeCredName = if ($CredentialName) { Sanitize-SqlQueryString -String $CredentialName } else { '' }
    $safeScope = if ($Scope) { Sanitize-SqlQueryString -String $Scope } else { '' }
    $safeUserID = if ($UserID) { Sanitize-SqlQueryString -String $UserID } else { '' }
    $safeIP = if ($IPAddress) { Sanitize-SqlQueryString -String $IPAddress } else { '' }
    $safeDetails = if ($Details) { Sanitize-SqlQueryString -String $Details } else { '' }

    $query = @"
INSERT INTO Vault_AuditLog (Action, CredentialName, Scope, UserID, IPAddress, Details)
VALUES ('$safeAction', '$safeCredName', '$safeScope', '$safeUserID', '$safeIP', '$safeDetails');
"@

    try {
        Invoke-PSWebSQLiteNonQuery -File $dbPath -Query $query
    } catch {
        Write-Warning "Failed to write vault audit log: $($_.Exception.Message)"
    }
}

function Get-VaultAuditLog {
    <#
    .SYNOPSIS
        Retrieves vault audit log entries
    .PARAMETER Limit
        Maximum number of entries to return
    .PARAMETER CredentialName
        Filter by credential name
    #>
    [CmdletBinding()]
    param(
        [int]$Limit = 100,

        [string]$CredentialName
    )

    $dbPath = Get-VaultDatabasePath

    if ($CredentialName) {
        $safeCredName = Sanitize-SqlQueryString -String $CredentialName
        $query = "SELECT * FROM Vault_AuditLog WHERE CredentialName = '$safeCredName' ORDER BY Timestamp DESC LIMIT $Limit;"
    } else {
        $query = "SELECT * FROM Vault_AuditLog ORDER BY Timestamp DESC LIMIT $Limit;"
    }

    return Get-PSWebSQLiteData -File $dbPath -Query $query
}

# Export module members
Export-ModuleMember -Function @(
    'Initialize-VaultDatabase'
    'Get-VaultDatabasePath'
    'Protect-VaultCredential'
    'Unprotect-VaultCredential'
    'Set-VaultCredential'
    'Get-VaultCredential'
    'Get-VaultCredentials'
    'Remove-VaultCredential'
    'Add-VaultAuditLog'
    'Get-VaultAuditLog'
)
