# post.ps1 (Get Authentication Token)

This script is a multi-step, interactive route handler for a `POST` request to `/api/v1/auth/getauthtoken`. It is designed to be called via AJAX from a web page and dynamically returns HTML content to guide a user through the login process, starting with their email address.

## Workflow

### Step 1: Initial Request (No Email Provided)

- When the initial `POST` request is made without an email in the body, the script checks for an existing valid session.
- If the user is already logged in, it returns a JSON response with a `status` of `success`.
- If the user is not logged in, it returns a JSON response with a `status` of `continue` and a `message` containing an HTML form that prompts the user to enter their email address.

### Step 2: Email Address Submitted

- Once the user submits the form, a new `POST` request is made, this time including the email address in the body.
- **Validation**: The script first validates the format of the email address.
- **Lockout Check**: It checks for any existing login lockouts for either the user or the IP address.
- **Method Discovery**: It queries the database to find all the authentication methods (e.g., "Password", "tokenauthenticator") that are enabled for the user.
- **Methods Found**: If one or more authentication methods are found, the script dynamically generates an HTML snippet containing a button for each method. This is returned in a JSON response with a `status` of `continue`. The user can then click a button to proceed to the specific login page for that authentication provider (e.g., the password entry form).
- **No User or Methods**: If no user is found for the email, or if the user has no authentication methods configured, the script logs a failed login attempt and returns a JSON response with a `status` of `fail` and an appropriate error message.
