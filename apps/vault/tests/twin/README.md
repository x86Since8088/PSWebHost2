# Vault Twin Tests

Comprehensive tests for the Vault app - Secure credential storage for PSWebHost nodes and services using DPAPI encryption.

## Overview

The Vault app provides secure credential storage with support for:
- Password credentials
- Certificate credentials (PFX, PEM, CER formats)
- API Key credentials
- DPAPI encryption (Windows Data Protection API)
- Audit logging for all operations
- Scope-based organization (global, node, service, api_key)

## Running Tests

### All Tests
```powershell
.\vault.Tests.ps1 -TestMode All
```

### CLI Tests Only
```powershell
.\vault.Tests.ps1 -TestMode CLI
```

### Integration Tests Only
```powershell
.\vault.Tests.ps1 -TestMode Integration
```

### Browser Tests
Browser tests must be run through the UnitTests app:

1. Start PSWebHost:
   ```powershell
   pwsh WebHost.ps1
   ```

2. Navigate to: http://localhost:8888/apps/UnitTests/cards/unit-test-runner

3. Select "vault Browser Tests" from the test suite dropdown

4. Click "Run Tests"

## Test Coverage

### CLI Tests
- [ ] Module loading (PSWebVault)
- [ ] Function availability (Get-VaultCredential, Set-VaultCredential, etc.)
- [ ] Credential encryption/decryption (DPAPI)
- [ ] Database operations (Create, Read, Update, Delete)
- [ ] Credential type support (Password, Certificate, API_Key)
- [ ] Scope filtering
- [ ] Audit logging
- [ ] Error handling

### Browser Tests
- [ ] Component loading (vault-home)
- [ ] UI rendering
- [ ] Event handling
- [ ] API integration (credentials endpoint)
- [ ] Local storage operations
- [ ] Form validation
- [ ] Error display

### Integration Tests
- [ ] Status endpoint (/apps/vault/api/v1/status)
- [ ] UI element endpoints (/apps/vault/api/v1/ui/elements/vault-home)
- [ ] Credentials GET (list and query)
- [ ] Credentials POST (create)
- [ ] Credentials DELETE (remove)
- [ ] Authentication (admin, vault_admin roles)
- [ ] Authorization (role-based access)
- [ ] Audit log retrieval

## Adding Tests

### PowerShell Test
Edit vault.Tests.ps1 and add to Test-CLIFunctionality:
```powershell
# Example: Test credential encryption
$testCred = Set-VaultCredential -Name "test-cred" -CredentialType "Password" `
    -Username "testuser" -Password "TestPass123" -Scope "test"

Test-Assert -TestName "Credential Creation" `
    -Condition ($testCred -eq $true) `
    -Message "Should create credential successfully"
```

### Browser Test
Edit browser-tests.js and add a new test method:
```javascript
async testCredentialListing() {
    const result = await this.apiCall('/apps/vault/api/v1/credentials');
    if (!result.success) {
        throw new Error('Failed to list credentials');
    }
    if (!Array.isArray(result.credentials)) {
        throw new Error('Credentials should be an array');
    }
    return 'Credential listing works';
}
```

## Security Notes

**CRITICAL**: The Vault app uses Windows DPAPI (Data Protection API) for encryption:
- Credentials are encrypted per-user by default (CurrentUser scope)
- Encrypted data can only be decrypted by the same user on the same machine
- Requires the `admin` or `vault_admin` role for all operations
- All operations are logged in the Vault_AuditLog table

**WARNING**: Do NOT:
- Store vault credentials in version control
- Share the vault.db file between machines
- Access vault data without proper authentication
- Bypass audit logging

## API Endpoints

### Status
- **GET** `/apps/vault/api/v1/status` - Get vault health and statistics

### Credentials
- **GET** `/apps/vault/api/v1/credentials` - List all credentials (no secrets)
  - Query params: `?name=<name>&scope=<scope>&credentialType=<type>`
- **POST** `/apps/vault/api/v1/credentials` - Create/update credential
- **DELETE** `/apps/vault/api/v1/credentials` - Delete credential
  - Query params: `?name=<name>&scope=<scope>`

### UI Elements
- **GET** `/apps/vault/api/v1/ui/elements/vault-home` - Main vault manager interface

## Module Functions

### Core Functions
- `Set-VaultCredential` - Store or update a credential
- `Get-VaultCredential` - Retrieve a credential (optionally decrypted)
- `Get-VaultCredentials` - List all credentials in scope
- `Remove-VaultCredential` - Delete a credential

### Encryption Functions
- `Protect-VaultCredential` - Encrypt using DPAPI
- `Unprotect-VaultCredential` - Decrypt using DPAPI

### Audit Functions
- `Add-VaultAuditLog` - Log an action
- `Get-VaultAuditLog` - Retrieve audit log entries

### Utility Functions
- `Initialize-VaultDatabase` - Set database path
- `Get-VaultDatabasePath` - Get database path

## Documentation
See [Twin Test Framework README](../../../system/utility/templates/TWIN_TESTS_README.md)
