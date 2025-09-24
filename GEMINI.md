## Project Context for Gemini CLI

This project is a PowerShell-based web host, recreated from scratch to improve modularity, security, and maintainability.

### Core Components:

*   **`WebHost.ps1`**: Main entry point for the web host.
*   **`config/settings.json`**: Basic configuration settings.
*   **`modules/`**: Contains PowerShell modules (`.psm1` files) for reusable functions.
*   **`routes/`**: Contains PowerShell scripts that define web routes and their handlers.
*   **`system/`**: Contains core system scripts and functions, including `validateInstall.ps1` for dependency checks.
*   **`tests/`**: Contains Pester unit tests for various components.

### Key Features:

*   **Input Sanitization**: Employs `Sanitize-HtmlInput` and `Sanitize-FilePath` to mitigate common web vulnerabilities.
*   **Modular Design**: Functions are organized into PowerShell modules for better reusability and maintainability.
*   **Dependency Validation**: `validateInstall.ps1` checks for required PowerShell modules and the SQLite command-line tool (with Winget installation if missing).

### Development Notes:

*   **Execution Policy**: Ensure your PowerShell execution policy allows running local scripts (e.g., `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`).
*   **File Permissions**: Ensure write permissions for `PsWebHost_DataStore` and its subdirectories (e.g., `logs`).
