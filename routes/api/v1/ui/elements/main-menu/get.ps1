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

function Build-CategoryMenuStructure {
    <#
    .SYNOPSIS
        Builds hierarchical category menu structure from apps
    #>
    param()

    if (-not ($Global:PSWebServer.Categories -and $Global:PSWebServer.Categories.Count -gt 0)) {
        return @()
    }

    Write-Verbose "[MainMenu] Building categorized app menu from $($Global:PSWebServer.Categories.Count) categories"

    $categoryMenuItems = @()
    $sortedCategories = $Global:PSWebServer.Categories.GetEnumerator() | Sort-Object { $_.Value.order }

    foreach ($catEntry in $sortedCategories) {
        $category = $catEntry.Value

        $categoryMenuItem = @{
            Name = $category.name
            hover_description = $category.description
            roles = @('authenticated')
            collapsed = $true
            tags = @($category.id)
            children = @()
        }

        # Build subcategories
        $sortedSubCategories = $category.subCategories.GetEnumerator() | Sort-Object { $_.Value.order }

        foreach ($subCatEntry in $sortedSubCategories) {
            $subCategory = $subCatEntry.Value

            $subCategoryMenuItem = @{
                Name = $subCategory.name
                hover_description = "$($category.name) - $($subCategory.name)"
                roles = @('authenticated')
                collapsed = $true
                children = @()
            }

            # Add app menu items to subcategory
            foreach ($appInfo in $subCategory.apps) {
                $appMenuItems = Get-AppMenuItems -AppName $appInfo.name -CategoryId $category.id -SubCategoryName $subCategory.name
                $subCategoryMenuItem.children += $appMenuItems
            }

            # Add subcategory if it has items
            if ($subCategoryMenuItem.children.Count -gt 0) {
                $categoryMenuItem.children += $subCategoryMenuItem
            }
        }

        # Add category if it has subcategories with items
        if ($categoryMenuItem.children.Count -gt 0) {
            $categoryMenuItems += $categoryMenuItem
            Write-Verbose "[MainMenu] Added category '$($category.name)' with $($categoryMenuItem.children.Count) subcategories"
        }
    }

    return $categoryMenuItems
}

function Get-AppMenuItems {
    <#
    .SYNOPSIS
        Loads menu items from an app's menu.yaml file
    #>
    param(
        [string]$AppName,
        [string]$CategoryId,
        [string]$SubCategoryName
    )

    if (-not $Global:PSWebServer.Apps.ContainsKey($AppName)) {
        return @()
    }

    $app = $Global:PSWebServer.Apps[$AppName]
    $appMenuPath = Join-Path $app.Path "menu.yaml"

    if (-not (Test-Path $appMenuPath)) {
        return @()
    }

    try {
        $appMenuContent = Get-Content -Path $appMenuPath -Raw
        $appMenuData = $appMenuContent | ConvertFrom-Yaml

        # Get app manifest for roles
        $manifest = $app.Manifest
        $appRoles = if ($manifest.requiredRoles) { $manifest.requiredRoles } else { @('authenticated') }

        $menuItems = @()
        foreach ($menuItem in $appMenuData) {
            # Inherit app's required roles if item doesn't specify its own
            if (-not $menuItem.roles) {
                $menuItem.roles = $appRoles
            }

            # Add category tags for searchability
            if (-not $menuItem.tags) {
                $menuItem.tags = @()
            }
            $menuItem.tags += $CategoryId
            $menuItem.tags += $SubCategoryName.ToLower()

            # Add ConfigSource for troubleshooting
            $menuItem.ConfigSource = Get-RelativePath -AbsolutePath $appMenuPath

            $menuItems += $menuItem
        }

        Write-Verbose "[MainMenu] Loaded $($menuItems.Count) menu items for app: $AppName"
        return $menuItems

    } catch {
        Write-PSWebHostLog -Severity 'Warning' -Category 'Menu' -Message "Failed to load menu for app '$AppName': $($_.Exception.Message)"
        return @()
    }
}

function Test-MenuCacheValid {
    <#
    .SYNOPSIS
        Checks if menu cache needs to be refreshed
    #>
    param()

    $now = Get-Date
    $cacheExpired = ($now - $Global:PSWebServer.MainMenu.LastFileCheck).TotalSeconds -ge 60

    if (-not $cacheExpired) {
        $secondsUntilNextCheck = 60 - ($now - $Global:PSWebServer.MainMenu.LastFileCheck).TotalSeconds
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
        Builds complete menu structure (main menu + app categories)
    #>
    param()

    Write-Verbose "[MainMenu] Rebuilding menu cache..."

    # Import YAML module
    $__err = $null
    Import-Module powershell-yaml -DisableNameChecking -ErrorAction SilentlyContinue -ErrorVariable __err
    if ($__err) {
        Write-PSWebHostLog -Severity 'Error' -Category 'Modules' -Message "Failed to import 'powershell-yaml' module: $__err"
        return @()
    }

    # Load main menu from main-menu.yaml
    $yamlPath = Join-Path $PSScriptRoot "main-menu.yaml"
    $menuData = @()

    if (Test-Path $yamlPath) {
        $yamlContent = Get-Content -Path $yamlPath -Raw
        $menuData = $yamlContent | ConvertFrom-Yaml
    } else {
        Write-PSWebHostLog -Severity 'Warning' -Category 'Menu' -Message "main-menu.yaml not found: $yamlPath"
    }

    # Build and append category menu structure
    $categoryMenus = Build-CategoryMenuStructure
    $menuData += $categoryMenus

    # Cache the complete menu
    $Global:PSWebServer.MainMenu.CachedMenu = $menuData
    Write-Verbose "[MainMenu] Menu cache rebuilt with $($menuData.Count) items ($($categoryMenus.Count) from apps)"

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

        # Check if user has required role
        if (!($item.roles | Where-Object { $_ -in $Roles })) { continue }

        # Build the full path for this menu item (for preferences lookup)
        $currentPath = if ($ParentPath) { "$ParentPath/$($item.Name)" } else { $item.Name }

        # Process children first (if any)
        $processedChildren = @()
        $hasMatchingChildren = $false
        if ($item.children) {
            $processedChildren = @(Convert-To-Menu-Format -items $item.children -Roles $Roles -Tags $Tags -SearchRegexArr $SearchRegexArr -IsSearching $IsSearching -UserPreferences $UserPreferences -ParentPath $currentPath -ConfigSource $ConfigSource)
            $hasMatchingChildren = ($processedChildren.Count -gt 0)
        }

        # Check if this item matches the search
        $itemMatches = Test-ItemMatchesSearch -item $item -SearchRegexArr $SearchRegexArr

        # Include item if it matches search OR has matching children
        if (-not $itemMatches -and -not $hasMatchingChildren) { continue }

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
if (-not $Global:PSWebServer.MainMenu) {
    $Global:PSWebServer.MainMenu = [hashtable]::Synchronized(@{
        LastFileCheck = [DateTime]::MinValue
        CachedMenu = $null
        FileHashes = @{}
    })
}

# Check cache and rebuild if needed
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
[string]$body = $menuItems | ConvertTo-Json -Depth 5
if ('' -eq $body) {
    $body = '[{"text":"No Data"}]'
}

# Return response
if ($test.IsPresent) {
    return write-host $body -ForegroundColor Yellow
}
context_reponse -Response $Response -String $body -ContentType 'application/json' -StatusCode 200 -CacheDuration 60

#endregion
