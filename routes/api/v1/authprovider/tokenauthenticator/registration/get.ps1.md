# get.ps1 (Token Authenticator Registration)

This script serves as the route handler for a `GET` request to `/api/v1/authprovider/tokenauthenticator/registration`. It is the first step in the process of enabling Time-based One-Time Password (TOTP) multi-factor authentication (MFA) for a user.

## Workflow

The script has two primary modes of operation, determined by the query string.

### 1. Initial Registration Page Load

When a user navigates to the registration endpoint, this script performs the following actions:

- **Authentication Check**: Verifies that the user is logged in. If not, they are redirected to the login page.
- **Generate Secret**: Creates a new TOTP secret and setup URI using the `New-OTPSecret` function.
- **Store Secret in Session**: The newly generated secret object (which includes the key and the setup URI) is stored temporarily in the user's session data under the key `PendingTwoFactorSecret`. This is used later for verification and QR code generation.
- **Serve HTML Page**: It loads the `register.html` file, injects the plain-text secret key into the page for users who want to perform manual setup, and returns the HTML to the user.

### 2. QR Code Generation

The `register.html` page contains an `<img>` tag that makes a subsequent request to this same endpoint with the query parameter `?qrcode=true`.

- When this request is received, the script retrieves the `PendingTwoFactorSecret` from the session.
- It uses the `New-QRCode` function to generate a PNG image of the QR code from the `SetupUri`.
- The generated QR code image is returned directly in the HTTP response with a content type of `image/png`.
