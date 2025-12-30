# get.ps1 (Windows Auth Provider)

This script serves as the route handler for a `GET` request to the `/api/v1/authprovider/windows` endpoint. It is a key part of the Windows authentication login flow.

## Workflow

1.  **Check for Existing Session**: The script first calls `Validate-UserSession` to determine if the user is already logged in and has a valid session.
2.  **Redirect if Authenticated**: If the user is already authenticated, it immediately redirects them to the `/api/v1/auth/getaccesstoken` endpoint. It passes along the `state` and `RedirectTo` query parameters, allowing the login flow to continue and eventually redirect the user back to their original destination.
3.  **Serve Login Page**: If the user is not authenticated, the script serves the `login.html` file. This page contains the form where the user can enter their Windows credentials to be submitted in a `POST` request.
