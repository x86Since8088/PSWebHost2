param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    [switch]$test,
    [string[]]$Roles,
    [string[]]$Tags,
    [string]$Search
)
if ($Session) {
    $Roles = $Session.Roles
}

if ($null -eq $Context) {[switch]$test=$true}
$yamlPath = Join-Path $PSScriptRoot "main-menu.yaml"
if ($test.IsPresent) {}
else {
    $SessionID = $Context.Request.Cookies['sessionid'].Value 
    $Session = Get-PSWebSessions -SessionID $SessionID
    $queryparams = $Request.QueryString
    $search = $queryparams["search"]
    Write-host "main-menu Search: $search"
}
if ($search -match '^regex:') { # If the search string starts with 'regex:', treat the rest as a regex
    [string[]]$SearchRegexArr = $search
} else {
    [string[]]$SearchRegexArr = ($search -split '("[^"]*")|(''[^'']*'')|(\S+)' |
        Where-Object {$_} | 
        ForEach-Object{[regex]::Escape($_)})
    if ($SearchRegexArr.Count -eq 0) {$SearchRegexArr+='.*'}
    Write-host "main-menu SearchRegexArr: $($SearchRegexArr -join '; ')"
}

# The frontend expects a 'text' property, but the yaml has 'Name'. Let's transform it.
function Convert-To-Menu-Format {
    param (
        $items,
        [string[]]$Roles,
        [string[]]$Tags,
        [string[]]$SearchRegexArr
    )
    if ($Roles.Count -eq 0) {$Roles+='unauthenticated'}
    foreach ($item in $items) {
        [string[]]$Searchables = $item.description,
            $item.Name,
            $item.hover_description,
            $item.tags
        $Unmatched_Terms = $SearchRegexArr | Where-Object{!($Searchables -match $_)}

        # Add default roles if none specified
        if ($item.roles.count -eq 0) { $item.roles += 'unauthenticated','authenticated'}

        # Check if user has required role
        if (!($item.roles|Where-Object{$_ -in $Roles})) { continue }

        # Check search terms
        if ($Unmatched_Terms.Count -gt 0) { continue }

        # Item passes all checks, include it
        $newItem = @{
                text = $item.Name
                url = $item.url
                hover_description = $item.hover_description
            }
        if ($item.children) {
            $newItem.children = @(Convert-To-Menu-Format -items $item.children -Roles $Roles -Tags $Tags -SearchRegexArr $SearchRegexArr)
        }
        $newItem
    }
}

if (-not (Test-Path $yamlPath)) {
    return context_reponse -Response $Response -String "File not found: $yamlPath" `
        -ContentType 'text/plain' -StatusCode 404 -StatusDescription "Not Found"
}

# The powershell-yaml module is required by the project
$__err = $null
Import-Module powershell-yaml -DisableNameChecking -ErrorAction SilentlyContinue -ErrorVariable __err
if ($__err) {
    Write-PSWebHostLog -Severity 'Error' -Category 'Modules' -Message "Failed to import 'powershell-yaml' module: $__err"
    return context_reponse -Response $Response -StatusCode 500 -String "Server misconfiguration: missing powershell-yaml module"
}

$yamlContent = Get-Content -Path $yamlPath -Raw
$menuData = $yamlContent | ConvertFrom-Yaml

[array]$menuItems = @(Convert-To-Menu-Format -items $menuData -Roles $Roles -Tags $Tags -SearchRegexArr $SearchRegexArr)
if ($menuItems.count -eq 0) {
    $menuItems += @{text='No results.';url='';hover_description='';children=@();icon='mdi-alert-circle-outline'}
    $menuItems += Convert-To-Menu-Format -items $menuData -Roles $Roles -Tags $Tags
}

[string]$body = $menuItems | ConvertTo-Json -Depth 5
if ('' -eq $body) {
    $body = '
    [
        {"text":"No Data"
        }
    ]'
}

if ($test.IsPresent) {
    return write-host $body -ForegroundColor Yellow
}
context_reponse -Response $Response -String $body -ContentType 'application/json' -StatusCode 200 -CacheDuration 60
