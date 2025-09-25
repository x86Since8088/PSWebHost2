# PSWebHost_Support.psm1

This PowerShell module provides a collection of essential helper and support functions that form the backbone of the PsWebHost application. It handles HTTP request processing, session management, logging, and more.

## Core Features

### HTTP Request Handling

- **Process-HttpRequest**: This is the main request routing engine. It inspects the URL and HTTP method of every incoming request and dispatches it to the appropriate handler. It is responsible for:
  - Serving static files (e.g., CSS, JS, images) from the `/public` directory.
  - Managing session cookies.
  - Performing security checks and authorization based on route-specific `.security.json` files.
  - Executing the corresponding PowerShell script for a given route.

- **context_reponse**: A versatile function for constructing and sending HTTP responses. It can send responses as strings, byte arrays, or full files, and it automatically determines the correct MIME type for files.

- **Get-RequestBody**: A simple helper to read the body content from an incoming HTTP request.

### Session Management

- **In-Memory Caching**: The module uses a global synchronized hashtable (`$global:PSWebSessions`) to cache session data for performance.
- **Get-PSWebSessions**: Retrieves a user's session. If the session is not in the in-memory cache, it attempts to load it from the database.
- **Set-PSWebSession**: Updates a user's session data and persists the changes to the database.
- **Remove-PSWebSession**: Deletes a session from both the cache and the database.
- **Validate-UserSession**: A critical security function that validates a session by checking if it has expired and if the User-Agent string of the current request matches the one that created the session.
- **Sync-SessionStateToDatabase**: A function that runs periodically to synchronize session data from the in-memory cache back to the database.

### Logging and Events

- **Write-PSWebHostLog**: A centralized function for queuing log entries. It can also create structured event objects for monitoring.
- **Read-PSWebHostLog**: A function to read and filter logs from the log file.
- **Event Management**: Includes functions (`Start-PSWebHostEvent`, `Complete-PSWebHostEvent`, `Get-PSWebHostEvents`) for creating and managing structured application events.

### Utility Functions

- **ConvertTo-CompressedBase64**: A helper function that GZip compresses a string and then Base64 encodes it, useful for efficiently storing larger data objects in the database.
