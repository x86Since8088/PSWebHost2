# TOTP Authenticator Plan

This document outlines the plan for creating a new TOTP (Time-based One-Time Password) authenticator endpoint for multi-factor authentication (MFA).

## 1. Core Concept

After a user successfully completes a primary authentication method (like entering their password), the system will check if they have MFA enabled. If so, instead of completing the login, it will redirect them to a new page where they must provide a 6-digit code from their authenticator app (e.g., Google Authenticator, Authy) to finish the process.

## 2. File Structure

*   `routes/api/v1/authprovider/tokenauthenticator/`
    *   `post.ps1`: **(MFA Verification)** This endpoint will receive and validate the 6-digit TOTP code during login.
    *   `mfa.html`: A simple HTML page that presents the form for the user to enter their TOTP code.
    *   `registration/`
        *   `get.ps1`: **(Start Registration)** Generates a new TOTP secret and displays it to the user as a QR code.
        *   `post.ps1`: **(Complete Registration)** Verifies the user's first TOTP code and saves the encrypted secret to their profile.
        *   `register.html`: The page that displays the QR code and has a form to submit the first verification code.

## 3. Database Schema Requirements

The `Users` table in the database will need to be updated to support storing MFA information:

*   `TwoFactorSecret` (TEXT): To store the user's encrypted TOTP secret key. **This must be encrypted at rest.**
*   `TwoFactorEnabled` (BOOLEAN): A flag to quickly identify if a user has MFA active.
*   `RecoveryCodes` (TEXT): A column to store a list of single-use, hashed recovery codes for users who lose their authenticator device.

## 4. Registration Workflow (How Users Enable MFA)

1.  **Initiate:** The user navigates to their profile/security page and clicks "Enable MFA". This action directs them to `.../tokenauthenticator/registration/get.ps1`.
2.  **Generate Secret & QR Code:** The `get.ps1` script generates a new unique secret for the user. It creates a standard `otpauth://` URL and uses a library to render it as a QR code on the `register.html` page. The secret is stored temporarily in the user's session.
3.  **Scan and Verify:** The user scans the QR code with their authenticator app. They then enter the 6-digit code shown in the app into a form on the `register.html` page.
4.  **Confirm and Save:** The form is `POST`ed to `.../tokenauthenticator/registration/post.ps1`. This script verifies the submitted code against the secret in the session. If it's correct, the script encrypts the secret, saves it to the database, sets `TwoFactorEnabled` to `true`, generates recovery codes, and displays them to the user one time.

## 5. Multi-Factor Login Workflow (How It Works)

1.  **Primary Authentication:** The user logs in with their password as normal. The `password/post.ps1` script validates their credentials.
2.  **Check for MFA:** After password validation, the script checks if the user's `TwoFactorEnabled` flag is `true`.
3.  **Divert to MFA:**
    *   **If MFA is disabled:** The flow continues as it does now. The script calls `TestToken -Completed` and redirects to `getaccesstoken`.
    *   **If MFA is enabled:** The script does **not** complete the login yet. Instead, it calls `TestToken -AuthenticationState 'mfa_required'` to put the session into an intermediate state. It then redirects the user to `.../tokenauthenticator/mfa.html`.
4.  **MFA Challenge:** The `mfa.html` page prompts the user for their 6-digit code.
5.  **Verify Code:** The form `POST`s the code to `.../tokenauthenticator/post.ps1`. This script first confirms the session is in the `mfa_required` state. It then validates the submitted code against the user's stored `TwoFactorSecret`.
6.  **Complete Login:** If the code is valid, `post.ps1` makes the final call to `TestToken -Completed` and redirects to `getaccesstoken` to grant the access token. If the code is invalid, it displays an error.
