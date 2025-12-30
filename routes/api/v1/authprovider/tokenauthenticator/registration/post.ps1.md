# post.ps1 (Token Authenticator Registration)

This script serves as the route handler for a `POST` request to `/api/v1/authprovider/tokenauthenticator/registration`. It handles the final verification step for enabling Time-based One-Time Password (TOTP) multi-factor authentication (MFA) for a user.

## Workflow

This script is executed after the user has been presented with a QR code and has entered their first TOTP code to confirm.

1.  **Authentication Check**: Ensures that a user is logged in by checking for a `UserID` in the current session data.
2.  **Input Retrieval**: Reads the `code` submitted by the user from the request body.
3.  **Secret Verification**: Retrieves the temporary TOTP secret that was generated in the first step of registration and stored in the user's session (`$SessionData.PendingTwoFactorSecret`).
4.  **Code Validation**: Generates the current expected code using `Get-OTPCode` and compares it to the code submitted by the user.
5.  **On Success**:
    - The TOTP secret is encrypted using `Protect-String`.
    - A new set of user-friendly recovery codes is generated and hashed.
    - The encrypted secret and the hashed recovery codes are saved to the database for the user, linked to the `tokenauthenticator` provider.
    - The temporary secret is removed from the user's session.
    - A `200 OK` response is sent back to the user, containing a success message and the **plain-text recovery codes**. The user is expected to save these codes in a safe place.
6.  **On Failure**: If the code is invalid, a `400 Bad Request` is returned, prompting the user to try again.
