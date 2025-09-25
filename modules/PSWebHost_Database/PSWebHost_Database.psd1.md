# PSWebHost_Database.psd1

This file is the PowerShell module manifest for the `PSWebHost_Database` module.

## Summary

- **ModuleVersion**: 0.0.1
- **Author**: Edward Skarke III
- **Description**: Provides functions for interacting with the SQLite database used by the PsWebHost application.
- **RootModule**: `PSWebHost_Database.psm1`

## Exported Functions

This module exports a comprehensive set of functions for database operations, including:

- **User and Group Management**: `Add-UserToGroup`, `Get-PSWebGroup`, `Get-UserData`, `Set-UserData`, etc.
- **Authentication**: `Add-PSWebAuthProvider`, `Get-PSWebAuthProvider`, `Remove-PSWebAuthProvider`, `Set-PSWebAuthProvider`, `Get-UserProvider`, `Set-UserProvider`.
- **Roles**: `Get-PSWebRoles`, `Set-RoleForPrincipal`, `Remove-RoleForPrincipal`.
- **Session and Login Tracking**: `Get-LastLoginAttempt`, `Set-LastLoginAttempt`, `Get-LoginSession`, `Set-LoginSession`.
- **Card and UI Settings**: `Get-CardSettings`, `Set-CardSettings`, `Set-CardSession`.
- **Generic Database Operations**: `Get-PSWebSQLiteData`, `Invoke-PSWebSQLiteNonQuery`, `New-PSWebSQLiteData`, `New-PSWebSQLiteTable`.
- **Database Initialization**: `Initialize-PSWebHostDatabase`.
