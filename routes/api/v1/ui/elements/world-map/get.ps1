
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

# Note: In a real scenario, this data would come from a database or another service.
$mapPins = @(
    @{ id = 'ny'; title = 'New York'; status = 'Operational'; lat = 40.7128; lng = -74.0060 },
    @{ id = 'london'; title = 'London'; status = 'Operational'; lat = 51.5074; lng = -0.1278 },
    @{ id = 'tokyo'; title = 'Tokyo'; status = 'Degraded'; lat = 35.6895; lng = 139.6917 },
    @{ id = 'sydney'; title = 'Sydney'; status = 'Outage'; lat = -33.8688; lng = 151.2093 },
    @{ id = 'rio'; title = 'Rio de Janeiro'; status = 'Operational'; lat = -22.9068; lng = -43.1729 }
)

$jsonData = $mapPins | ConvertTo-Json
context_response -Response $Response -String $jsonData -ContentType "application/json"
