# get.ps1 (Session API)

This script serves as the route handler for a `GET` request to the `/api/v1/session` endpoint. Its primary purpose is to provide information about the current user's authentication status and session details.

## Workflow

1.  **Session Validation**: The script begins by calling the `Validate-UserSession` function to verify that the current session is active, not expired, and matches the user's browser.
2.  **Authentication Check**: If the session is valid, it checks for the presence of a `UserID` in the session data.
3.  **Role Retrieval**: For an authenticated user, it calls `Get-UserRoles` to fetch a list of all roles assigned to that user.
4.  **Construct Response**: It builds a JSON object containing a `user` property. 
    - If the user is authenticated, this property will contain an object with their `UserName` and an array of their `Roles`.
    - If the user is not authenticated or the session is invalid, the `user` property will be `null`.
5.  **Send JSON Response**: The final object is converted to a JSON string and sent back to the client with a `Content-Type` of `application/json`.
