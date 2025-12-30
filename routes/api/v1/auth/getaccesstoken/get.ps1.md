# get.ps1 (Get Access Token)

This script serves as the `GET` route handler for the `/api/v1/auth/getaccesstoken` endpoint. It represents the final and most critical step in the user authentication process, where a user who has successfully authenticated is granted an access token.

## Workflow

1.  **Final Session Validation**: The script calls `Invoke-TestToken` to verify that the user's session is in the `completed` state. This is the definitive check to ensure the user has successfully passed all required authentication factors (e.g., password, MFA) in the preceding steps.
2.  **On Success (Session is 'completed')**:
    - The `UserID` from the temporary, completed login record is transferred to the main user session.
    - A new, cryptographically random access token is generated.
    - The access token and its expiration time (set to 1 hour) are stored in the user's session data.
    - The user is redirected to the URL specified in the `RedirectTo` query parameter. If no redirect URL is provided, a simple success message is displayed.
3.  **On Failure (Session is not 'completed')**:
    - If no session is found in the `completed` state, it indicates that the user has not finished the authentication flow correctly.
    - The script redirects the user back to the beginning of the login process at `/api/v1/auth/getauthtoken`, forcing them to start over.
