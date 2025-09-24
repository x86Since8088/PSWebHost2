
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

# Generating a 10x10 grid of random numbers for the heatmap
$heatmapData = foreach ($row in (1..10)) {
    $rowData = foreach ($col in (1..10)) { Get-Random -Minimum 0 -Maximum 100 }
    ,($rowData) # The comma forces the output to be treated as an array row
}

$jsonData = $heatmapData | ConvertTo-Json
context_reponse -Response $Response -String $jsonData -ContentType "application/json"
