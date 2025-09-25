# PSWebHost_Authentication.psm1

This PowerShell module provides functions for user authentication, user management, and security-related operations within the PSWebHost environment.

## Functions

### Authentication
- **Get-AuthenticationMethod**: Returns a list of available authentication methods.
- **Get-AuthenticationMethodForm**: Provides the necessary form fields for a given authentication method.
- **Invoke-AuthenticationMethod**: Authenticates a user based on the specified method (e.g., "Password", "Windows") and provided credentials.
- **PSWebLogon**: Logs login attempts (success or failure), and handles login lockout logic based on violation counts.
- **Test-LoginLockout**: Checks if a user or IP address is currently locked out from logging in.

### User and Role Management
- **Get-PSWebHostUser**: Retrieves a user's details from the database based on their email address.
- **Get-PSWebHostUsers**: Fetches a list of all user emails from the database.
- **Get-UserAuthenticationMethods**: Gets the authentication methods enabled for a specific user.
- **Get-UserRoles**: Retrieves the roles assigned to a user, including those inherited from groups.
- **New-PSWebHostUser**: Creates a new user with a salted and hashed password.
- **New-PSWebUser**: Creates a new user record in the database.

### Security and Validation
- **Test-IsValidEmailAddress**: Validates the format of an email address.
- **Test-StringForHighRiskUnicode**: Scans a string for high-risk or non-printable Unicode characters to prevent various injection and spoofing attacks.
- **Test-IsValidPassword**: Checks if a password meets the defined complexity requirements.
- **Protect-String**: Encrypts a string to a `SecureString` format for the current user and machine.
- **Unprotect-String**: Decrypts a `SecureString` back to plain text.
