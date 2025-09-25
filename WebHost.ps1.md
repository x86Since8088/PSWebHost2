# WebHost.ps1

This script is the main entry point for the PowerShell-based web server.

## Functionality

- **Initialization**: Sets up the web server environment by running `system/init.ps1`.
- **Command-line Arguments**: Accepts parameters to control its behavior:
  - `-RunInProcess`: Runs the server in the current process.
  - `-ShowVariables`: Displays variables for debugging and exits.
  - `-AuthenticationSchemes`: Sets the authentication schemes for the listener (default is "Anonymous").
  - `-Async`: Enables asynchronous request handling.
  - `-Port`: Specifies the port for the listener (default is 8080).
  - `-ReloadOnScriptUpdate`: Automatically restarts the server when the script file is modified.
  - `-StopOnScriptUpdate`: Stops the server when the script file is modified.
- **HTTP Listener**: Creates and starts an `System.Net.HttpListener` to listen for incoming HTTP requests on the specified port.
- **Request Handling**: Enters a loop to continuously accept and process incoming requests. It can handle requests both synchronously and asynchronously based on the `-Async` switch.
- **Dynamic Reloading**:
  - **Script Reload**: If `-ReloadOnScriptUpdate` is used, it monitors the `WebHost.ps1` file for changes and restarts the server.
  - **Module Reload**: It periodically checks for changes in loaded PowerShell modules and reloads them if they have been updated.
  - **Settings Reload**: It monitors the `config/settings.json` file for changes and reloads the configuration.
- **Logging**: Captures and displays log messages.
- **Cleanup**: Ensures a graceful shutdown by stopping the listener and cleaning up resources when the script exits.
