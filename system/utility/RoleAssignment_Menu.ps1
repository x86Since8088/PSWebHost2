# RoleAssignment_Menu.ps1
# Interactive menu for role assignment management

<#
.SYNOPSIS
    Interactive menu interface for managing role assignments.

.DESCRIPTION
    Provides a user-friendly menu system for common role management tasks.
    No command-line parameters needed - just run and follow the prompts.

.EXAMPLE
    pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Menu.ps1'"

    Opens the interactive menu.
#>

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[RoleAssignment_Menu.ps1]'

function Show-Menu {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   PSWebHost Role Assignment Manager" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Assign Role to User" -ForegroundColor White
    Write-Host "2. View User's Roles" -ForegroundColor White
    Write-Host "3. Remove Role from User" -ForegroundColor White
    Write-Host "4. List All Role Assignments" -ForegroundColor White
    Write-Host "5. Show Role Statistics" -ForegroundColor White
    Write-Host "6. List Available Users" -ForegroundColor White
    Write-Host "7. List All Roles" -ForegroundColor White
    Write-Host "8. Add Multiple Roles to User" -ForegroundColor White
    Write-Host "9. Export Roles to CSV" -ForegroundColor White
    Write-Host "Q. Quit" -ForegroundColor Yellow
    Write-Host ""
}

function Get-UserByEmail {
    param([string]$Email)
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $safeEmail = Sanitize-SqlQueryString -String $Email
    return Get-PSWebSQLiteData -File $dbFile -Query "SELECT UserID, Email FROM Users WHERE Email COLLATE NOCASE = '$safeEmail';"
}

function Show-AllUsers {
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $users = Get-PSWebSQLiteData -File $dbFile -Query "SELECT Email FROM Users ORDER BY Email;"

    Write-Host "`nAvailable Users:" -ForegroundColor Cyan
    Write-Host "================" -ForegroundColor Cyan
    $users | ForEach-Object { Write-Host "  • $($_.Email)" }
    Write-Host ""
}

# Main menu loop
do {
    Show-Menu
    $choice = Read-Host "Select an option"

    switch ($choice.ToUpper()) {
        '1' {
            Write-Host "`n--- Assign Role to User ---" -ForegroundColor Green
            $email = Read-Host "Enter user email"
            $roleName = Read-Host "Enter role name (e.g., Debug, Admin, site_admin)"

            try {
                & (Join-Path $PSScriptRoot "RoleAssignment_New.ps1") -Email $email -RoleName $roleName
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            } catch {
                Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "Press any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
        }

        '2' {
            Write-Host "`n--- View User's Roles ---" -ForegroundColor Green
            $email = Read-Host "Enter user email"

            try {
                & (Join-Path $PSScriptRoot "RoleAssignment_Get.ps1") -Email $email
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            } catch {
                Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "Press any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
        }

        '3' {
            Write-Host "`n--- Remove Role from User ---" -ForegroundColor Yellow
            $email = Read-Host "Enter user email"
            $roleName = Read-Host "Enter role name to remove"
            $confirm = Read-Host "Are you sure? (Y/N)"

            if ($confirm.ToUpper() -eq 'Y') {
                try {
                    & (Join-Path $PSScriptRoot "RoleAssignment_Remove.ps1") -Email $email -RoleName $roleName -Force
                    Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                } catch {
                    Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "Press any key to continue..." -ForegroundColor Gray
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                }
            } else {
                Write-Host "Cancelled." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }
        }

        '4' {
            Write-Host "`n--- All Role Assignments ---" -ForegroundColor Green
            $groupBy = Read-Host "Group by? (None/Role/User) [None]"
            if ([string]::IsNullOrWhiteSpace($groupBy)) { $groupBy = 'None' }

            try {
                & (Join-Path $PSScriptRoot "RoleAssignment_List.ps1") -GroupBy $groupBy
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            } catch {
                Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "Press any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
        }

        '5' {
            Write-Host "`n--- Role Statistics ---" -ForegroundColor Green

            try {
                & (Join-Path $PSScriptRoot "RoleAssignment_List.ps1") -ShowStatistics
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            } catch {
                Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "Press any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
        }

        '6' {
            Show-AllUsers
            Write-Host "Press any key to continue..." -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }

        '7' {
            Write-Host "`n--- All Roles ---" -ForegroundColor Green

            try {
                & (Join-Path $PSScriptRoot "RoleAssignment_Get.ps1") -ListRoles
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            } catch {
                Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "Press any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
        }

        '8' {
            Write-Host "`n--- Add Multiple Roles to User ---" -ForegroundColor Green
            $email = Read-Host "Enter user email"
            $roles = Read-Host "Enter role names (comma-separated)"
            $roleArray = $roles -split ',' | ForEach-Object { $_.Trim() }

            try {
                & (Join-Path $PSScriptRoot "RoleAssignment_Update.ps1") -Email $email -AddRoles $roleArray
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            } catch {
                Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "Press any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
        }

        '9' {
            Write-Host "`n--- Export Roles to CSV ---" -ForegroundColor Green
            $path = Read-Host "Enter file path (e.g., C:\temp\roles.csv)"

            try {
                & (Join-Path $PSScriptRoot "RoleAssignment_List.ps1") -Export $path
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            } catch {
                Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "Press any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
        }

        'Q' {
            Write-Host "`nGoodbye!" -ForegroundColor Cyan
            break
        }

        default {
            Write-Host "`nInvalid option. Press any key to continue..." -ForegroundColor Red
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    }
} while ($choice.ToUpper() -ne 'Q')
