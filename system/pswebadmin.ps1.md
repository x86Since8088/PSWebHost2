# pswebadmin.ps1

This script is the central command-line utility for managing the PsWebHost instance. It provides a range of administrative functions for user management, session control, and database maintenance.

## Features

### User Management
- **List Users**: `-ListUsers` displays a table of all registered users.
- **Create User**: `-User <Email> -Create` initiates a prompt to create a new user with a password.
- **Manage Password**: `-User <Email> -SetPassword` allows resetting a user's password.
- **Reset MFA**: `-User <Email> -ResetMfa` removes a user's multi-factor authentication configuration, allowing them to re-register.
- **Role Management**: `-User <Email> -AssignRole <Role>` and `-RemoveRole <Role>` assign or remove roles for a user.
- **Group Management**: `-User <Email> -AddToGroup <Group>` and `-RemoveFromGroup <Group>` manage a user's group memberships.

### Session Management
- **List Sessions**: `-ListSessions` shows all active user login sessions from the database.
- **Drop Session**: `-DropSession <SessionID>` terminates a specific user session by deleting it from the database.

### Database Management
- **Validate Database**: `-ValidateDatabase` runs the `system/db/sqlite/validatetables.ps1` script to ensure the database schema is correct.
- **Backup Database**: `-BackupDatabase` creates a timestamped backup of the `pswebhost.db` file in the `backups/` directory.

### Usability
- **Argument Completion**: The script registers an argument completer for the `-User` parameter, enabling tab-completion for usernames directly from the database.
- **Environment Loading**: It automatically loads the PsWebHost environment by executing `system/init.ps1` if it's not already loaded.
