param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $SessionID = $Request.Cookies["PSWebSessionID"].Value
)

$Session = Get-PSWebSessions -SessionID $SessionID

$Erroroutput = @()
foreach ($ErrorItem in $Error) {
    $Erroroutput+=[pscustomobject]@{
        Messsage = $ErrorItem.Exception.Message
        Data = $ErrorItem.Exception.Data 
        Source = $ErrorItem.InvocationInfo.PositionMessage 
    }
} 
$Erroroutput| format-list | out-string

if ($Error.count -eq 0) {
    $responseString = @{Message = 'Error count 0'} | ConvertTo-Json -Depth 5    
}
else {
    $responseString = $Erroroutput | ConvertTo-Json -Depth 5
}

context_reponse -Response $Response -String $responseString -ContentType "application/json"