# get.ps1 (Email Confirmation)

This script serves as the route handler for a `GET` request to `/api/v1/registration/confirm/email`. It is responsible for processing the confirmation link that a user clicks in an email to verify their email address.

## Workflow

1.  **Extract GUID**: The script retrieves a unique reference GUID from the `ref` query string parameter of the incoming request URL.
2.  **Find Confirmation Request**: It queries the `account_email_confirmation` table in the database to find a record matching the provided GUID.
3.  **Perform Security Checks**:
    - **Already Confirmed**: It checks if the email has already been confirmed (i.e., if the `response_date` field is already populated). If so, it informs the user.
    - **Session and IP Validation**: For security, it verifies that the IP address and session ID of the user clicking the link are the same as those recorded when the registration was initiated. This helps prevent account takeover if the confirmation email is intercepted.
4.  **Update Database**: If all security checks pass, the script updates the record in the database, populating the `response_date`, `response_ip`, and `response_session_id` fields to mark the email as confirmed.
5.  **Return Response**: It displays a success or failure message to the user in their browser.
