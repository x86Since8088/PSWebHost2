# init.ps1

This script is the central initialization script for the PsWebHost application. It runs at startup to configure the global environment, load settings, secure sensitive data, and prepare all necessary modules and services before the web server begins listening for requests.

## Key Responsibilities

1.  **Global Environment Setup**:
    - Establishes the project's root directory.
    - Creates the `$Global:PSWebServer` variable, which is a synchronized hashtable used as a central repository for all global application data, including configuration, session state, and module tracking.

2.  **Configuration Loading**:
    - Reads the `config/settings.json` file and populates the `$Global:PSWebServer.Config` object.
    - Stores the file's last modification time to enable dynamic reloading if the settings are changed while the server is running.

3.  **Sensitive Data Handling**:
    - Scans the loaded configuration for plaintext secrets, such as the SMTP password and OAuth client secrets for Google and Office 365.
    - Converts these plaintext values into `SecureString` objects for safer handling in memory.
    - Overwrites the original plaintext properties in the in-memory configuration with `null` to reduce the risk of secret exposure.

4.  **Module Management**:
    - Defines a custom `Import-TrackedModule` function that imports a module and also records its file path and last write time. This tracking information is crucial for the hot-reloading feature, which automatically re-imports modules when they are updated.
    - Imports all core application modules using this function.

5.  **Asynchronous Logging**:
    - Sets up a thread-safe concurrent queue (`$global:PSWebHostLogQueue`) for log messages.
    - Spawns a background PowerShell job dedicated to writing log entries from the queue to a file. This ensures that logging operations do not block the main web server thread, improving performance.

6.  **Installation Validation**:
    - As its final action, it executes the `validateInstall.ps1` script to perform a full check of all dependencies, tools, and the database schema, ensuring the environment is ready before the web server starts.
