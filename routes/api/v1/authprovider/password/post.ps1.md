# post.ps1 (Password Auth Provider)

This script serves as the `POST` route handler for the `/api/v1/authprovider/password` endpoint. It is responsible for processing a user's email and password login attempt.

## Workflow

1.  **Input Validation**: The script parses the request body to retrieve the `email` and `password`. It validates that both fields are present and conform to the required formats using `Test-IsValidEmailAddress` and `Test-IsValidPassword`.
2.  **Lockout Check**: It calls `Test-LoginLockout` to ensure the user or IP address is not currently locked out due to too many previous failed login attempts. If a lockout is active, it returns a `429 Too Many Requests` error.
3.  **Authentication**: It uses `Invoke-AuthenticationMethod` with the provider name `Password` to securely compare the provided password against the hashed password stored in the database.
4.  **On Successful Authentication**:
    - **MFA Check**: The script checks if the user has a multi-factor authentication provider (specifically `tokenauthenticator`) enabled.
    - **MFA Enabled**: If MFA is active, the session state is set to `mfa_required`, and the user is redirected to the MFA challenge page to enter their TOTP code.
    - **No MFA**: If the user does not have MFA enabled, the session state is set directly to `completed`, and the user is redirected to the final `/api/v1/auth/getaccesstoken` endpoint to be issued an access token.
5.  **On Failed Authentication**:
    - If the credentials are incorrect, the script logs the failed attempt using `PSWebLogon`.
    - It returns a `401 Unauthorized` error to the client.
6.  **Error Handling**: A `try...catch` block is used to gracefully handle any unexpected errors, which are logged before a `500 Internal Server Error` is returned.
