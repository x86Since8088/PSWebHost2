<#
.SYNOPSIS
    Creates a new PSWebHost app with proper structure and scaffolding

.DESCRIPTION
    Generates a complete app directory structure including:
    - app.yaml manifest with category support
    - app_init.ps1 initialization script
    - menu.yaml for menu integration
    - Basic route and element scaffolding

.PARAMETER AppName
    Name of the app (alphanumeric, no spaces)

.PARAMETER DisplayName
    Display name for the app (can include spaces)

.PARAMETER Description
    Brief description of the app's functionality

.PARAMETER Category
    Top-level category for grouping apps in the menu
    Examples: "Operating Systems", "Databases", "Containers", "Monitoring"

.PARAMETER SubCategory
    Optional sub-category within the main category
    Examples: "Windows", "Linux", "MySQL", "Docker"

.PARAMETER RequiredRoles
    Array of roles required to access the app
    Default: @('authenticated')

.PARAMETER Author
    Author name

.PARAMETER RoutePrefix
    URL prefix for app routes
    Default: /apps/[appname-lowercase]

.PARAMETER CreateSampleRoute
    Create a sample GET route

.PARAMETER CreateSampleElement
    Create a sample UI element

.EXAMPLE
    .\New-PSWebHostApp.ps1 -AppName "WindowsAdmin" -DisplayName "Windows Administration" `
        -Description "Windows service and task management" `
        -Category "Operating Systems" -SubCategory "Windows" `
        -RequiredRoles @('admin', 'system_admin')

.EXAMPLE
    .\New-PSWebHostApp.ps1 -AppName "DockerManager" -Category "Containers" -SubCategory "Docker" `
        -CreateSampleRoute -CreateSampleElement
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[a-zA-Z0-9]+$')]
    [string]$AppName,

    [Parameter(Mandatory=$false)]
    [string]$DisplayName,

    [Parameter(Mandatory=$true)]
    [string]$Description,

    [Parameter(Mandatory=$true)]
    [string]$Category,

    [Parameter(Mandatory=$false)]
    [string]$SubCategory,

    [Parameter(Mandatory=$false)]
    [string[]]$RequiredRoles = @('authenticated'),

    [Parameter(Mandatory=$false)]
    [string]$Author = $env:USERNAME,

    [Parameter(Mandatory=$false)]
    [string]$RoutePrefix,

    [switch]$CreateSampleRoute,
    [switch]$CreateSampleElement
)

# Determine project root
$projectRoot = $PSScriptRoot -replace '[/\\]system[/\\].*'
$appsRoot = Join-Path $projectRoot "apps"

# Set defaults
if (-not $DisplayName) {
    $DisplayName = $AppName
}

if (-not $RoutePrefix) {
    $RoutePrefix = "/apps/$($AppName.ToLower())"
}

$appPath = Join-Path $appsRoot $AppName

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PSWebHost App Scaffolder" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check if app already exists
if (Test-Path $appPath) {
    Write-Host "ERROR: App '$AppName' already exists at: $appPath" -ForegroundColor Red
    exit 1
}

Write-Host "Creating app: $DisplayName" -ForegroundColor Yellow
Write-Host "  Location: $appPath" -ForegroundColor Gray
Write-Host "  Category: $Category$(if ($SubCategory) { " > $SubCategory" })" -ForegroundColor Gray
Write-Host "  Route Prefix: $RoutePrefix" -ForegroundColor Gray
Write-Host ""

# Create directory structure
Write-Host "[1/6] Creating directory structure..." -ForegroundColor Yellow
$directories = @(
    $appPath,
    (Join-Path $appPath "data"),
    (Join-Path $appPath "modules"),
    (Join-Path $appPath "public"),
    (Join-Path $appPath "public\elements"),
    (Join-Path $appPath "routes"),
    (Join-Path $appPath "routes\api\v1")
)

foreach ($dir in $directories) {
    New-Item -Path $dir -ItemType Directory -Force | Out-Null
    $relativePath = if ($dir -eq $appPath) { "(root)" } else { $dir.Substring($appPath.Length + 1) }
    Write-Host "  Created: $relativePath" -ForegroundColor Gray
}

# Create app.yaml manifest
Write-Host "`n[2/6] Creating app.yaml manifest..." -ForegroundColor Yellow

# Define parent category objects
$parentCategoryDefinitions = @{
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
    "Monitoring" = @{
        id = "monitoring"
        name = "Monitoring"
        description = "System monitoring and metrics"
        icon = "chart"
        order = 4
    }
    "Admin" = @{
        id = "admin"
        name = "Administration"
        description = "User and system administration"
        icon = "users"
        order = 5
    }
    "Utilities" = @{
        id = "utilities"
        name = "Utilities"
        description = "Tools and helpers"
        icon = "tool"
        order = 6
    }
}

# Get parent category definition or create a custom one
if ($parentCategoryDefinitions.ContainsKey($Category)) {
    $parentCatDef = $parentCategoryDefinitions[$Category]
} else {
    # Create custom category
    $categoryId = $Category.ToLower() -replace '\s+', '-'
    $parentCatDef = @{
        id = $categoryId
        name = $Category
        description = "Custom category: $Category"
        icon = "folder"
        order = 99
    }
}

$manifest = @{
    name = $DisplayName
    version = "1.0.0"
    description = $Description
    routePrefix = $RoutePrefix
    enabled = $true
    requiredRoles = $RequiredRoles
    author = $Author
    parentCategory = [PSCustomObject]@{
        id = $parentCatDef.id
        name = $parentCatDef.name
        description = $parentCatDef.description
        icon = $parentCatDef.icon
        order = $parentCatDef.order
    }
}

if ($SubCategory) {
    # Determine subcategory order (default to 999 if not specified)
    $subCatOrder = 999
    $manifest.subCategory = [PSCustomObject]@{
        name = $SubCategory
        order = $subCatOrder
    }
}

$manifest.features = @{
    created = Get-Date -Format 'yyyy-MM-dd'
}

$manifestPath = Join-Path $appPath "app.yaml"
$manifest | ConvertTo-Yaml | Out-File $manifestPath -Encoding UTF8
Write-Host "  Created: app.yaml" -ForegroundColor Gray

# Create app_init.ps1
Write-Host "`n[3/6] Creating app_init.ps1..." -ForegroundColor Yellow
$initScript = @"
<#
.SYNOPSIS
    Initialization script for $DisplayName app

.DESCRIPTION
    This script is called when the app is loaded during PSWebHost initialization.
    It receives the global PSWebServer hashtable and app root path.

.PARAMETER PSWebServer
    Global server state hashtable

.PARAMETER AppRoot
    Absolute path to this app's root directory
#>

param(`$PSWebServer, `$AppRoot)

Write-Verbose "[$AppName] Initializing $DisplayName app..."

# Create app namespace in global state
`$PSWebServer['$AppName'] = [hashtable]::Synchronized(@{
    AppRoot = `$AppRoot
    DataPath = Join-Path `$AppRoot 'data'
    Initialized = Get-Date
    # Add app-specific state here
})

# Ensure data directory exists
`$dataPath = `$PSWebServer.$AppName.DataPath
if (-not (Test-Path `$dataPath)) {
    New-Item -Path `$dataPath -ItemType Directory -Force | Out-Null
}

# Load any app-specific configuration
# `$configPath = Join-Path `$AppRoot "config.json"
# if (Test-Path `$configPath) {
#     `$config = Get-Content `$configPath | ConvertFrom-Json
#     `$PSWebServer.$AppName.Config = `$config
# }

# Initialize any background jobs or resources here
# Example:
# Start-Job -ScriptBlock { ... }

Write-Host "[Init] Loaded app: $DisplayName (v1.0.0)" -ForegroundColor Green
"@

$initPath = Join-Path $appPath "app_init.ps1"
$initScript | Out-File $initPath -Encoding UTF8
Write-Host "  Created: app_init.ps1" -ForegroundColor Gray

# Create menu.yaml
Write-Host "`n[4/6] Creating menu.yaml..." -ForegroundColor Yellow
$menuContent = @"
# Menu entries for $DisplayName
# These will be integrated into the main PSWebHost menu under:
# $Category$(if ($SubCategory) { " > $SubCategory" })

- Name: $DisplayName Home
  url: $RoutePrefix/api/v1/status
  hover_description: $DisplayName main dashboard
  icon: home
  tags:
    - $($Category.ToLower())
$(if ($SubCategory) { "    - $($SubCategory.ToLower())" })

# Add more menu items here following the same pattern
# - Name: Feature Name
#   url: $RoutePrefix/api/v1/feature
#   hover_description: Description of the feature
#   icon: icon-name
#   tags:
#     - tag1
#     - tag2
"@

$menuPath = Join-Path $appPath "menu.yaml"
$menuContent | Out-File $menuPath -Encoding UTF8
Write-Host "  Created: menu.yaml" -ForegroundColor Gray

# Create sample route if requested
if ($CreateSampleRoute) {
    Write-Host "`n[5/6] Creating sample route..." -ForegroundColor Yellow

    $sampleRouteDir = Join-Path $appPath "routes\api\v1\status"
    New-Item -Path $sampleRouteDir -ItemType Directory -Force | Out-Null

    $sampleRoute = @"
param (
    [System.Net.HttpListenerContext]`$Context,
    [System.Net.HttpListenerRequest]`$Request = `$Context.Request,
    [System.Net.HttpListenerResponse]`$Response = `$Context.Response,
    `$SessionData
)

# Sample status endpoint for $DisplayName app
try {
    `$result = @{
        app = '$DisplayName'
        version = '1.0.0'
        status = 'running'
        timestamp = Get-Date -Format 'o'
        category = '$Category'
$(if ($SubCategory) { "        subCategory = '$SubCategory'" })
    }

    context_response -Response `$Response -String (`$result | ConvertTo-Json) -ContentType 'application/json' -StatusCode 200

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category '$AppName' -Message "Error in status endpoint: `$(`$_.Exception.Message)"

    context_response -Response `$Response -StatusCode 500 -String (@{
        error = `$_.Exception.Message
    } | ConvertTo-Json) -ContentType 'application/json'
}
"@

    $sampleRoutePath = Join-Path $sampleRouteDir "get.ps1"
    $sampleRoute | Out-File $sampleRoutePath -Encoding UTF8

    # Create security file
    $securityContent = @"
{
  "Allowed_Roles": $($RequiredRoles | ConvertTo-Json -Compress)
}
"@
    $securityPath = Join-Path $sampleRouteDir "get.security.json"
    $securityContent | Out-File $securityPath -Encoding UTF8

    Write-Host "  Created: routes/api/v1/status/get.ps1" -ForegroundColor Gray
    Write-Host "  Created: routes/api/v1/status/get.security.json" -ForegroundColor Gray
} else {
    Write-Host "`n[5/6] Skipping sample route (use -CreateSampleRoute to generate)" -ForegroundColor Gray
}

# Create sample UI element if requested
if ($CreateSampleElement) {
    Write-Host "`n[6/6] Creating sample UI element..." -ForegroundColor Yellow

    $elementName = "$($AppName.ToLower())-home"
    $elementDir = Join-Path $appPath "public\elements\$elementName"
    New-Item -Path $elementDir -ItemType Directory -Force | Out-Null

    # Create component.js
    $componentJs = @"
// $DisplayName Home Component
class ${AppName}Home extends React.Component {
    constructor(props) {
        super(props);
        this.state = {
            status: null,
            loading: true,
            error: null
        };
    }

    async componentDidMount() {
        await this.loadStatus();
    }

    async loadStatus() {
        try {
            const response = await window.psweb_fetchWithAuthHandling('$RoutePrefix/api/v1/status');
            if (!response.ok) throw new Error(`HTTP `${response.status}: `${response.statusText}`);
            const data = await response.json();
            this.setState({ status: data, loading: false });
        } catch (error) {
            this.setState({ error: error.message, loading: false });
        }
    }

    render() {
        const { status, loading, error } = this.state;

        if (loading) {
            return React.createElement('div', { className: '$elementName' },
                React.createElement('p', null, 'Loading...')
            );
        }

        if (error) {
            return React.createElement('div', { className: '$elementName' },
                React.createElement('div', { className: 'error' },
                    React.createElement('strong', null, 'Error: '),
                    error
                )
            );
        }

        return React.createElement('div', { className: '$elementName' },
            React.createElement('h2', null, '$DisplayName'),
            React.createElement('div', { className: 'status-card' },
                React.createElement('p', null, `Category: `${status.category}`),
$(if ($SubCategory) { "                React.createElement('p', null, ``SubCategory: ``${status.subCategory}``),`n" })
                React.createElement('p', null, `Status: `${status.status}`),
                React.createElement('p', null, `Version: `${status.version}`)
            )
        );
    }
}

// Register with card loader
window.customElements.define('$elementName', class extends HTMLElement {
    connectedCallback() {
        ReactDOM.render(
            React.createElement(${AppName}Home),
            this
        );
    }
});
"@

    $componentJsPath = Join-Path $elementDir "component.js"
    $componentJs | Out-File $componentJsPath -Encoding UTF8

    # Create style.css
    $styleCss = @"
.$elementName {
    padding: 1rem;
    background: var(--pane-bg-color);
}

.$elementName h2 {
    margin-top: 0;
    color: var(--accent-color);
}

.status-card {
    background: var(--card-bg-color);
    border: 1px solid var(--border-color);
    border-radius: 4px;
    padding: 1rem;
    margin-top: 1rem;
}

.status-card p {
    margin: 0.5rem 0;
}

.error {
    background: rgba(244, 67, 54, 0.2);
    border: 2px solid #f44336;
    border-radius: 4px;
    padding: 1rem;
    color: #f44336;
}
"@

    $styleCssPath = Join-Path $elementDir "style.css"
    $styleCss | Out-File $styleCssPath -Encoding UTF8

    # Create GET endpoint for the element
    $elementRouteDir = Join-Path $appPath "routes\api\v1\ui\elements\$elementName"
    New-Item -Path $elementRouteDir -ItemType Directory -Force | Out-Null

    $elementRoute = @"
param (
    [System.Net.HttpListenerContext]`$Context,
    [System.Net.HttpListenerRequest]`$Request = `$Context.Request,
    [System.Net.HttpListenerResponse]`$Response = `$Context.Response,
    `$SessionData
)

# Serve the UI element HTML
`$html = @``"
<link rel="stylesheet" href="$RoutePrefix/public/elements/$elementName/style.css">
<script src="$RoutePrefix/public/elements/$elementName/component.js"></script>
<$elementName></$elementName>
``"@

context_response -Response `$Response -String `$html -ContentType 'text/html' -StatusCode 200
"@

    $elementRoutePath = Join-Path $elementRouteDir "get.ps1"
    $elementRoute | Out-File $elementRoutePath -Encoding UTF8

    Write-Host "  Created: public/elements/$elementName/component.js" -ForegroundColor Gray
    Write-Host "  Created: public/elements/$elementName/style.css" -ForegroundColor Gray
    Write-Host "  Created: routes/api/v1/ui/elements/$elementName/get.ps1" -ForegroundColor Gray
} else {
    Write-Host "`n[6/6] Skipping sample UI element (use -CreateSampleElement to generate)" -ForegroundColor Gray
}

# Create README
Write-Host "`nCreating README.md..." -ForegroundColor Yellow
$readme = @"
# $DisplayName

$Description

## Category
**$Category**$(if ($SubCategory) { " > **$SubCategory**" })

## Installation
This app is automatically loaded by PSWebHost when placed in the \`apps/\` directory.

## Configuration
- **Route Prefix:** \`$RoutePrefix\`
- **Required Roles:** $($RequiredRoles -join ', ')
- **Author:** $Author

## File Structure
\`\`\`
$AppName/
├── app.yaml                 # App manifest
├── app_init.ps1             # Initialization script
├── menu.yaml                # Menu entries
├── data/                    # App data storage
├── modules/                 # App-specific modules
├── public/elements/         # UI components
└── routes/api/v1/           # API endpoints
\`\`\`

## Development
To add new features:
1. Create routes in \`routes/api/v1/\`
2. Add UI elements in \`public/elements/\`
3. Update \`menu.yaml\` for menu integration
4. Update this README

## API Endpoints
$(if ($CreateSampleRoute) { "- \`GET $RoutePrefix/api/v1/status\` - App status`n" } else { "(Add your endpoints here)`n" })

## Version History
- **1.0.0** ($(Get-Date -Format 'yyyy-MM-dd')) - Initial release
"@

$readmePath = Join-Path $appPath "README.md"
$readme | Out-File $readmePath -Encoding UTF8
Write-Host "  Created: README.md" -ForegroundColor Gray

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "App Created Successfully!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "App Location: $appPath" -ForegroundColor White
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Review and customize app.yaml" -ForegroundColor Gray
Write-Host "  2. Implement your routes in routes/api/v1/" -ForegroundColor Gray
Write-Host "  3. Create UI elements in public/elements/" -ForegroundColor Gray
Write-Host "  4. Update menu.yaml with your menu items" -ForegroundColor Gray
Write-Host "  5. Restart PSWebHost to load the new app" -ForegroundColor Gray
Write-Host ""
Write-Host "The app will be accessible at: $RoutePrefix" -ForegroundColor Cyan
Write-Host ""
