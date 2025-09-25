# validateInstall.ps1

This script is a comprehensive validator for the PsWebHost environment. It is designed to be run to ensure that all necessary dependencies, modules, and tools are correctly installed and configured before starting the web server.

## Features

- **PowerShell Module Validation**:
  - Reads a list of required modules and their minimum versions from `system/RequiredModules.json`.
  - Checks if each module is installed and if its version is sufficient.
  - Dynamically adds the project's local `modules` directory to the `PSModulePath` to make custom modules available.

- **Third-Party Dependency Management**:
  - Executes the `Validate3rdPartyModules.ps1` script to automatically download and validate modules from external sources like the PSGallery (e.g., `TOTP`, `powershell-yaml`).

- **SQLite Toolchain Verification**:
  - Checks if the `sqlite3` command-line tool is present and accessible in the system's PATH.
  - If `sqlite3` is not found, it attempts to automatically install it using the `winget` package manager.
  - Provides an `-Upgrade` switch to allow for upgrading the SQLite tool via `winget`.

- **Database Schema Validation**:
  - After checking for tools and modules, it runs the `db/sqlite/validatetables.ps1` script to verify that the database schema is correctly configured.

- **Debugging**: 
  - Includes a `-ShowVariables` switch that, when used, will output a JSON representation of the script's key variables for debugging purposes.
