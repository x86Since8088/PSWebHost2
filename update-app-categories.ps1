# Update all app.json files to use parent category objects

$categoryDefinitions = @{
    "Operating Systems" = @{
        id = "operating-systems"
        name = "Operating Systems"
        description = "Operating system administration and management"
        icon = "desktop"
        order = 1
    }
    "Containers" = @{
        id = "containers"
        name = "Containers"
        description = "Container orchestration and management"
        icon = "box"
        order = 2
    }
    "Databases" = @{
        id = "databases"
        name = "Databases"
        description = "Database administration and monitoring"
        icon = "database"
        order = 3
    }
}

$appCategories = @{
    "WindowsAdmin" = @{
        parentCategory = "Operating Systems"
        subCategory = "Windows"
        subCategoryOrder = 1
    }
    "LinuxAdmin" = @{
        parentCategory = "Operating Systems"
        subCategory = "Linux"
        subCategoryOrder = 2
    }
    "WSLManager" = @{
        parentCategory = "Containers"
        subCategory = "WSL"
        subCategoryOrder = 1
    }
    "DockerManager" = @{
        parentCategory = "Containers"
        subCategory = "Docker"
        subCategoryOrder = 2
    }
    "KubernetesManager" = @{
        parentCategory = "Containers"
        subCategory = "Kubernetes"
        subCategoryOrder = 3
    }
    "MySQLManager" = @{
        parentCategory = "Databases"
        subCategory = "MySQL"
        subCategoryOrder = 1
    }
    "RedisManager" = @{
        parentCategory = "Databases"
        subCategory = "Redis"
        subCategoryOrder = 2
    }
    "SQLiteManager" = @{
        parentCategory = "Databases"
        subCategory = "SQLite"
        subCategoryOrder = 3
    }
    "SQLServerManager" = @{
        parentCategory = "Databases"
        subCategory = "SQL Server"
        subCategoryOrder = 4
    }
    "VaultManager" = @{
        parentCategory = "Databases"
        subCategory = "Vault"
        subCategoryOrder = 5
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Updating App Category Structures" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

foreach ($appName in $appCategories.Keys) {
    $appJsonPath = "apps\$appName\app.json"

    if (-not (Test-Path $appJsonPath)) {
        Write-Host "⚠ Skipping $appName (app.json not found)" -ForegroundColor Yellow
        continue
    }

    Write-Host "Updating $appName..." -ForegroundColor White

    # Load existing app.json
    $appJson = Get-Content $appJsonPath -Raw | ConvertFrom-Json

    # Get category info
    $categoryInfo = $appCategories[$appName]
    $parentCategoryName = $categoryInfo.parentCategory
    $parentCategoryDef = $categoryDefinitions[$parentCategoryName]

    # Create parent category object
    $parentCategory = [PSCustomObject]@{
        id = $parentCategoryDef.id
        name = $parentCategoryDef.name
        description = $parentCategoryDef.description
        icon = $parentCategoryDef.icon
        order = $parentCategoryDef.order
    }

    # Update app.json with new structure
    $appJson | Add-Member -MemberType NoteProperty -Name "parentCategory" -Value $parentCategory -Force

    # Update subCategory with order
    $subCategoryObj = [PSCustomObject]@{
        name = $categoryInfo.subCategory
        order = $categoryInfo.subCategoryOrder
    }
    $appJson.subCategory = $subCategoryObj

    # Remove old "category" field if it exists
    if ($appJson.PSObject.Properties.Name -contains "category") {
        $appJson.PSObject.Properties.Remove("category")
    }

    # Save updated app.json
    $appJson | ConvertTo-Json -Depth 10 | Set-Content $appJsonPath -Encoding UTF8

    Write-Host "  ✓ Updated with parent category: $($parentCategory.name) > $($categoryInfo.subCategory)" -ForegroundColor Green
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Category Update Complete!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  - Operating Systems: 2 apps (Windows, Linux)" -ForegroundColor White
Write-Host "  - Containers: 3 apps (WSL, Docker, Kubernetes)" -ForegroundColor White
Write-Host "  - Databases: 5 apps (MySQL, Redis, SQLite, SQL Server, Vault)" -ForegroundColor White
Write-Host ""
