<#
.SYNOPSIS
    Enumerates all available cards from menu.yaml files

.DESCRIPTION
    Scans all PSWebHost apps for menu.yaml files and extracts card definitions.
    Returns metadata for all available cards including URLs, titles, roles, and tags.

.PARAMETER Tags
    Filter cards by tags (e.g., "files", "debug", "monitoring")

.PARAMETER AppFilter
    Filter by app name (e.g., "WebhostFileExplorer")

.PARAMETER IncludeDisabled
    Include cards from disabled apps

.EXAMPLE
    Get-DebugMenuCards

.EXAMPLE
    Get-DebugMenuCards -Tags @("files", "storage")

.EXAMPLE
    Get-DebugMenuCards -AppFilter @("WebhostFileExplorer", "WebHostMetrics")

.OUTPUTS
    Returns array of card definition objects
#>
[CmdletBinding()]
param(
        [Parameter(Mandatory = $false)]
        [string[]]$Tags,

        [Parameter(Mandatory = $false)]
        [string[]]$AppFilter,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeDisabled
    )

    $MyTag = '[Get-DebugMenuCards]'

    try {
        Write-Verbose "$MyTag Scanning for menu.yaml files..."

        $allCards = @()

        # Check if PSWebServer is available
        if (-not $Global:PSWebServer -or -not $Global:PSWebServer.Apps) {
            Write-Warning "$MyTag PSWebServer.Apps not available"
            return @()
        }

        # Iterate through all registered apps
        foreach ($appName in $Global:PSWebServer.Apps.Keys) {
            $appData = $Global:PSWebServer.Apps[$appName]

            # Skip disabled apps unless requested
            if (-not $IncludeDisabled -and $appData.Enabled -eq $false) {
                Write-Verbose "$MyTag Skipping disabled app: $appName"
                continue
            }

            # Apply app filter if specified
            if ($AppFilter -and $appName -notin $AppFilter) {
                Write-Verbose "$MyTag Skipping filtered app: $appName"
                continue
            }

            # Look for menu.yaml in app root
            $menuPath = Join-Path $appData.RootPath "menu.yaml"

            if (-not (Test-Path $menuPath)) {
                Write-Verbose "$MyTag No menu.yaml found for app: $appName"
                continue
            }

            Write-Verbose "$MyTag Processing menu: $menuPath"

            try {
                # Read and parse YAML (simple parser for menu structure)
                $menuContent = Get-Content $menuPath -Raw

                # Extract menu items (simple regex-based parsing)
                # Format: - Name: <name>\n  url: <url>\n  hover_description: <desc>
                $menuItems = @()

                # Split into individual menu items
                $items = $menuContent -split '(?m)^- Name:'

                foreach ($item in $items) {
                    if ([string]::IsNullOrWhiteSpace($item)) { continue }

                    # Extract fields
                    $name = if ($item -match '^\s*(.+?)[\r\n]') { $matches[1].Trim() } else { $null }
                    $url = if ($item -match '(?m)^\s*url:\s*(.+?)[\r\n]') { $matches[1].Trim() } else { $null }
                    $description = if ($item -match '(?m)^\s*hover_description:\s*(.+?)[\r\n]') { $matches[1].Trim() } else { $null }

                    # Extract roles (list format)
                    $roles = @()
                    if ($item -match '(?ms)roles:(.*?)(?:\r?\n\S|\z)') {
                        $rolesBlock = $matches[1]
                        $roles = ([regex]::Matches($rolesBlock, '(?m)^\s*-\s*(.+?)[\r\n]') | ForEach-Object { $_.Groups[1].Value.Trim() })
                    }

                    # Extract tags (list format)
                    $itemTags = @()
                    if ($item -match '(?ms)tags:(.*?)(?:\r?\n\S|\z)') {
                        $tagsBlock = $matches[1]
                        $itemTags = ([regex]::Matches($tagsBlock, '(?m)^\s*-\s*(.+?)[\r\n]') | ForEach-Object { $_.Groups[1].Value.Trim() })
                    }

                    if ($name -and $url) {
                        # Determine element ID from URL
                        $elementId = if ($url -match '/ui/elements/([^/\?]+)') { $matches[1] } else { $null }

                        $cardDef = [PSCustomObject]@{
                            Name = $name
                            Url = $url
                            ElementID = $elementId
                            Description = $description
                            Roles = $roles
                            Tags = $itemTags
                            AppName = $appName
                            AppEnabled = $appData.Enabled
                            MenuPath = $menuPath
                        }

                        # Apply tag filter if specified
                        if ($Tags) {
                            $hasMatchingTag = $false
                            foreach ($tag in $Tags) {
                                if ($itemTags -contains $tag) {
                                    $hasMatchingTag = $true
                                    break
                                }
                            }
                            if (-not $hasMatchingTag) {
                                Write-Verbose "$MyTag Skipping card '$name' (no matching tags)"
                                continue
                            }
                        }

                        $menuItems += $cardDef
                        Write-Verbose "$MyTag Found card: $name (ElementID: $elementId)"
                    }
                }

                $allCards += $menuItems

            } catch {
                Write-Warning "$MyTag Failed to parse menu.yaml for ${appName}: $($_.Exception.Message)"
            }
    }

    Write-Verbose "$MyTag Found $($allCards.Count) total cards"
    return $allCards

} catch {
    Write-Error "$MyTag Error enumerating cards: $_"
    return @()
}
