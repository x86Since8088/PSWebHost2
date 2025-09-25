# Validate3rdPartyModules.ps1

This script is responsible for validating and downloading third-party PowerShell modules required by the project.

## Functionality

- **Configuration-Driven**: It reads a `Validate3rdPartyModules.yaml` file to determine which modules are required, their specific versions, and from which repository to download them.

- **Local Module Cache**: It uses a `ModuleDownload` directory within the project root to store downloaded modules, keeping dependencies project-local.

- **Dynamic PSModulePath**: The script temporarily adds the `ModuleDownload` directory to the `PSModulePath` environment variable for the current session. This allows PowerShell to find and load the locally-saved modules.

- **YAML Dependency**: It checks if the `powershell-yaml` module is installed and, if not, attempts to install it from the PSGallery. This is a prerequisite for parsing the configuration file.

- **Validation and Download**: For each module defined in the YAML configuration, the script:
  1. Checks if the module is already present in the local cache.
  2. Compares the version of the cached module with the required version.
  3. If the module is missing or the version does not match, it uses `Save-Module` to download the correct version into the `ModuleDownload` directory.

- **Error Handling**: It includes basic error handling for module downloads and provides a placeholder for fallback logic to download from a direct URL if the primary repository fails.
