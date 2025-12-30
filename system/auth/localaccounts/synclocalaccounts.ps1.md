# synclocalaccounts.ps1

This script is designed to synchronize local Windows user and group accounts from the host machine into the PsWebHost database. This allows the web application to use these local accounts for authentication and authorization.

## Key Functions

### User Synchronization

1.  **Retrieve Local Users**: The script uses `Get-LocalUser` to fetch all user accounts on the local machine.
2.  **Format User Data**: For each enabled user, it:
    - Creates a unique `UserID` in the format `username@computername`.
    - Checks for account lockout status.
    - Parses the output of the `net user` command to determine configured logon hours.
    - Gathers additional details such as the user's full name, description, and password policy information.
3.  **Database Update**: It calls the `Set-UserProvider` function to insert or update the user's record in the database, registering them with the `local` authentication provider.

### Group and Membership Synchronization

1.  **Retrieve Local Groups**: It uses `Get-LocalGroup` to get all local groups.
2.  **Sync Groups**: Each local group is added or updated in the `User_Groups` table in the database.
3.  **Sync Memberships**: It iterates through the members of each local group and creates corresponding entries in the `User_Groups_Map` table to link users to their respective groups.
4.  **Admin Role Mapping**: The script specifically assigns the `system_admin` role in PsWebHost to any user who is a member of the local `Administrators` group, effectively granting them administrative privileges in the application.
