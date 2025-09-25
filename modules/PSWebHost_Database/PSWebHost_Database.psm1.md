# PSWebHost_Database.psm1

This PowerShell module file contains the core implementation for all database-related functions in the PsWebHost project. It uses the `sqlite3.exe` command-line tool to interact with the SQLite database.

## Key Responsibilities

- **Database Initialization**: The `Initialize-PSWebHostDatabase` function is responsible for creating the entire database schema, including tables for users, roles, groups, sessions, authentication providers, and application settings.

- **Generic Data Operations**: It provides a set of generic functions for basic CRUD (Create, Read, Update, Delete) operations:
  - `New-PSWebSQLiteTable`: Creates a new table.
  - `New-PSWebSQLiteData`: Inserts a new record.
  - `Get-PSWebSQLiteData`: Executes a `SELECT` query and returns the data as PowerShell objects.
  - `Invoke-PSWebSQLiteNonQuery`: A versatile function for executing `INSERT`, `UPDATE`, and `DELETE` statements.

- **User and Authentication Management**:
  - Manages user authentication providers, roles, and group memberships.
  - Tracks login attempts for security features like account lockout.
  - Stores and retrieves arbitrary data associated with a user profile.

- **Session Management**:
  - `Set-LoginSession` and `Get-LoginSession` handle the creation and retrieval of user login sessions.
  - `Invoke-TestToken` is a key function for managing the state of authentication tokens during the login process.

- **Application-Specific Logic**:
  - Includes functions like `Get-CardSettings` and `Set-CardSettings` to manage settings for the UI's card-based dashboard.

- **Helper Functions**:
  - Contains helper functions like `ConvertFrom-CompressedBase64` to decompress and decode data retrieved from the database.
