param (
    [Parameter(Mandatory=$true)]
    [string]$Email,

    [Parameter(Mandatory=$true)]
    [string]$Password,

    [Parameter(Mandatory=$false)]
    [string]$Phone
)

# Define project root (assuming script is in PsWebHost/system/auth)
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Add modules folder to PSModulePath if not already present
$modulesFolderPath = Join-Path $projectRoot "modules"
if (-not ($Env:PSModulePath -split ';' -contains $modulesFolderPath)) {
    $Env:PSModulePath = "$modulesFolderPath;$($Env:PSModulePath)"
}

# Import the authentication module
Import-Module (Join-Path $modulesFolderPath "PSWebHost_Authentication/PSWebHost_Authentication.psm1") -Force

Write-Host "Creating new user '$Email'..."

try {
    $userID = New-PSWebHostUser -Email $Email -Password $Password -Phone $Phone
    Write-Host "User '$Email' created successfully with UserID: $userID"
} catch {
    Write-Error "Failed to create user: $($_.Exception.Message)"
}
