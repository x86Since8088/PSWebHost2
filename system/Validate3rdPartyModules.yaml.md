# Validate3rdPartyModules.yaml

This YAML file specifies the third-party PowerShell modules that are required for the PsWebHost project to function correctly. The `system/Validate3rdPartyModules.ps1` script reads this file to validate and download the necessary dependencies.

## Defined Modules

Each entry in the file defines a module with its `Name`, `Repository`, and a specific `Version` to ensure a consistent and reproducible environment.

- **TOTP**: 
  - **Version**: `1.2.0`
  - **Repository**: `PSGallery`
  - **Purpose**: Provides Time-based One-Time Password (TOTP) functionality, which is essential for the multi-factor authentication (MFA) feature.

- **powershell-yaml**:
  - **Version**: `0.4.2`
  - **Repository**: `PSGallery`
  - **Purpose**: Used to parse YAML files. It is a critical dependency for the validation script itself, as it needs this module to read its own configuration.

- **QRCodeGenerator**:
  - **Version**: `2.0.0`
  - **Repository**: `PSGallery`
  - **Purpose**: Used to generate the QR codes that users scan with their authenticator apps during MFA setup.
