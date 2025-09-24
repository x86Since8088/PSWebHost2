# PsWebAdmin Administration Script

## Overview

`pswebadmin.ps1` is intended to be the central command-line utility for managing the PsWebHost instance. It provides a safe and structured way to perform administrative tasks, reducing the need for manual database or file editing. The script is designed around distinct modes for handling different aspects of the system.

---

## 1. Implementation Roadmap

The implementation will be broken down into three main feature sets:

### Phase 1: User and Group Management

This mode is for managing user accounts, roles, and group memberships. It will be the primary interface for all user-related administration.

**Core Functionality:**

*   View details for a specific user (roles, groups, MFA status).
*   Create new user accounts.
*   Set or reset a user's password.
*   Enable, disable, or reset a user's MFA configuration.
*   Assign roles to a user (e.g., 'admin', 'editor').
*   Add or remove users from groups.
*   List all users, roles, or groups.

**Proposed Command Syntax:**

```powershell
# View a user's details
.\pswebadmin.ps1 -User 'user@email.com'

# Create a new user (will prompt for password)
.\pswebadmin.ps1 -User 'new@email.com' -Create

# Set a user's password
.\pswebadmin.ps1 -User 'user@email.com' -SetPassword

# Reset a user's MFA
.\pswebadmin.ps1 -User 'user@email.com' -ResetMfa

# Assign a role to a user
.\pswebadmin.ps1 -User 'user@email.com' -AssignRole 'admin'

# List all users
.\pswebadmin.ps1 -ListUsers
```

### Phase 2: Database and Session Administration

This mode provides tools for direct database maintenance and managing active user sessions.

**Core Functionality:**

*   Manually trigger the database schema validation.
*   Create a backup of the live database file.
*   List all active user sessions from the `LoginSessions` table.
*   Forcibly terminate a specific user session.

**Proposed Command Syntax:**

```powershell
# Validate the database schema against the config file
.\pswebadmin.ps1 -Database -Validate

# Create a backup of the database
.\pswebadmin.ps1 -Database -Backup

# List all active sessions
.\pswebadmin.ps1 -Session -List

# Drop a specific session
.\pswebadmin.ps1 -Session -Drop 'session-id-guid'
```

### Phase 3: JSON Configuration Management

This mode provides a structured way to view and edit project configuration files, building on the original script's intent.

**Core Functionality:**

*   Display the contents of a specified JSON file.
*   Set a value for a specific key within a JSON file.
*   Automatically create a backup before modifying any file.

**Proposed Command Syntax:**

```powershell
# View a configuration file
.\pswebadmin.ps1 -Json 'config/settings.json'

# Set a value in a configuration file
.\pswebadmin.ps1 -Json 'config/settings.json' -Set @{ 'DebugMode' = $true }
```

---

## 2. Dependencies and Resources

The `pswebadmin.ps1` script will not operate in a vacuum. It will be built upon the existing modular structure of the project.

*   **Core Modules:** It will heavily rely on functions exported from:
    *   `PSWebHost_Database.psm1`: For all direct database interactions (querying and non-querying).
    *   `PSWebHost_Authentication.psm1`: For functions related to user creation, password hashing, and MFA secret management.
    *   `PSWebHost_Support.psm1`: For session management functions.

*   **Database and Schema:**
    *   It will directly interface with the `PsWebHost_Data/pswebhost.db` SQLite file.
    *   The `-Database -Validate` command will directly call the `system/db/sqlite/validatetables.ps1` script, which in turn uses `system/db/sqlite/sqliteconfig.json`.

*   **Argument Completers:** The existing tab-completion logic for parameters like `-User`, `-Role`, and `-Group` is a critical feature and will be preserved and expanded as new commands are implemented.
