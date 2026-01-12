# Vault App Initialization Script
# This script runs during PSWebHost startup when the vault app is loaded

param(
    [hashtable]$PSWebServer,
    [string]$AppRoot
)

$MyTag = '[Vault:Init]'

# Import the PSWebVault module
$modulePath = Join-Path $AppRoot "modules\PSWebVault.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force -DisableNameChecking
    Write-Verbose "$MyTag Loaded PSWebVault module" -Verbose
}

# Initialize vault database
$vaultDbPath = Join-Path $AppRoot "data\vault.db"
$dataDir = Join-Path $Global:PSWebServer['DataRoot'] "apps\vault"

# Ensure data directory exists
if (-not (Test-Path $dataDir)) {
    New-Item -Path $dataDir -ItemType Directory -Force | Out-Null
    Write-Verbose "$MyTag Created vault data directory: $dataDir" -Verbose
}

# Create vault database and schema if it doesn't exist
$needsSchemaUpdate = $false
if (-not (Test-Path $vaultDbPath)) {
    $needsSchemaUpdate = $true
    Write-Verbose "$MyTag Creating vault database: $vaultDbPath" -Verbose
} else {
    # Check if schema needs updating (check for CredentialType column)
    try {
        $schemaCheck = Get-PSWebSQLiteData -File $vaultDbPath -Query "PRAGMA table_info(Vault_Credentials);"
        $hasCredentialType = $schemaCheck | Where-Object { $_.name -eq 'CredentialType' }
        if (-not $hasCredentialType) {
            $needsSchemaUpdate = $true
            Write-Verbose "$MyTag Vault database schema needs updating" -Verbose
        }
    } catch {
        $needsSchemaUpdate = $true
    }
}

if ($needsSchemaUpdate) {
    # Drop old table if exists and recreate with new schema
    $dropTableQuery = "DROP TABLE IF EXISTS Vault_Credentials;"

    $createTableQuery = @"
CREATE TABLE IF NOT EXISTS Vault_Credentials (
    ID INTEGER PRIMARY KEY AUTOINCREMENT,
    Name TEXT NOT NULL,
    CredentialType TEXT DEFAULT 'Password' CHECK(CredentialType IN ('Password', 'Certificate', 'API_Key')),
    Username TEXT,
    EncryptedSecret TEXT,
    CertificateFormat TEXT CHECK(CertificateFormat IN ('PFX', 'PEM', 'CER', NULL, '')),
    Scope TEXT DEFAULT 'global',
    Description TEXT,
    CreatedBy TEXT,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    Metadata TEXT,
    UNIQUE(Name, Scope)
);

CREATE TABLE IF NOT EXISTS Vault_AuditLog (
    ID INTEGER PRIMARY KEY AUTOINCREMENT,
    Action TEXT NOT NULL,
    CredentialName TEXT,
    Scope TEXT,
    UserID TEXT,
    Timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    IPAddress TEXT,
    Details TEXT
);

CREATE INDEX IF NOT EXISTS idx_credentials_name ON Vault_Credentials(Name);
CREATE INDEX IF NOT EXISTS idx_credentials_scope ON Vault_Credentials(Scope);
CREATE INDEX IF NOT EXISTS idx_credentials_type ON Vault_Credentials(CredentialType);
CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON Vault_AuditLog(Timestamp);
"@

    try {
        # Only drop if updating existing database
        if (Test-Path $vaultDbPath) {
            Invoke-PSWebSQLiteNonQuery -File $vaultDbPath -Query $dropTableQuery
            Write-Warning "$MyTag Dropped old Vault_Credentials table for schema update"
        }
        Invoke-PSWebSQLiteNonQuery -File $vaultDbPath -Query $createTableQuery
        Write-Verbose "$MyTag Vault database schema created/updated successfully" -Verbose
    } catch {
        Write-Warning "$MyTag Failed to create vault database schema: $($_.Exception.Message)"
    }
}

# Store vault configuration in PSWebServer
if (-not $PSWebServer.ContainsKey('Vault')) {
    $PSWebServer['Vault'] = @{
        DatabasePath = $vaultDbPath
        AppRoot = $AppRoot
        Initialized = Get-Date
    }
}

Write-Verbose "$MyTag Vault app initialization complete" -Verbose
