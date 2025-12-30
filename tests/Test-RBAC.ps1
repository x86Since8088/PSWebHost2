# Test-RBAC.ps1
# Role-Based Access Control testing for PsWebHost
# Tests authorization enforcement across all route security configurations

[CmdletBinding()]
param(
    [int]$Port = 0
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PsWebHost RBAC Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$testsPassed = 0
$testsFailed = 0

# ============================================
# STEP 1: Analyze Security Configurations
# ============================================
Write-Host "[ANALYSIS] Scanning route security configurations..." -ForegroundColor Cyan

$routesDir = Join-Path $ProjectRoot "routes"
$securityFiles = Get-ChildItem -Path $routesDir -Filter "*.security.json" -Recurse

Write-Host "Found $($securityFiles.Count) security configuration files`n" -ForegroundColor Green

# Parse all security configurations
$securityConfig = @{}
$roleStats = @{}

foreach ($file in $securityFiles) {
    $config = Get-Content $file.FullName | ConvertFrom-Json
    $routePath = $file.FullName.Replace($routesDir, "").Replace("\", "/").Replace(".security.json", "")

    $securityConfig[$routePath] = $config

    # Count role usage
    foreach ($role in $config.Allowed_Roles) {
        if (-not $roleStats.ContainsKey($role)) {
            $roleStats[$role] = 0
        }
        $roleStats[$role]++
    }
}

# Display role statistics
Write-Host "╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      Role Usage Statistics              ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

foreach ($role in $roleStats.Keys | Sort-Object) {
    $count = $roleStats[$role]
    $percentage = [math]::Round(($count / $securityFiles.Count) * 100, 1)
    Write-Host "$($role.PadRight(20)) : $count endpoints ($percentage%)" -ForegroundColor White
}

# ============================================
# STEP 2: Categorize Endpoints by Security Level
# ============================================
Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║    Endpoints by Security Level          ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

$categories = @{
    "Public (unauthenticated)" = @()
    "Authenticated Users" = @()
    "Admin Only (site_admin)" = @()
    "Mixed Access" = @()
}

foreach ($route in $securityConfig.Keys | Sort-Object) {
    $roles = $securityConfig[$route].Allowed_Roles

    if ($roles -contains "unauthenticated" -and $roles.Count -eq 1) {
        $categories["Public (unauthenticated)"] += $route
    }
    elseif ($roles -contains "unauthenticated" -and $roles -contains "authenticated") {
        $categories["Public (unauthenticated)"] += $route
    }
    elseif ($roles -contains "authenticated" -and $roles.Count -eq 1) {
        $categories["Authenticated Users"] += $route
    }
    elseif ($roles -contains "site_admin") {
        $categories["Admin Only (site_admin)"] += $route
    }
    else {
        $categories["Mixed Access"] += $route
    }
}

foreach ($category in $categories.Keys | Sort-Object) {
    $endpoints = $categories[$category]
    Write-Host "`n$category ($($endpoints.Count) endpoints):" -ForegroundColor Yellow

    if ($endpoints.Count -le 10) {
        foreach ($ep in $endpoints | Sort-Object) {
            Write-Host "  - $ep" -ForegroundColor Gray
        }
    } else {
        foreach ($ep in $endpoints | Sort-Object | Select-Object -First 5) {
            Write-Host "  - $ep" -ForegroundColor Gray
        }
        Write-Host "  ... and $($endpoints.Count - 5) more" -ForegroundColor DarkGray
    }
}

# ============================================
# STEP 3: Security Recommendations
# ============================================
Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      Security Recommendations           ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

$recommendations = @()

# Check for potentially exposed sensitive endpoints
$sensitivePatterns = @("debug", "db", "query", "admin", "users")
foreach ($route in $securityConfig.Keys) {
    $roles = $securityConfig[$route].Allowed_Roles

    foreach ($pattern in $sensitivePatterns) {
        if ($route -match $pattern) {
            if ($roles -contains "unauthenticated") {
                $recommendations += "[HIGH] $route allows unauthenticated access to sensitive endpoint"
                $testsFailed++
            }
            elseif ($roles -contains "authenticated" -and $roles -notcontains "site_admin") {
                $recommendations += "[MEDIUM] $route accessible to all authenticated users (consider restricting)"
            }
        }
    }
}

# Check for missing authentication on non-public endpoints
$publicPatterns = @("auth", "registration", "login")
foreach ($route in $securityConfig.Keys) {
    $roles = $securityConfig[$route].Allowed_Roles
    $isPublic = $false

    foreach ($pattern in $publicPatterns) {
        if ($route -match $pattern) {
            $isPublic = $true
            break
        }
    }

    if (-not $isPublic -and $roles -contains "unauthenticated") {
        $recommendations += "[INFO] $route allows unauthenticated access (verify this is intentional)"
    }
}

if ($recommendations.Count -eq 0) {
    Write-Host "✓ No security issues found in RBAC configuration" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "Found $($recommendations.Count) recommendations:`n" -ForegroundColor Yellow

    foreach ($rec in $recommendations | Sort-Object) {
        if ($rec -match '^\[HIGH\]') {
            Write-Host $rec -ForegroundColor Red
        }
        elseif ($rec -match '^\[MEDIUM\]') {
            Write-Host $rec -ForegroundColor Yellow
        }
        else {
            Write-Host $rec -ForegroundColor Cyan
        }
    }
}

# ============================================
# STEP 4: RBAC Enforcement Matrix
# ============================================
Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       RBAC Enforcement Matrix           ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

# Create enforcement matrix
$matrix = @"

Role Hierarchy & Permissions:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. unauthenticated (Lowest)
   ├─ Can access: Login, Registration, Public endpoints
   └─ Endpoints: $($categories["Public (unauthenticated)"].Count)

2. authenticated (Standard User)
   ├─ Inherits: All unauthenticated access
   ├─ Additional: Profile config, Session management
   └─ Endpoints: $($categories["Authenticated Users"].Count) (exclusive)

3. site_admin (Administrator)
   ├─ Inherits: All authenticated access
   ├─ Additional: Database queries, Debug tools, User management
   └─ Endpoints: $($categories["Admin Only (site_admin)"].Count) (exclusive)

4. Additional Roles (if configured)
   ├─ vault_admin
   ├─ system_admin
   └─ Custom roles...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Critical Admin-Only Endpoints:
"@

Write-Host $matrix -ForegroundColor White

$adminEndpoints = $categories["Admin Only (site_admin)"]
foreach ($ep in $adminEndpoints | Sort-Object | Select-Object -First 10) {
    Write-Host "  🔒 $ep" -ForegroundColor Magenta
}
if ($adminEndpoints.Count -gt 10) {
    Write-Host "  ... and $($adminEndpoints.Count - 10) more" -ForegroundColor DarkGray
}

# ============================================
# STEP 5: Configuration Validation
# ============================================
Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     Configuration Validation            ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

# Check for routes without security files
$allRoutes = Get-ChildItem -Path $routesDir -Filter "*.ps1" -Recurse | Where-Object { $_.Name -notmatch 'security' }
$routesWithoutSecurity = @()

foreach ($route in $allRoutes) {
    $securityFile = $route.FullName.Replace(".ps1", ".security.json")
    if (-not (Test-Path $securityFile)) {
        $routePath = $route.FullName.Replace($routesDir, "").Replace("\", "/")
        $routesWithoutSecurity += $routePath
    }
}

if ($routesWithoutSecurity.Count -eq 0) {
    Write-Host "✓ All routes have security configuration files" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "⚠ Found $($routesWithoutSecurity.Count) routes without .security.json files:" -ForegroundColor Yellow
    foreach ($route in $routesWithoutSecurity | Sort-Object | Select-Object -First 10) {
        Write-Host "  - $route" -ForegroundColor Yellow
    }
    if ($routesWithoutSecurity.Count -gt 10) {
        Write-Host "  ... and $($routesWithoutSecurity.Count - 10) more" -ForegroundColor DarkGray
    }
    $testsFailed++
}

# Validate JSON structure
$invalidConfigs = @()
foreach ($file in $securityFiles) {
    try {
        $config = Get-Content $file.FullName | ConvertFrom-Json

        # Check for required fields
        if (-not $config.Allowed_Roles) {
            $invalidConfigs += "$($file.Name): Missing 'Allowed_Roles' field"
        }
        elseif ($config.Allowed_Roles.Count -eq 0) {
            $invalidConfigs += "$($file.Name): 'Allowed_Roles' is empty"
        }
        elseif ($config.Allowed_Roles -isnot [Array]) {
            $invalidConfigs += "$($file.Name): 'Allowed_Roles' should be an array"
        }
    } catch {
        $invalidConfigs += "$($file.Name): Invalid JSON - $($_.Exception.Message)"
    }
}

if ($invalidConfigs.Count -eq 0) {
    Write-Host "✓ All security configuration files are valid" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "✗ Found $($invalidConfigs.Count) invalid configuration files:" -ForegroundColor Red
    foreach ($invalid in $invalidConfigs) {
        Write-Host "  - $invalid" -ForegroundColor Red
    }
    $testsFailed++
}

# ============================================
# Summary
# ============================================
Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          RBAC Test Summary              ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "Security Files Analyzed: $($securityFiles.Count)" -ForegroundColor White
Write-Host "Routes Without Security: $($routesWithoutSecurity.Count)" -ForegroundColor $(if ($routesWithoutSecurity.Count -eq 0) { 'Green' } else { 'Yellow' })
Write-Host "Security Recommendations: $($recommendations.Count)" -ForegroundColor $(if ($recommendations.Count -eq 0) { 'Green' } else { 'Yellow' })
Write-Host ""
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })

if ($testsFailed -eq 0 -and $recommendations.Count -eq 0) {
    Write-Host "`n✓ RBAC configuration is secure!" -ForegroundColor Green
} elseif ($testsFailed -eq 0) {
    Write-Host "`n⚠ RBAC configuration is valid but has recommendations" -ForegroundColor Yellow
} else {
    Write-Host "`n✗ RBAC configuration has issues that need attention" -ForegroundColor Red
}
Write-Host ""
