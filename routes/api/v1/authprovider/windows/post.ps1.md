# post.ps1 (Windows Auth Provider)

This script serves as the `POST` route handler for the `/api/v1/authprovider/windows` endpoint. It is responsible for processing a user's Windows credentials submitted from a login form.

## Workflow

1.  **Input Validation**: The script parses the request body to retrieve the `username` and `password`. It validates that both fields are present and meet basic formatting requirements.
2.  **Lockout Check**: It calls `Test-LoginLockout` to ensure the user or IP address is not currently locked out due to too many previous failed login attempts.
3.  **Authentication**: 
    - It creates a `PSCredential` object from the submitted credentials.
    - It then executes the `system/auth/Test-PSWebWindowsAuth.ps1` script, passing the credential to it to perform the actual validation against the Windows operating system.
4.  **On Successful Authentication**:
    - **MFA Check**: The script checks the PsWebHost database to see if the authenticated user has a multi-factor authentication provider (specifically `tokenauthenticator`) enabled.
    - **MFA Enabled**: If MFA is active, the session state is set to `mfa_required`, and the user is redirected to the MFA challenge page to enter their TOTP code.
    - **No MFA**: If the user does not have MFA enabled, the session state is set directly to `completed`, and the user is redirected to the final `/api/v1/auth/getaccesstoken` endpoint to be issued an access token.
5.  **On Failed Authentication**:
    - If the credentials are not valid, the script logs the failed attempt using `PSWebLogon`.
    - It returns a `401 Unauthorized` error to the client.
