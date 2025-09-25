# smtp.psm1

This PowerShell module provides a centralized function for sending emails via an SMTP server, with a focus on security and detailed error handling.

## Functions

### Send-SmtpEmail

This is the sole function in the module, designed to be a robust wrapper around PowerShell's `Send-MailMessage` cmdlet.

**Workflow**:

1.  **Secure Protocol**: It starts by enforcing modern security standards, setting the security protocol to TLS 1.2 and TLS 1.3.
2.  **Configuration Loading**: It retrieves all necessary SMTP settings (server, port, from address, username) from the global `$Global:PSWebServer.Config.Smtp` configuration object.
3.  **Credential Handling**: It securely accesses the SMTP password, which is expected to be stored as a `SecureString` in the configuration (`$smtpSettings.PasswordSecureString`). It then creates a `PSCredential` object for authentication.
4.  **Email Transmission**: It calls `Send-MailMessage` with the provided parameters, forcing the connection to use SSL for encryption.
5.  **Error Handling**: The function includes a comprehensive `try...catch` block that specifically catches `SmtpException`. It analyzes the exception's status code to provide detailed, user-friendly error messages for common SMTP issues, such as:
    -   Authentication failures (e.g., wrong password, app password required).
    -   Mailbox issues (e.g., unavailable, busy).
    -   General service availability problems.
