# post.ps1 (Token Authenticator)

This script serves as the route handler for a `POST` request to `/api/v1/authprovider/tokenauthenticator`. It is responsible for validating a Time-based One-Time Password (TOTP) during a multi-factor authentication (MFA) login process.

## Workflow

1.  **Dependency Check**: Verifies that the required `OTP` PowerShell module is installed.
2.  **Session State Verification**: It calls `Invoke-TestToken` to confirm that the user's current session is in the `mfa_required` state. This ensures that this second authentication factor is only performed after the primary authentication (e.g., password) has succeeded.
3.  **Input Retrieval**: Reads the request body to extract the `code` submitted by the user.
4.  **Secret Retrieval**: Fetches the current user's TOTP secret, which is stored in an encrypted format in the database, and decrypts it.
5.  **Code Validation**: Generates the current expected code using `Get-OTPCode` and compares it to the code submitted by the user.
6.  **Success**: If the code is valid, it marks the authentication as complete by calling `Invoke-TestToken -Completed`. It then redirects the user to `/api/v1/auth/getaccesstoken` to obtain their final session access token.
7.  **Failure**: If the code is invalid, it returns a `400 Bad Request` error. The script also resets the session state back to `mfa_required`, allowing the user to attempt the MFA challenge again.
