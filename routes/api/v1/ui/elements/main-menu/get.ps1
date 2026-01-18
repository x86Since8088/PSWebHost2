param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $SessionData,
    [switch]$test,
    [string[]]$Roles,
    [string[]]$Tags,
    [string]$Search
)

#region Helper Functions

function Test-ItemMatchesSearch {
    <#
    .SYNOPSIS
        Tests if a menu item matches the search criteria
    #>
    param (
        $item,
        [string[]]$SearchRegexArr
    )

    # Build searchable strings from tags, Name, and hover_description
    [string[]]$Searchables = @()
    if ($item.Name) { $Searchables += $item.Name }
    if ($item.hover_description) { $Searchables += $item.hover_description }
    if ($item.description) { $Searchables += $item.description }
    if ($item.tags) {
        foreach ($tag in $item.tags) { $Searchables += $tag }
    }

    # Check if all search terms match at least one searchable field
    $Unmatched_Terms = $SearchRegexArr | Where-Object { !($Searchables -match $_) }
    return ($Unmatched_Terms.Count -eq 0)
}

function Get-FileHash {
    <#
    .SYNOPSIS
        Creates a hash from file path and last write time
    #>
    param([string]$FilePath)

    if (Test-Path $FilePath) {
        $fileInfo = Get-Item $FilePath
        return "$($fileInfo.FullName)|$($fileInfo.LastWriteTime.Ticks)"
    }
    return $null
}

function Get-RelativePath {
    <#
    .SYNOPSIS
        Converts absolute path to relative path from project root
    #>
    param([string]$AbsolutePath)

    $relativePath = $AbsolutePath -replace [regex]::Escape($Global:PSWebServer.Project_Root.Path), ''
    return $relativePath.TrimStart('\', '/')
}

function Discover-Apps {
    <#
    .SYNOPSIS
        Discovers apps in the apps directory if not already loaded
    #>
    param()

    if (-not $Global:PSWebServer.ContainsKey('Project_Root')) {
        # If Project_Root not set, calculate from script root
        # Script is in: routes/api/v1/ui/elements/main-menu/get.ps1
        # Need to go up 6 levels to project root
        $projectRoot = Split-Path (Split-Path (Split-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent) -Parent) -Parent
        $Global:PSWebServer.Project_Root = @{ Path = $projectRoot }
    }

    $appsPath = Join-Path $Global:PSWebServer.Project_Root.Path "apps"
    if (-not (Test-Path $appsPath)) {
        Write-Verbose "[MainMenu] Apps directory not found: $appsPath"
        return
    }

    $appDirs = Get-ChildItem -Path $appsPath -Directory
    foreach ($appDir in $appDirs) {
        $appName = $appDir.Name
        if (-not $Global:PSWebServer.Apps.ContainsKey($appName)) {
            $Global:PSWebServer.Apps[$appName] = @{
                Path = $appDir.FullName
                Name = $appName
                Manifest = $null
                Menu = @()
            }
            Write-Verbose "[MainMenu] Discovered app: $appName"
        }
    }
}

function Update-AppMenuData {
    <#
    .SYNOPSIS
        Parses app.yaml and menu.yaml files and updates $Global:PSWebServer.Apps.[AppId].Menu
    #>
    param()

    Write-Verbose "[MainMenu] Updating app menu data..."

    # Import YAML module
    if (-not (Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
        $__err = $null
        # Try local module first
        $localYamlPath = Join-Path $Global:PSWebServer.Project_Root.Path "ModuleDownload/powershell-yaml/0.4.2/powershell-yaml.psm1"
        if (Test-Path $localYamlPath) {
            Import-Module $localYamlPath -DisableNameChecking -ErrorAction SilentlyContinue -ErrorVariable __err
        } else {
            Import-Module powershell-yaml -DisableNameChecking -ErrorAction SilentlyContinue -ErrorVariable __err
        }

        if ($__err) {
            if (Get-Command Write-PSWebHostLog -ErrorAction SilentlyContinue) {
                Write-PSWebHostLog -Severity 'Error' -Category 'Modules' -Message "Failed to import 'powershell-yaml' module: $__err"
            } else {
                Write-Warning "Failed to import 'powershell-yaml' module: $__err"
            }
            return
        }
    }

    # Discover apps if not already loaded
    Discover-Apps

    # Process each app
    if (-not $Global:PSWebServer.Apps -or $Global:PSWebServer.Apps.Count -eq 0) {
        Write-Verbose "[MainMenu] No apps found"
        return
    }

    foreach ($appName in $Global:PSWebServer.Apps.Keys) {
        $app = $Global:PSWebServer.Apps[$appName]

        # Parse app.yaml to get manifest if not already loaded
        $appYamlPath = Join-Path $app.Path "app.yaml"
        if (Test-Path $appYamlPath) {
            try {
                $appYamlContent = Get-Content -Path $appYamlPath -Raw
                $manifest = $appYamlContent | ConvertFrom-Yaml
                $app.Manifest = $manifest
            } catch {
                $msg = "Failed to parse app.yaml for '$appName': $($_.Exception.Message)"
                if (Get-Command Write-PSWebHostLog -ErrorAction SilentlyContinue) {
                    Write-PSWebHostLog -Severity 'Warning' -Category 'Menu' -Message $msg
                } else {
                    Write-Warning $msg
                }
            }
        }

        # Parse menu.yaml
        $menuYamlPath = Join-Path $app.Path "menu.yaml"
        if (Test-Path $menuYamlPath) {
            try {
                $menuYamlContent = Get-Content -Path $menuYamlPath -Raw
                $menuData = $menuYamlContent | ConvertFrom-Yaml

                # Get app's required roles from manifest
                $appRoles = if ($app.Manifest -and $app.Manifest.requiredRoles) {
                    $app.Manifest.requiredRoles
                } else {
                    @('authenticated')
                }

                # Process each menu item
                $processedMenuItems = @()
                foreach ($menuItem in $menuData) {
                    # Inherit app's required roles if item doesn't specify its own
                    if (-not $menuItem.roles) {
                        $menuItem.roles = $appRoles
                    }

                    # Ensure roles is always an array (YAML may parse single role as string)
                    if ($menuItem.roles -is [string]) {
                        $menuItem.roles = @($menuItem.roles)
                    } elseif ($menuItem.roles -isnot [array]) {
                        $menuItem.roles = @($menuItem.roles)
                    }

                    # Set default parent path if not specified
                    if (-not $menuItem.parent) {
                        $menuItem.parent = "Apps\$appName"
                    }

                    # Ensure tags array exists
                    if (-not $menuItem.tags) {
                        $menuItem.tags = @()
                    }

                    # Ensure tags is always an array (YAML may parse single tag as string)
                    if ($menuItem.tags -is [string]) {
                        $menuItem.tags = @($menuItem.tags)
                    } elseif ($menuItem.tags -isnot [array]) {
                        $menuItem.tags = @($menuItem.tags)
                    }

                    # Add app name as tag for searchability
                    if ($menuItem.tags -notcontains $appName) {
                        $menuItem.tags += $appName
                    }

                    # Add ConfigSource for troubleshooting
                    $menuItem.ConfigSource = Get-RelativePath -AbsolutePath $menuYamlPath

                    $processedMenuItems += $menuItem
                }

                # Store in app's Menu property
                $app.Menu = $processedMenuItems
                Write-Verbose "[MainMenu] Loaded $($processedMenuItems.Count) menu items for app: $appName"

            } catch {
                $msg = "Failed to load menu.yaml for app '$appName': $($_.Exception.Message)"
                if (Get-Command Write-PSWebHostLog -ErrorAction SilentlyContinue) {
                    Write-PSWebHostLog -Severity 'Warning' -Category 'Menu' -Message $msg
                } else {
                    Write-Warning $msg
                }
                $app.Menu = @()
            }
        } else {
            # No menu.yaml file
            $app.Menu = @()
        }
    }

    Write-Verbose "[MainMenu] App menu data updated"
}

function Build-HierarchicalMenu {
    <#
    .SYNOPSIS
        Builds hierarchical menu structure from main-menu.yaml and app menus using parent paths
    #>
    param(
        [array]$MainMenuData
    )

    Write-Verbose "[MainMenu] Building hierarchical menu structure..."

    # Start with main menu items
    $menuStructure = $MainMenuData

    # Collect all app menu items
    $allAppMenuItems = @()
    if ($Global:PSWebServer.Apps) {
        foreach ($appName in $Global:PSWebServer.Apps.Keys) {
            $app = $Global:PSWebServer.Apps[$appName]
            if ($app.Menu) {
                $allAppMenuItems += $app.Menu
            }
        }
    }

    Write-Verbose "[MainMenu] Collected $($allAppMenuItems.Count) app menu items"

    # Insert app menu items into hierarchy based on parent paths
    foreach ($appMenuItem in $allAppMenuItems) {
        $parentPath = $appMenuItem.parent
        if (-not $parentPath) { continue }

        # Split parent path (e.g., "System Management\WebHost" -> ["System Management", "WebHost"])
        $pathParts = $parentPath -split '\\'

        # Find or create the parent hierarchy
        $currentLevel = $menuStructure
        $currentLevelParent = $null

        for ($i = 0; $i -lt $pathParts.Count; $i++) {
            $partName = $pathParts[$i]

            # Find existing item at this level
            $existingItem = $null
            foreach ($item in $currentLevel) {
                if ($item.Name -eq $partName) {
                    $existingItem = $item
                    break
                }
            }

            if (-not $existingItem) {
                # Create parent item if it doesn't exist
                $newParentItem = @{
                    Name = $partName
                    hover_description = $partName
                    roles = @('authenticated')
                    collapsed = $true
                    children = @()
                }

                # Add to current level (use .Add() for ArrayList or direct assignment)
                if ($currentLevel -is [System.Collections.ArrayList]) {
                    [void]$currentLevel.Add($newParentItem)
                } else {
                    $currentLevel += $newParentItem
                }
                $existingItem = $newParentItem
            }

            # Ensure children array exists
            if (-not $existingItem.children) {
                $existingItem.children = @()
            }

            # Move to next level
            $currentLevelParent = $existingItem
            $currentLevel = $existingItem.children
        }

        # Add the app menu item to the final level
        if ($currentLevel -is [System.Collections.ArrayList]) {
            [void]$currentLevel.Add($appMenuItem)
        } else {
            # Must modify the parent's children array directly
            if ($currentLevelParent) {
                $currentLevelParent.children += $appMenuItem
            } else {
                # Top level addition
                $menuStructure += $appMenuItem
            }
        }
    }

    Write-Verbose "[MainMenu] Hierarchical menu structure built"
    return $menuStructure
}

function Test-MenuCacheValid {
    <#
    .SYNOPSIS
        Checks if menu cache needs to be refreshed (once per minute)
    #>
    param()

    $now = Get-Date
    $lastCheck = $Global:PSWebServer.MainMenu.LastFileCheck

    # If never checked, cache is invalid
    if ($lastCheck -eq [DateTime]::MinValue) {
        Write-Verbose "[MainMenu] No previous cache check found"
        return $false
    }

    $secondsSinceLastCheck = ($now - $lastCheck).TotalSeconds
    $cacheExpired = $secondsSinceLastCheck -ge 60

    if (-not $cacheExpired) {
        $secondsUntilNextCheck = 60 - $secondsSinceLastCheck
        Write-Verbose "[MainMenu] Using cached menu (next check in $([int]$secondsUntilNextCheck)s)"
        return $true
    }

    Write-Verbose "[MainMenu] Cache expired, checking files for changes..."

    # Check all files for changes
    $filesChanged = $false
    $newFileHashes = @{}
    $yamlPath = Join-Path $PSScriptRoot "main-menu.yaml"

    # Check main-menu.yaml
    $mainMenuHash = Get-FileHash -FilePath $yamlPath
    if ($mainMenuHash) {
        $newFileHashes[$yamlPath] = $mainMenuHash
        if ($Global:PSWebServer.MainMenu.FileHashes[$yamlPath] -ne $mainMenuHash) {
            Write-Verbose "[MainMenu] main-menu.yaml changed"
            $filesChanged = $true
        }
    }

    # Check all app.yaml and menu.yaml files
    if ($Global:PSWebServer.Apps) {
        foreach ($appName in $Global:PSWebServer.Apps.Keys) {
            $appInfo = $Global:PSWebServer.Apps[$appName]

            # Check app.yaml
            $appYamlPath = Join-Path $appInfo.Path "app.yaml"
            $appYamlHash = Get-FileHash -FilePath $appYamlPath
            if ($appYamlHash) {
                $newFileHashes[$appYamlPath] = $appYamlHash
                if ($Global:PSWebServer.MainMenu.FileHashes[$appYamlPath] -ne $appYamlHash) {
                    Write-Verbose "[MainMenu] app.yaml changed: $appName"
                    $filesChanged = $true
                }
            }

            # Check app menu.yaml
            $appMenuPath = Join-Path $appInfo.Path "menu.yaml"
            $appMenuHash = Get-FileHash -FilePath $appMenuPath
            if ($appMenuHash) {
                $newFileHashes[$appMenuPath] = $appMenuHash
                if ($Global:PSWebServer.MainMenu.FileHashes[$appMenuPath] -ne $appMenuHash) {
                    Write-Verbose "[MainMenu] menu.yaml changed: $appName"
                    $filesChanged = $true
                }
            }
        }
    }

    # Update check time and file hashes
    $Global:PSWebServer.MainMenu.LastFileCheck = $now
    $Global:PSWebServer.MainMenu.FileHashes = $newFileHashes

    return (-not $filesChanged -and $null -ne $Global:PSWebServer.MainMenu.CachedMenu)
}

function Build-CompleteMenu {
    <#
    .SYNOPSIS
        Builds complete menu structure (main menu + app menus via parent paths)
    #>
    param()

    Write-Verbose "[MainMenu] Rebuilding menu cache..."

    # Import YAML module
    if (-not (Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
        $__err = $null
        # Try local module first
        $localYamlPath = Join-Path $Global:PSWebServer.Project_Root.Path "ModuleDownload/powershell-yaml/0.4.2/powershell-yaml.psm1"
        if (Test-Path $localYamlPath) {
            Import-Module $localYamlPath -DisableNameChecking -ErrorAction SilentlyContinue -ErrorVariable __err
        } else {
            Import-Module powershell-yaml -DisableNameChecking -ErrorAction SilentlyContinue -ErrorVariable __err
        }

        if ($__err) {
            $msg = "Failed to import 'powershell-yaml' module: $__err"
            if (Get-Command Write-PSWebHostLog -ErrorAction SilentlyContinue) {
                Write-PSWebHostLog -Severity 'Error' -Category 'Modules' -Message $msg
            } else {
                Write-Warning $msg
            }
            return @()
        }
    }

    # Update app menu data (parse app.yaml and menu.yaml files)
    Update-AppMenuData

    # Load main menu from main-menu.yaml
    $yamlPath = Join-Path $PSScriptRoot "main-menu.yaml"
    $mainMenuData = @()

    if (Test-Path $yamlPath) {
        $yamlContent = Get-Content -Path $yamlPath -Raw
        $mainMenuData = $yamlContent | ConvertFrom-Yaml
    } else {
        $msg = "main-menu.yaml not found: $yamlPath"
        if (Get-Command Write-PSWebHostLog -ErrorAction SilentlyContinue) {
            Write-PSWebHostLog -Severity 'Warning' -Category 'Menu' -Message $msg
        } else {
            Write-Warning $msg
        }
    }

    # Build hierarchical structure using parent paths
    $menuData = Build-HierarchicalMenu -MainMenuData $mainMenuData

    # Cache the complete menu
    $Global:PSWebServer.MainMenu.CachedMenu = $menuData

    # Count total items including app menus
    $appMenuCount = 0
    if ($Global:PSWebServer.Apps) {
        foreach ($appName in $Global:PSWebServer.Apps.Keys) {
            $app = $Global:PSWebServer.Apps[$appName]
            if ($app.Menu) {
                $appMenuCount += $app.Menu.Count
            }
        }
    }

    Write-Verbose "[MainMenu] Menu cache rebuilt with $($mainMenuData.Count) main items + $appMenuCount app items"

    return $menuData
}

function Convert-To-Menu-Format {
    <#
    .SYNOPSIS
        Converts menu items to frontend format with role filtering
    #>
    param (
        $items,
        [string[]]$Roles,
        [string[]]$Tags,
        [string[]]$SearchRegexArr,
        [bool]$IsSearching = $false,
        [hashtable]$UserPreferences = @{},
        [string]$ParentPath = "",
        [string]$ConfigSource = "routes/api/v1/ui/elements/main-menu/main-menu.yaml"
    )

    if ($Roles.Count -eq 0) { $Roles += 'unauthenticated' }

    foreach ($item in $items) {
        # Add default roles if none specified
        if ($item.roles.count -eq 0) { $item.roles += 'unauthenticated', 'authenticated' }

        # Build the full path for this menu item (for preferences lookup)
        $currentPath = if ($ParentPath) { "$ParentPath/$($item.Name)" } else { $item.Name }

        # Process children first (if any) - do this BEFORE role check so we can include parents with matching children
        $processedChildren = @()
        $hasMatchingChildren = $false
        if ($item.children) {
            $processedChildren = @(Convert-To-Menu-Format -items $item.children -Roles $Roles -Tags $Tags -SearchRegexArr $SearchRegexArr -IsSearching $IsSearching -UserPreferences $UserPreferences -ParentPath $currentPath -ConfigSource $ConfigSource)
            $hasMatchingChildren = ($processedChildren.Count -gt 0)
        }

        # Check if user has required role
        $userHasRole = ($item.roles | Where-Object { $_ -in $Roles }).Count -gt 0

        # Check if this item matches the search
        $itemMatches = Test-ItemMatchesSearch -item $item -SearchRegexArr $SearchRegexArr

        # Include item if (user has role AND item matches search) OR has matching children
        if (-not (($userHasRole -and $itemMatches) -or $hasMatchingChildren)) { continue }

        # Build output item
        $newItem = @{
            text = $item.Name
            url = $item.url
            hover_description = $item.hover_description
            ConfigSource = if ($item.ConfigSource) { $item.ConfigSource } else { $ConfigSource }
        }

        # Set collapsed state (search mode, user preference, or YAML default)
        if ($null -ne $item.collapsed) {
            if ($IsSearching) {
                $newItem.collapsed = $false
            } elseif ($UserPreferences.ContainsKey($currentPath)) {
                # Invert user preference (frontend uses isOpen, backend uses collapsed)
                $newItem.collapsed = -not $UserPreferences[$currentPath]
            } else {
                $newItem.collapsed = $item.collapsed
            }
        }

        # Include tags if present
        if ($item.tags) {
            $newItem.tags = $item.tags
        }

        # Add children
        if ($processedChildren.Count -gt 0) {
            $newItem.children = $processedChildren
        } elseif ($item.children -and $item.children.Count -gt 0) {
            $newItem.children = @()
        }

        # Exclude empty parent items (no URL and no children)
        if (-not $newItem.url -and (-not $newItem.children -or $newItem.children.Count -eq 0)) {
            continue
        }

        $newItem
    }
}

#endregion

#region Main Execution

# Initialize session and roles
$Session = $SessionData
if ($Session) {
    $Roles = $Session.Roles
}

# Load user preferences
$userPreferences = @{}
if ($Session -and $Session.UserID) {
    try {
        $savedPrefs = Get-CardSettings -EndpointGuid "main-menu" -UserId $Session.UserID
        if ($savedPrefs) {
            $prefsData = $savedPrefs | ConvertFrom-Json
            if ($prefsData.data) {
                $userPreferences = $prefsData.data | ConvertFrom-Json -AsHashtable
            }
        }
    } catch {
        Write-Verbose "Could not load user menu preferences: $($_.Exception.Message)"
    }
}

# Handle test mode
if ($null -eq $Context) { [switch]$test = $true }

# Parse search parameters
if (-not $test.IsPresent) {
    $queryparams = $Request.QueryString
    $search = $queryparams["search"]
    Write-host "main-menu Search: $search"
}

# Build search regex array
if ($search -match '^regex:') {
    [string[]]$SearchRegexArr = $search
} else {
    [string[]]$SearchRegexArr = ($search -split '("[^"]*")|(''[^'']*'')|(\S+)' |
        Where-Object {$_} |
        ForEach-Object{[regex]::Escape($_)})
    if ($SearchRegexArr.Count -eq 0) { $SearchRegexArr += '.*' }
    Write-host "main-menu SearchRegexArr: $($SearchRegexArr -join '; ')"
}

# Initialize menu cache
if (-not $Global:PSWebServer) {
    $Global:PSWebServer = @{}
}
if (-not $Global:PSWebServer.ContainsKey('Apps')) {
    $Global:PSWebServer.Apps = [hashtable]::Synchronized(@{})
}
if (-not $Global:PSWebServer.ContainsKey('MainMenu')) {
    $Global:PSWebServer.MainMenu = [hashtable]::Synchronized(@{
        LastFileCheck = [DateTime]::MinValue
        CachedMenu = $null
        FileHashes = @{}
    })
}

# Check cache and rebuild if needed (once per minute)
$cacheValid = Test-MenuCacheValid
if (-not $cacheValid) {
    $menuData = Build-CompleteMenu
} else {
    $menuData = $Global:PSWebServer.MainMenu.CachedMenu
    if (-not $menuData) {
        $menuData = @()
    }
}

# Convert to frontend format with role filtering
$isSearching = ($search -and $search.Trim() -ne '' -and $SearchRegexArr -and $SearchRegexArr[0] -ne '.*')
[array]$menuItems = @(Convert-To-Menu-Format -items $menuData -Roles $Roles -Tags $Tags -SearchRegexArr $SearchRegexArr -IsSearching $isSearching -UserPreferences $userPreferences)

# Handle empty results
if ($menuItems.count -eq 0) {
    $menuItems += @{text='No results.';url='';hover_description='';children=@();icon='mdi-alert-circle-outline'}
    $menuItems += Convert-To-Menu-Format -items $menuData -Roles $Roles -Tags $Tags -IsSearching $false -UserPreferences $userPreferences
}

# Convert to JSON
[string]$body = $menuItems | ConvertTo-Json -Depth 8
if ('' -eq $body) {
    $body = '[{"text":"No Data"}]'
}

# Return response
if ($test.IsPresent) {
    return $body
}
context_response -Response $Response -String $body -ContentType 'application/json' -StatusCode 200 -CacheDuration 60

#endregion
