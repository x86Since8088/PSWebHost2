param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $SessionData
)

# API endpoint to get merged category structure

try {
    # Build response with sorted categories
    $categories = @()

    foreach ($categoryId in ($Global:PSWebServer.Categories.Keys | Sort-Object)) {
        $cat = $Global:PSWebServer.Categories[$categoryId]

        # Sort subcategories by order
        $subCategories = @()
        foreach ($subCatKey in $cat.subCategories.Keys) {
            $subCat = $cat.subCategories[$subCatKey]
            $subCategories += @{
                name = $subCat.name
                order = $subCat.order
                apps = @($subCat.apps)
            }
        }
        $subCategories = $subCategories | Sort-Object order

        $categories += @{
            id = $cat.id
            name = $cat.name
            description = $cat.description
            icon = $cat.icon
            order = $cat.order
            subCategories = $subCategories
            totalApps = $cat.apps.Count
        }
    }

    # Sort categories by order
    $categories = $categories | Sort-Object order

    $result = @{
        categories = $categories
        totalCategories = $categories.Count
        totalApps = ($Global:PSWebServer.Apps.Keys | Where-Object {
            $Global:PSWebServer.Apps[$_].Manifest.parentCategory
        }).Count
        generatedAt = Get-Date -Format 'o'
    }

    context_reponse -Response $Response -String ($result | ConvertTo-Json -Depth 10) -ContentType 'application/json' -StatusCode 200

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Categories' -Message "Error: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -SessionData $SessionData
    context_reponse -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
