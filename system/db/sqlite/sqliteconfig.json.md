# sqliteconfig.json

This JSON file defines the schema for the SQLite database used by the PsWebHost application. It is used by the `system/db/sqlite/validatetables.ps1` script to automatically create and validate the database structure.

## Schema Definition

The file contains a list of table definitions. Each table has a name and a list of columns, with each column specifying its name, data type, and constraints.

### Tables

- **Users**: Stores the primary information for each user.
  - `ID`: A unique identifier for the user (GUID).
  - `UserID`: The user's login name.
  - `Email`: The user's email address.
  - `PasswordHash`: The user's hashed password.

- **User_Data**: A flexible key-value table for storing additional data related to a user, linked by the user's `ID`.
  - `ID`: The foreign key to the `Users` table.
  - `Name`: The name of the data key (e.g., `Auth_tokenauthenticator_Registration`).
  - `Data`: The value, stored as a `BLOB`.

- **LoginSessions**: Tracks active user sessions.
  - `SessionID`: The unique session identifier.
  - `UserID`: The user associated with the session.
  - `Provider`: The authentication provider used (e.g., `Password`, `Windows`).
  - `AuthenticationTime`: The timestamp when the user authenticated.
  - `LogonExpires`: The timestamp when the session expires.
  - `AuthenticationState`: The current state of the login process (e.g., `initiated`, `mfa_required`, `completed`).
  - `UserAgent`: The browser User-Agent string for the session.

- **LoginLockout**: Tracks failed login attempts to implement security lockouts.
  - `IPAddress`: The IP address from which the login attempt was made.
  - `Username`: The username used in the attempt.
  - `FailedAttempts`: A counter for failed attempts.
  - `LockedUntil`: A timestamp indicating when the lockout period ends.
