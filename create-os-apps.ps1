# Script to create all OS and Container apps

$projectRoot = $PSScriptRoot
Set-Location $projectRoot

$apps = @(
    @{
        Name = "WindowsAdmin"
        DisplayName = "Windows Administration"
        Description = "Windows service and task scheduler management"
        Category = "Operating Systems"
        SubCategory = "Windows"
        Roles = @('admin', 'system_admin')
    },
    @{
        Name = "LinuxAdmin"
        DisplayName = "Linux Administration"
        Description = "Linux services, cron jobs, and system management"
        Category = "Operating Systems"
        SubCategory = "Linux"
        Roles = @('admin', 'system_admin')
    },
    @{
        Name = "WSLManager"
        DisplayName = "WSL Manager"
        Description = "Windows Subsystem for Linux management and integration"
        Category = "Containers"
        SubCategory = "WSL"
        Roles = @('admin', 'system_admin')
    },
    @{
        Name = "DockerManager"
        DisplayName = "Docker Manager"
        Description = "Docker container and image management"
        Category = "Containers"
        SubCategory = "Docker"
        Roles = @('admin', 'system_admin')
    },
    @{
        Name = "KubernetesManager"
        DisplayName = "Kubernetes Manager"
        Description = "Kubernetes cluster monitoring and management"
        Category = "Containers"
        SubCategory = "Kubernetes"
        Roles = @('admin', 'system_admin')
    }
)

foreach ($app in $apps) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Creating $($app.DisplayName)..." -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan

    & ".\system\utility\New-PSWebHostApp.ps1" `
        -AppName $app.Name `
        -DisplayName $app.DisplayName `
        -Description $app.Description `
        -Category $app.Category `
        -SubCategory $app.SubCategory `
        -RequiredRoles $app.Roles `
        -CreateSampleRoute `
        -CreateSampleElement

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR creating $($app.Name)" -ForegroundColor Red
        break
    }
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "All apps created successfully!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green
