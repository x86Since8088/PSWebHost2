# get.ps1 (Get Authentication Token)

This script serves as the `GET` route handler for the `/api/v1/auth/getauthtoken` endpoint and is the primary entry point for the user login flow.

## Workflow

1.  **State Management**: The script ensures a `state` parameter is present in the URL's query string. If it is missing, the script generates a new GUID, appends it as the `state` parameter, and redirects the user back to the same URL. This `state` is used to track the authentication flow and prevent CSRF attacks.
2.  **Session Validation**: It calls `Validate-UserSession` to check if the user already has a valid, active session.
3.  **Redirect if Authenticated**: If the user is already authenticated, they are immediately redirected to `/api/v1/auth/getaccesstoken`. This allows an already logged-in user to get a new access token without having to re-authenticate.
4.  **Initiate Login Flow**: If the user is not authenticated, the script calls `Invoke-TestToken` to create a new entry in the `LoginSessions` database table with a status of `initiated`. This officially begins the authentication attempt.
5.  **Serve Login Page**: Finally, the script serves the `getauthtoken.html` page. This HTML page contains the necessary client-side logic to make a `POST` request back to this same endpoint, which triggers the interactive, multi-step login process handled by `post.ps1`.
