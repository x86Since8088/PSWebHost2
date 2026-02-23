#Requires -Version 7

<#
.SYNOPSIS
    PowerShell Docker Manager Module
.DESCRIPTION
    Provides wrapper functions for Docker CLI operations
    Used by Docker Manager app for container management
#>

# Test if Docker is available and get version info
function Test-DockerAvailability {
    <#
    .SYNOPSIS
        Checks if Docker is installed and accessible
    .OUTPUTS
        Hashtable with available, version, error properties
    #>

    try {
        # Test docker command exists
        $dockerVersion = docker --version 2>&1

        if ($LASTEXITCODE -ne 0) {
            return @{
                available = $false
                version = $null
                error = "Docker command failed: $dockerVersion"
            }
        }

        # Get detailed info
        $dockerInfo = docker info --format json 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue

        return @{
            available = $true
            version = $dockerVersion.ToString().Trim()
            serverVersion = $dockerInfo.ServerVersion
            containers = $dockerInfo.Containers
            containersRunning = $dockerInfo.ContainersRunning
            containersStopped = $dockerInfo.ContainersStopped
            containersPaused = $dockerInfo.ContainersPaused
            images = $dockerInfo.Images
            error = $null
        }

    } catch {
        return @{
            available = $false
            version = $null
            error = $_.Exception.Message
        }
    }
}

# Get all Docker containers
function Get-DockerContainers {
    <#
    .SYNOPSIS
        Lists all Docker containers (running and stopped)
    .OUTPUTS
        Array of hashtables with container information
    #>

    try {
        # Use JSON format for reliable parsing
        $output = docker ps -a --format json --no-trunc 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Docker ps failed: $output"
            return @()
        }

        # Parse JSON lines
        $containers = @()
        $lines = $output -split "`n" | Where-Object { $_.Trim() -ne '' }

        foreach ($line in $lines) {
            try {
                $container = $line | ConvertFrom-Json

                # Normalize container object
                $containers += @{
                    id = $container.ID
                    name = $container.Names
                    image = $container.Image
                    state = $container.State
                    status = $container.Status
                    ports = $container.Ports
                    created = $container.CreatedAt
                    command = $container.Command
                }
            } catch {
                Write-Warning "Failed to parse container JSON: $line"
            }
        }

        return $containers

    } catch {
        Write-Warning "Get-DockerContainers failed: $($_.Exception.Message)"
        return @()
    }
}

# Start a Docker container
function Start-DockerContainer {
    <#
    .SYNOPSIS
        Starts a stopped Docker container
    .PARAMETER ContainerId
        Container ID or name
    .OUTPUTS
        Hashtable with success, message, error properties
    #>

    param(
        [Parameter(Mandatory=$true)]
        [string]$ContainerId
    )

    try {
        $output = docker start $ContainerId 2>&1

        if ($LASTEXITCODE -eq 0) {
            return @{
                success = $true
                message = "Container started successfully"
                containerId = $ContainerId
                error = $null
            }
        } else {
            return @{
                success = $false
                message = "Failed to start container"
                containerId = $ContainerId
                error = $output.ToString()
            }
        }

    } catch {
        return @{
            success = $false
            message = "Exception starting container"
            containerId = $ContainerId
            error = $_.Exception.Message
        }
    }
}

# Stop a Docker container
function Stop-DockerContainer {
    <#
    .SYNOPSIS
        Stops a running Docker container
    .PARAMETER ContainerId
        Container ID or name
    .OUTPUTS
        Hashtable with success, message, error properties
    #>

    param(
        [Parameter(Mandatory=$true)]
        [string]$ContainerId
    )

    try {
        $output = docker stop $ContainerId 2>&1

        if ($LASTEXITCODE -eq 0) {
            return @{
                success = $true
                message = "Container stopped successfully"
                containerId = $ContainerId
                error = $null
            }
        } else {
            return @{
                success = $false
                message = "Failed to stop container"
                containerId = $ContainerId
                error = $output.ToString()
            }
        }

    } catch {
        return @{
            success = $false
            message = "Exception stopping container"
            containerId = $ContainerId
            error = $_.Exception.Message
        }
    }
}

# Restart a Docker container
function Restart-DockerContainer {
    <#
    .SYNOPSIS
        Restarts a Docker container
    .PARAMETER ContainerId
        Container ID or name
    .OUTPUTS
        Hashtable with success, message, error properties
    #>

    param(
        [Parameter(Mandatory=$true)]
        [string]$ContainerId
    )

    try {
        $output = docker restart $ContainerId 2>&1

        if ($LASTEXITCODE -eq 0) {
            return @{
                success = $true
                message = "Container restarted successfully"
                containerId = $ContainerId
                error = $null
            }
        } else {
            return @{
                success = $false
                message = "Failed to restart container"
                containerId = $ContainerId
                error = $output.ToString()
            }
        }

    } catch {
        return @{
            success = $false
            message = "Exception restarting container"
            containerId = $ContainerId
            error = $_.Exception.Message
        }
    }
}

# Remove a Docker container
function Remove-DockerContainer {
    <#
    .SYNOPSIS
        Removes a Docker container
    .PARAMETER ContainerId
        Container ID or name
    .PARAMETER Force
        Force removal of running container
    .OUTPUTS
        Hashtable with success, message, error properties
    #>

    param(
        [Parameter(Mandatory=$true)]
        [string]$ContainerId,

        [Parameter(Mandatory=$false)]
        [switch]$Force
    )

    try {
        $args = @('rm')
        if ($Force) {
            $args += '-f'
        }
        $args += $ContainerId

        $output = docker $args 2>&1

        if ($LASTEXITCODE -eq 0) {
            return @{
                success = $true
                message = "Container removed successfully"
                containerId = $ContainerId
                error = $null
            }
        } else {
            return @{
                success = $false
                message = "Failed to remove container"
                containerId = $ContainerId
                error = $output.ToString()
            }
        }

    } catch {
        return @{
            success = $false
            message = "Exception removing container"
            containerId = $ContainerId
            error = $_.Exception.Message
        }
    }
}

# Get Docker container logs
function Get-DockerContainerLogs {
    <#
    .SYNOPSIS
        Gets logs from a Docker container
    .PARAMETER ContainerId
        Container ID or name
    .PARAMETER Tail
        Number of lines to retrieve from end of logs (default: 100)
    .OUTPUTS
        Hashtable with success, lines, error properties
    #>

    param(
        [Parameter(Mandatory=$true)]
        [string]$ContainerId,

        [Parameter(Mandatory=$false)]
        [int]$Tail = 100
    )

    try {
        $output = docker logs $ContainerId --tail $Tail 2>&1

        if ($LASTEXITCODE -eq 0) {
            $lines = $output -split "`n" | ForEach-Object { $_.TrimEnd() }

            return @{
                success = $true
                containerId = $ContainerId
                lines = @($lines)
                tail = $Tail
                error = $null
            }
        } else {
            return @{
                success = $false
                containerId = $ContainerId
                lines = @()
                tail = $Tail
                error = $output.ToString()
            }
        }

    } catch {
        return @{
            success = $false
            containerId = $ContainerId
            lines = @()
            tail = $Tail
            error = $_.Exception.Message
        }
    }
}

# Validate Docker container ID
function Test-DockerContainerId {
    <#
    .SYNOPSIS
        Validates a Docker container ID format and existence
    .PARAMETER Id
        Container ID to validate
    .OUTPUTS
        Boolean - true if valid and exists, false otherwise
    #>

    param(
        [Parameter(Mandatory=$true)]
        [string]$Id
    )

    # Format validation
    if ($Id -notmatch '^[a-zA-Z0-9_-]+$') {
        throw "Invalid container ID format: must contain only alphanumeric, underscore, and hyphen characters"
    }

    # Length validation
    if ($Id.Length -lt 1 -or $Id.Length -gt 64) {
        throw "Invalid container ID length: must be between 1 and 64 characters"
    }

    # Existence check
    try {
        $output = docker ps -a --format '{{.ID}}' --filter "id=$Id" 2>&1

        if ($LASTEXITCODE -ne 0) {
            return $false
        }

        # Check if we got a result
        $containerIds = $output -split "`n" | Where-Object { $_.Trim() -ne '' }
        return ($containerIds.Count -gt 0)

    } catch {
        return $false
    }
}

# Export module functions
Export-ModuleMember -Function @(
    'Test-DockerAvailability',
    'Get-DockerContainers',
    'Start-DockerContainer',
    'Stop-DockerContainer',
    'Restart-DockerContainer',
    'Remove-DockerContainer',
    'Get-DockerContainerLogs',
    'Test-DockerContainerId'
)
