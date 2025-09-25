# delete.ps1 (Users API)

This script serves as the route handler for `DELETE` requests to the `/api/v1/users` endpoint. Its purpose is to delete a user and all of their associated data from the database.

## Workflow

1.  **Get UserID**: The script retrieves the `UserID` of the user to be deleted from the request's query string (e.g., `/api/v1/users?UserID=someuser`).
2.  **Input Validation**: It checks that a `UserID` has been provided. If not, it returns a `400 Bad Request` error.
3.  **Delete Associated Data**: To ensure a clean deletion, the script first finds the user's internal unique ID (`ID`) from the `Users` table. It then uses this `ID` to delete all corresponding records from the `User_Data` table, which stores related information like authentication provider registrations.
4.  **Delete User Record**: After the associated data is removed, the script deletes the primary user record from the `Users` table.
5.  **Send Response**: A success message is returned in the HTTP response.
