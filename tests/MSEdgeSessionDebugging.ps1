# ==========================
# Helper functions (parent)
# ==========================
function Send-WebSocketMessage {
    param([System.Net.WebSockets.ClientWebSocket]$Client, [string]$Message)
    Write-Host "`n[Send] $(Get-Date): $Message" -ForegroundColor Magenta
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
    $segment = [System.ArraySegment[byte]]::new($bytes)
    $Client.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).Wait()
}
function Receive-WebSocketText {
    param([System.Net.WebSockets.ClientWebSocket]$Client, [int]$BufferSize = 16384)
    if ($Client.State -notmatch '\w') { return Write-Host 'No state on client.  Returning.' }
    $Client
    Write-Host "`n[Receive] Waiting for message at $(Get-Date)" -ForegroundColor Yellow -NoNewline
    $buffer = New-Object byte[] $BufferSize
    $segment = [System.ArraySegment[byte]]::new($buffer)
    $ms = New-Object System.IO.MemoryStream
    ($D = [System.Diagnostics.Stopwatch]::new()).start()
    do {
        if ($Client.State -eq [System.Net.WebSockets.WebSocketState]::Aborted) {
            Write-Host " Client state is aborted." -ForegroundColor Yellow
            break
        }
        if ([math]::Round($D.ElapsedMilliseconds / 1000, 0) % 3) {
            write-host "$($Client.State), " -NoNewline
        }
        $result = $Client.ReceiveAsync($segment, [Threading.CancellationToken]::None).Result
        if ($result.Count -gt 0) { $ms.Write($buffer, 0, $result.Count) }
        if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { return $null }
        Write-Host "." -NoNewline
    } while (-not $result.EndOfMessage)
    $data = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
    Write-Host "`n[Receive Complete] $(Get-Date): $data" -ForegroundColor Cyan
    return $data
}
function Convert-HeadersToHarArray {
    param([hashtable]$Headers)
    Write-Host "Convert-HeadersToHarArray started $(Get-Date)"
    $harHeaders = @()
    if ($Headers) {
        foreach ($k in $Headers.Keys) {
            $harHeaders += @{ name = [string]$k; value = [string]$Headers[$k] }
        }
    }
    return $harHeaders
}
# ==========================
# Setup & launch Edge
# ==========================
$dropFolder = Join-Path $PSScriptRoot "drop"
if (-not (Test-Path $dropFolder)) { New-Item -ItemType Directory -Path $dropFolder | Out-Null }
$url = Read-Host "Enter the URL"
Add-Type -AssemblyName System.Web
$encodedUrl = [System.Web.HttpUtility]::UrlEncode($url)
$userDomain = $env:USERDOMAIN
$userName = $env:USERNAME
$computerName = $env:COMPUTERNAME
$edgePath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edgePath)) { $edgePath = "C:\Program Files\Microsoft\Edge\Application\msedge.exe" }
$BrowserDebuggingPort = 9222
$tempProfile = Join-Path $env:TEMP "EdgeProfile_$([guid]::NewGuid())"
$proc = Start-Process -FilePath $edgePath `
-ArgumentList @("--new-window", "--remote-debugging-port=$BrowserDebuggingPort", "--user-data-dir=$tempProfile", $url) `
-PassThru
Write-Host "Edge launched (PID: $($proc.Id))."
# ==========================
# Find a PAGE WebSocket URL
# ==========================
Start-Sleep 2
$pageTarget = $null
for ($i = 0; $i -lt 10 -and -not $pageTarget; $i++) {
    try {
        $targets = Invoke-RestMethod -Uri "http://localhost:$BrowserDebuggingPort/json" -TimeoutSec 3
    }
    catch { $targets = $null }
    if ($targets) {
        $pageTarget = $targets |
        Where-Object { $_.type -eq 'page' -and $_.url -like "$url*" } |
        Select-Object -First 1
        if (-not $pageTarget) {
            $pageTarget = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
        }
    }
    if (-not $pageTarget) { Start-Sleep -Milliseconds 500 }
}
if (-not $pageTarget) { throw "No 'page' targets found on DevTools port $BrowserDebuggingPort." }
$wsUrl = $pageTarget.webSocketDebuggerUrl
Write-Host "DevTools (page) WebSocket: $wsUrl"
# ==========================
# Start HAR capture job
# ==========================
Get-Job -Name EdgeDebugJob -ErrorAction Ignore | Stop-Job -PassThru | Remove-Job
$EdgeDebugJob_SB = {
    param($wsUrl, $dropFolder, $encodedUrl, $userDomain, $userName, $computerName, $BrowserDebuggingPort, $procId)
    begin {
        # Import helper functions from parent
        try { ${function:Send-WebSocketMessage} = ${using:function:Send-WebSocketMessage} } catch {}
        try { ${function:Receive-WebSocketText} = ${using:function:Receive-WebSocketText} } catch {}
        try { ${function:Convert-HeadersToHarArray} = ${using:function:Convert-HeadersToHarArray} } catch {}
        # CDP helpers
        $script:__cdpId = 1000
        # Needed for querystring parsing
        Add-Type -AssemblyName System.Web
        function Parse-HeadersText {
            param([string]$HeadersText)
            Write-Host -ForegroundColor DarkCyan "[Helper] Parse-HeadersText start $(Get-Date)"
            $result = @{
                protocol   = $null
                statusCode = $null
                statusText = $null
                headers    = @{}
            }
            if ([string]::IsNullOrWhiteSpace($HeadersText)) { return $result }
            $lines = $HeadersText -split "`r?`n"
            $statusLine = ($lines | Where-Object { $_.Trim() } | Select-Object -First 1)
            if ($statusLine -match '^(HTTP/\d\.\d|\w+/\d(?:\.\d)?)\s+(\d{3})\s+(.*)$') {
                $result.protocol = $matches[1]
                $result.statusCode = [int]$matches[2]
                $result.statusText = $matches[3]
            }
            foreach ($line in ($lines | Select-Object -Skip 1)) {
                if (-not $line.Trim()) { continue }
                $idx = $line.IndexOf(':')
                if ($idx -gt 0) {
                    $name = $line.Substring(0, $idx).Trim()
                    $value = $line.Substring($idx + 1).Trim()
                    if ($result.headers.ContainsKey($name)) {
                        $result.headers[$name] = ($result.headers[$name] + ", " + $value)
                    }
                    else {
                        $result.headers[$name] = $value
                    }
                }
            }
            return $result
        }
        function ConvertTo-Hashtable {
            param($obj)
            $ht = @{}
            if ($obj) {
                foreach ($prop in $obj.psobject.Properties) {
                    if ($prop.Value -is [System.Management.Automation.PSCustomObject]) {
                        $ht[$prop.Name] = ConvertTo-Hashtable $prop.Value
                    }
                    else {
                        $ht[$prop.Name] = $prop.Value
                    }
                }
            }
            return $ht
        }        
        function Merge-HeaderMaps {
            param(
                $Primary,   # preferred values (override)
                $Secondary  # fallback values
            )
            if ($Primary -isnot [hashtable]) {
                $Primary = ConvertTo-Hashtable $Primary
            }
            if ($Secondary -isnot [hashtable]) {
                $Secondary = ConvertTo-Hashtable $Secondary
            }
            Write-Host -ForegroundColor DarkCyan "[Helper] Merge-HeaderMaps start $(Get-Date)"
            $merged = @{}
            if ($Secondary) { foreach ($k in $Secondary.Keys) { $merged[$k] = $Secondary[$k] } }
            if ($Primary) { foreach ($k in $Primary.Keys) { $merged[$k] = $Primary[$k] } }
            return $merged
        }
        function Parse-QueryString {
            param([string]$Url)
            Write-Host -ForegroundColor DarkCyan "[Helper] Parse-QueryString for $Url"
            try {
                $u = [System.Uri]$Url
            }
            catch {
                return @()
            }
            $qs = [System.Web.HttpUtility]::ParseQueryString($u.Query)
            $arr = @()
            foreach ($k in $qs.Keys) {
                if ($null -eq $k) { continue }
                $arr += @{ name = [string]$k; value = [string]$qs[$k] }
            }
            return $arr
        }
        function Parse-SetCookieHeaders {
            param(
                [hashtable]$HeadersMap,       # merged headers (case-sensitive keys)
                [string]$HeadersText          # raw headers text, for multiple Set-Cookie lines
            )
            Write-Host -ForegroundColor DarkCyan "[Helper] Parse-SetCookieHeaders start $(Get-Date)"
            $cookies = @()
            # Prefer headersText lines because Set-Cookie may repeat
            if ($HeadersText) {
                $lines = $HeadersText -split "`r?`n"
                foreach ($line in $lines) {
                    if ($line -match '^\s*Set-Cookie\s*:\s*(.+)$') {
                        $cookieLine = $matches[1].Trim()
                        $cookies += (Convert-SetCookieLineToHar -CookieLine $cookieLine)
                    }
                }
            }
            elseif ($HeadersMap -and $HeadersMap.ContainsKey('Set-Cookie')) {
                # Fallback: some servers coalesce multiple set-cookie; split crudely on ", " only if safe
                $coalesced = $HeadersMap['Set-Cookie']
                foreach ($part in ($coalesced -split '(?<!Expires=.+),\s*(?=[^;,]+=)')) {
                    $cookies += (Convert-SetCookieLineToHar -CookieLine $part.Trim())
                }
            }
            return $cookies
        }
        function Convert-SetCookieLineToHar {
            param([string]$CookieLine)
            # Very simple parser: name=value; attr1=val; attr2; Expires=...
            $segments = $CookieLine -split ';'
            if (-not $segments -or $segments.Count -eq 0) { return $null }
            $nameValue = $segments[0].Trim()
            $eq = $nameValue.IndexOf('=')
            if ($eq -lt 0) { return $null }
            $name = $nameValue.Substring(0, $eq)
            $value = $nameValue.Substring($eq + 1)
            $har = @{
                name     = $name
                value    = $value
                path     = $null
                domain   = $null
                expires  = $null
                httpOnly = $false
                secure   = $false
                sameSite = $null
            }
            foreach ($seg in $segments | Select-Object -Skip 1) {
                $s = $seg.Trim()
                if (-not $s) { continue }
                $kvIdx = $s.IndexOf('=')
                if ($kvIdx -gt 0) {
                    $k = $s.Substring(0, $kvIdx).Trim()
                    $v = $s.Substring($kvIdx + 1).Trim()
                    switch -Regex ($k.ToLower()) {
                        '^path$' { $har.path = $v }
                        '^domain$' { $har.domain = $v }
                        '^expires$' { $har.expires = $v }
                        '^samesite$' { $har.sameSite = $v }
                        default { } # ignore other key/vals
                    }
                }
                else {
                    switch ($s.ToLower()) {
                        'httponly' { $har.httpOnly = $true }
                        'secure' { $har.secure = $true }
                        default { }
                    }
                }
            }
            return $har
        }
        function Build-HarCookies-FromRequest {
            param($AssociatedCookies) # from requestWillBeSentExtraInfo.associatedCookies
            $arr = @()
            if ($AssociatedCookies) {
                foreach ($c in $AssociatedCookies) {
                    # $c = @{ blockedReason=... cookie = @{ name=..., value=..., domain=..., path=..., expires=..., httpOnly=..., secure=..., sameSite=... } }
                    $ck = $c.cookie
                    if ($ck) {
                        $arr += @{
                            name     = $ck.name
                            value    = $ck.value
                            path     = $ck.path
                            domain   = $ck.domain
                            expires  = $ck.expires
                            httpOnly = [bool]$ck.httpOnly
                            secure   = [bool]$ck.secure
                            sameSite = $ck.sameSite
                        }
                    }
                }
            }
            return $arr
        }
        function Get-ContentSizes {
            param(
                [int]$EncodedBytes,   # from loadingFinished.encodedDataLength (network bytes, compressed)
                [int]$ReceivedBytes,  # sum of dataReceived.dataLength (payload bytes)
                [string]$BodyText,    # captured body (possibly base64)
                [string]$Encoding     # 'base64' or $null
            )
            # HAR: response.content.size = uncompressed, decoded body size (best-effort)
            # HAR: response.bodySize = size of the message body transferred over the network (compressed)
            $contentSize = 0
            if ($ReceivedBytes -gt 0) {
                $contentSize = $ReceivedBytes
            }
            elseif ($BodyText) {
                $contentSize = $BodyText.Length
            }
            $bodySize = if ($EncodedBytes -ge 0) { $EncodedBytes } else { -1 }
            return @{ contentSize = $contentSize; bodySize = $bodySize }
        }
        function Invoke-CDP {
            param(
                [System.Net.WebSockets.ClientWebSocket]$Client,
                [string]$Method,
                [hashtable]$Params
            )
            $script:__cdpId++
            $p = if ($Params) { $Params } else { @{} }
            $payload = @{ id = $script:__cdpId; method = $Method; params = $p } | ConvertTo-Json -Compress
            Write-Output "[Invoke-CDP] Sending command: $Method at $(Get-Date)"
            Send-WebSocketMessage -Client $Client -Message $payload
            Write-Output "[Receive] Waiting for response at $(Get-Date)."
            while ($Client.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                $text = Receive-WebSocketText -Client $Client
                if (-not $text) { return $null }
                $obj = $null
                try {
                    $obj = $text | Where-Object { $_ -is [string] -and ($_ -match '^[\{\[]') } | ConvertFrom-Json
                }
                catch {
                    $obj = $null 
                }
                if ($obj -and $obj.id -eq $script:__cdpId) {
                    Write-Output "[Invoke-CDP] Response received for $Method`:"
                    Write-Output ($text)
                    return $obj.result
                }
                # Notifications handled in main loop
                if ($obj -and $obj.method) {
                    Process-CDPNotification -Notification $obj
                }
            }
            return $null
        }
        function Redact-SensitiveData {
            param($harEntry)
            # Redact headers (optional, if needed)
            foreach ($header in $harEntry.request.headers) {
                if ($header.name -match 'Authorization|Proxy-Authorization') {
                    $header.value = '[REDACTED]'
                }
            }
            # Redact cookies (optional, if needed)
            foreach ($cookie in $harEntry.request.cookies) {
                $cookie.value = '[REDACTED]'
            }
            foreach ($cookie in $harEntry.response.cookies) {
                $cookie.value = '[REDACTED]'
            }
            # Redact postData only if it contains "password="
            if ($harEntry.request.postData -and $harEntry.request.postData.text) {
                if ($harEntry.request.postData.text -match 'password=') {
                    $harEntry.request.postData.text = '[REDACTED]'
                }
            }
            return $harEntry
        }
        # Request/entry tracking & event handling
        $script:Requests = @{}
        $script:HAR = @{
            log = @{
                version = "1.2"
                creator = @{ name = "Edge DevTools"; version = "HAR-Capture" }
                pages   = @(@{
                        startedDateTime = (Get-Date).ToString("o")
                        id              = "page-1"
                        title           = "DevTools HAR Capture"
                        pageTimings     = @{ onContentLoad = -1; onLoad = -1 }
                    })
                entries = @()
            }
        }
        function Process-CDPNotification {
            param($Notification)
            $m = $Notification.method
            $p = $Notification.params
            Write-Host -ForegroundColor Gray "[Process-CDPNotification] Processing Notification: $(($Notification|ConvertTo-Json) -split '\n' -join "`n`t")"
            $rid = $p.requestId
            switch ($m) {
                'Network.requestWillBeSent' {
                    $rid = $p.requestId
                    $script:Requests[$rid] = @{
                        id              = $rid
                        startedDateTime = (Get-Date).ToString("o")
                        startTs         = $p.timestamp
                        request         = $p.request
                        response        = $null
                        responseTs      = $null
                        endTs           = $null
                        timings         = @{ blocked = 0; dns = -1; connect = -1; send = 0; wait = 0; receive = 0 }
                        requestExtra    = $null
                        responseExtra   = $null
                        receivedBytes   = 0
                        encodedBytes    = -1
                    }
                    Write-Host "[Event] requestWillBeSent: $($p.request.method) $($p.request.url)"
                    break
                }
                'Network.requestWillBeSentExtraInfo' {
                    $rid = $p.requestId
                    if (-not $script:Requests.ContainsKey($rid)) {
                        $script:Requests[$rid] = @{
                            id              = $rid
                            startedDateTime = (Get-Date).ToString("o")
                            timings         = @{ blocked = 0; dns = -1; connect = -1; send = 0; wait = 0; receive = 0 }
                            request         = @{ method = ''; url = ''; headers = @{} }
                            response        = $null
                            requestExtra    = $null
                            responseExtra   = $null
                            receivedBytes   = 0
                            encodedBytes    = -1
                        }
                    }
                    $parsed = Parse-HeadersText $p.headersText
                    $script:Requests[$rid].requestExtra = @{
                        headers           = Merge-HeaderMaps -Primary $p.headers -Secondary $parsed.headers
                        protocol          = $parsed.protocol
                        associatedCookies = $p.associatedCookies
                        headersText       = $p.headersText
                    }
                    Write-Host "[Event] requestWillBeSentExtraInfo: requestId=$rid protocol=$($parsed.protocol)"
                    break
                }
                'Network.responseReceived' {
                    $rid = $p.requestId
                    if (-not $script:Requests.ContainsKey($rid)) {
                        $script:Requests[$rid] = @{}
                    }
                    $script:Requests[$rid].id = $rid
                    $script:Requests[$rid].response = $p.response
                    $script:Requests[$rid].responseTs = $p.timestamp
                    Write-Host "[Event] responseReceived: $($p.response.status) $($p.response.mimeType)"
                    break
                }
                'Network.responseReceivedExtraInfo' {
                    $rid = $p.requestId
                    if (-not $script:Requests.ContainsKey($rid)) {
                        $script:Requests[$rid] = @{
                            id              = $rid
                            startedDateTime = (Get-Date).ToString("o")
                            timings         = @{ blocked = 0; dns = -1; connect = -1; send = 0; wait = 0; receive = 0 }
                            request         = @{ method = ''; url = ''; headers = @{} }
                            response        = $null
                            requestExtra    = $null
                            responseExtra   = $null
                            receivedBytes   = 0
                            encodedBytes    = -1
                        }
                    }
                    $parsed = Parse-HeadersText $p.headersText
                    $script:Requests[$rid].responseExtra = @{
                        headers                  = .{ try { Merge-HeaderMaps -Primary $p.headers -Secondary $parsed.headers } catch { $_ } }
                        protocol                 = $parsed.protocol
                        statusCode               = $p.statusCode
                        statusText               = $parsed.statusText
                        blockedCookies           = $p.blockedCookies
                        exemptedCookies          = $p.exemptedCookies
                        resourceIPAddressSpace   = $p.resourceIPAddressSpace
                        cookiePartitionKey       = $p.cookiePartitionKey
                        cookiePartitionKeyOpaque = $p.cookiePartitionKeyOpaque
                        headersText              = $p.headersText
                    }
                    Write-Host "[Event] responseReceivedExtraInfo: requestId=$rid status=$($p.statusCode) protocol=$($parsed.protocol)"
                }
                'Network.dataReceived' {
                    $rid = $p.requestId
                    if ($script:Requests.ContainsKey($rid)) {
                        $script:Requests[$rid].receivedBytes += [int]$p.dataLength
                        # encodedDataLength accumulates compressed bytes; may be 0 until loadingFinished
                        if ($p.encodedDataLength -gt 0) {
                            if ($script:Requests[$rid].encodedBytes -lt 0) { $script:Requests[$rid].encodedBytes = 0 }
                            $script:Requests[$rid].encodedBytes += [int]$p.encodedDataLength
                        }
                    }
                    Write-Host "[Event] dataReceived: requestId=$rid +$($p.dataLength)B (encoded +$($p.encodedDataLength)B)"
                }
                'Network.loadingFinished' {
                    $rid = $p.requestId
                    if ($script:Requests.ContainsKey($rid)) {
                        $script:Requests[$rid].endTs = $p.timestamp
                        # Prefer encodedDataLength reported by loadingFinished
                        if ($p.encodedDataLength -ge 0) {
                            $script:Requests[$rid].encodedBytes = [int]$p.encodedDataLength
                        }
                        # Fetch body (synchronous)
                        $res = Invoke-CDP -Client $script:Client -Method 'Network.getResponseBody' -Params @{ requestId = $rid }
                        $bodyText = $null; $encoding = $null
                        if ($res) {
                            $bodyText = $res.body
                            if ($res.base64Encoded) { $encoding = 'base64' }
                        }
                        # Timings in ms
                        $startTs = $script:Requests[$rid].startTs
                        $respTs = $script:Requests[$rid].responseTs
                        $endTs = $script:Requests[$rid].endTs
                        if ($startTs -and $respTs) { $script:Requests[$rid].timings.wait = [math]::Round(($respTs - $startTs) * 1000) }
                        if ($respTs -and $endTs) { $script:Requests[$rid].timings.receive = [math]::Round(($endTs - $respTs) * 1000) }
                        $totalMs = if ($startTs -and $endTs) { [math]::Round(($endTs - $startTs) * 1000) } else { 0 }
                        # Build HAR entry (merge extra info)
                        $req = $script:Requests[$rid].request
                        $reqExtra = $script:Requests[$rid].requestExtra
                        $resp = $script:Requests[$rid].response
                        $respExtra = $script:Requests[$rid].responseExtra
                        $reqHeadersMerged = Merge-HeaderMaps -Primary $req.headers  -Secondary ($reqExtra?.headers)
                        $respHeadersMerged = Merge-HeaderMaps -Primary $resp.headers -Secondary ($respExtra?.headers)
                        $httpVersionReq = $reqExtra?.protocol
                        $httpVersionResp = $respExtra?.protocol
                        $statusCode = if ($respExtra?.statusCode) { $respExtra.statusCode } else { $resp.status }
                        $statusText = if ($respExtra?.statusText) { $respExtra.statusText } else { $resp.statusText }
                        # QueryString and Cookies
                        $queryStringArr = Parse-QueryString $req.url
                        $requestCookies = Build-HarCookies-FromRequest ($reqExtra?.associatedCookies)
                        $responseCookies = Parse-SetCookieHeaders -HeadersMap $respHeadersMerged -HeadersText ($respExtra?.headersText)
                        # Sizes
                        $sizes = Get-ContentSizes -EncodedBytes $script:Requests[$rid].encodedBytes `
                        -ReceivedBytes $script:Requests[$rid].receivedBytes `
                        -BodyText $bodyText -Encoding $encoding
                        if ($req.postData) { $PostData = @{ text = $req.postData } } else { $PostData = $null }
                        $entry = @{
                            startedDateTime = $script:Requests[$rid].startedDateTime
                            time            = $totalMs
                            request         = @{
                                method      = $req.method
                                url         = $req.url
                                httpVersion = $httpVersionReq
                                headers     = Convert-HeadersToHarArray -Headers $reqHeadersMerged
                                queryString = $queryStringArr
                                cookies     = $requestCookies
                                headersSize = -1
                                bodySize    = -1
                                postData    = $PostData
                            }
                            response        = @{
                                status      = $statusCode
                                statusText  = $statusText
                                httpVersion = $httpVersionResp
                                headers     = Convert-HeadersToHarArray -Headers $respHeadersMerged
                                cookies     = $responseCookies
                                content     = @{
                                    size     = $sizes.contentSize
                                    mimeType = $resp.mimeType
                                    text     = $bodyText
                                    encoding = $encoding
                                }
                                headersSize = -1
                                bodySize    = $sizes.bodySize
                                # Optional: preserve extraInfo metadata in comment for audit
                                comment     = (if ($respExtra) { ($respExtra | ConvertTo-Json -Compress) } else { $null })
                            }
                            cache           = @{}
                            timings         = $script:Requests[$rid].timings
                            pageref         = "page-1"
                        }
                        $script:HAR.log.entries += $entry
                        Write-Host "[Event] loadingFinished: added HAR entry for $($req.url) ($totalMs ms)"
                        $script:Requests.Remove($rid) | Out-Null
                    }
                    break
                }
                'Network.loadingFailed' {
                    $rid = $p.requestId
                    Write-Host "[Event] loadingFailed: requestId=$rid errorText=$($p.errorText) canceled=$($p.canceled)"
                    if ($script:Requests.ContainsKey($rid)) {
                        $req = $script:Requests[$rid].request
                        $entry = @{
                            startedDateTime = $script:Requests[$rid].startedDateTime
                            time            = 0
                            request         = @{
                                method      = $req.method
                                url         = $req.url
                                headers     = Convert-HeadersToHarArray -Headers $req.headers
                                queryString = Parse-QueryString $req.url
                                headersSize = -1
                                bodySize    = -1
                                postData    = (if ($req.postData) { @{ text = $req.postData } } else { $null })
                            }
                            response        = @{
                                status      = 0
                                statusText  = $p.errorText
                                headers     = @()
                                cookies     = @()
                                content     = @{ size = 0; mimeType = ""; text = "" }
                                headersSize = -1
                                bodySize    = -1
                            }
                            cache           = @{}
                            timings         = @{ blocked = 0; dns = -1; connect = -1; send = 0; wait = 0; receive = 0 }
                            pageref         = "page-1"
                        }
                        $script:HAR.log.entries += $entry
                        $script:Requests.Remove($rid) | Out-Null
                    }
                    break
                }
                'Network.resourceChangedPriority' {
                    # This event fires when the priority of a network resource changes (e.g., from Low to High)
                    $rid = $p.requestId
                    $newPriority = $p.newPriority
                    $timestamp = $p.timestamp
                    Write-Host "[Event] resourceChangedPriority: requestId=$rid newPriority=$newPriority at $timestamp"
                    # If the request is being tracked, update its metadata
                    if ($script:Requests.ContainsKey($rid)) {
                        if (-not $script:Requests[$rid].ContainsKey('priorityChanges')) {
                            $script:Requests[$rid].priorityChanges = @()
                        }
                        $script:Requests[$rid].priorityChanges += @{
                            timestamp   = $timestamp
                            newPriority = $newPriority
                        }
                    }
                    break
                }
                'Network.policyUpdated' {
                    # Fires when a network-related policy changes (e.g., CSP, mixed content)
                    $policy = $p.policy
                    $source = $p.source
                    Write-Host "[Event] policyUpdated: source=$source policy=$policy"
                    # Optional: store in HAR comment or a separate array for audit
                    if (-not $script:HAR.log.ContainsKey('policyUpdates')) {
                        $script:HAR.log.policyUpdates = @()
                    }
                    $script:HAR.log.policyUpdates += @{
                        timestamp = (Get-Date).ToString("o")
                        source    = $source
                        policy    = $policy
                    }
                    break
                }
                'Network.requestServedFromCache' {
                    $rid = $p.requestId
                    Write-Host "[Event] RequestID: $rid requestServedFromCache: requestId=$rid"
                    # If the request is tracked, mark it as served from cache
                    if ($script:Requests.ContainsKey($rid)) {
                        $script:Requests[$rid].servedFromCache = $true
                    }
                }
                'Inspector.detached' {
                    Write-Host "[Event] Inspector.detached: DevTools session ended."
                    # Optionally set a flag to break the main loop
                    $script:SessionDetached = $true
                    break
                }
                default {
                    Write-Host -ForegroundColor Red "[Process-CDPNotification] Unhandled Notification Method: $m"
                }
            }
            if ($rid -and $script:Requests.ContainsKey($rid)) {
                $script:HAR.log.entries += $script:Requests[$rid]
            }
        }
    }
    process {
        # Connect PAGE WebSocket & enable Network
        $script:Client = [System.Net.WebSockets.ClientWebSocket]::new()
        $script:Client.ConnectAsync([System.Uri]$wsUrl, [Threading.CancellationToken]::None).Wait()
        # Enable network & disable cache (page-level commands work here)
        Invoke-CDP -Client $script:Client -Method 'Network.enable' -Params @{} | Out-Null
        Invoke-CDP -Client $script:Client -Method 'Network.setCacheDisabled' -Params @{ cacheDisabled = $true } | Out-Null
        Write-Output "[Job] HAR capture started at $(Get-Date)"
        # Loop controls
        $lastFlush = Get-Date
        $deadline = (Get-Date).AddMinutes(5)   # 5-minute cap
        while ($script:Client.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            Write-Output "`n[Loop] Iteration start at $(Get-Date)"
            # Stop if Edge process exited
            if (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) {
                Write-Output "[Loop] Edge process closed. Ending capture."
                break
            }
            # Stop at 5-minute cap
            if ((Get-Date) -ge $deadline) {
                Write-Output "[Loop] Time limit reached. Ending capture."
                break
            }
            # Endpoint health check (break if /json/version fails)
            if ($Null -eq $ver) {
                try { $ver = Invoke-RestMethod -Uri "http://localhost:$BrowserDebuggingPort/json/version" -TimeoutSec 5 } catch { $ver = $null }
                if (-not $ver) {
                    Write-Output "[Loop] DevTools endpoint not responding. Ending capture."
                    break
                }
            }
            # Pump one message
            $text = Receive-WebSocketText -Client $script:Client
            if ($text) {
                try {
                    $text | Where-Object { $_ -isnot [string] }
                    $text | Where-Object { $_ -is [string] -and ($_ -match '^[\[\{]') } | ForEach-Object {
                        $obj = $_ | ConvertFrom-Json
                        if ($obj.method) {
                            write-host "[EdgeDebugJob_SB] Running Process-CDPNotification -Notification $obj"
                            Process-CDPNotification -Notification $obj
                        }
                    }
                }
                catch {
                    Write-Output "[Loop] JSON parse error for WebSocket frame."
                }
            }
            # Snapshot every 30 seconds
            if ((Get-Date) - $lastFlush -ge [TimeSpan]::FromSeconds(30)) {
                $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
                $harFileName = "$encodedUrl--$userDomain-$userName-$computerName-$timestamp.har"
                $harFilePath = Join-Path $dropFolder $harFileName
                $script:HAR.log.entries = $script:HAR.log.entries | Group-Object Id |
                ForEach-Object {
                    $last = $_.Group | Select-Object -Last 1
                    Redact-SensitiveData $last
                }
                $script:HAR | ConvertTo-Json -Depth 12 | Out-File $harFilePath -Encoding UTF8
                Write-Output "[Snapshot] Saved: $harFilePath"
                $lastFlush = Get-Date
            }
            if ($script:SessionDetached) {
                Write-Output "[Loop] Session detached. Ending capture."
                break
            }
            Start-Sleep -Milliseconds 100
        }
    }
    end {
        # Final HAR (base name per requirement)
        $finalName = "$encodedUrl--$userDomain-$userName-$computerName.har"
        $finalPath = Join-Path $dropFolder $finalName
        $script:HAR.log.entries = $script:HAR.log.entries | Group-Object Id |
        ForEach-Object {
            $last = $_.Group | Select-Object -Last 1
            Redact-SensitiveData $last
        }
        $script:HAR | ConvertTo-Json -Depth 12 | Out-File $finalPath -Encoding UTF8
        Write-Output "[Final] HAR saved at $finalPath"
    }
}
$ArgList = @(
    $wsUrl, $dropFolder, $encodedUrl, $userDomain, $userName, $computerName, $BrowserDebuggingPort, $proc.Id
)
if ($wsUrl -notmatch '://') {
    return Write-Warning ""
}
$job = Start-Job -Name EdgeDebugJob -ScriptBlock $EdgeDebugJob_SB -ArgumentList $ArgList
#. $EdgeDebugJob_SB @ArgList
Write-Host "HAR capture job started (Id: $($job.Id))."
# ==========================
# Monitor the job (your loop)
# ==========================
$Output = [System.Collections.ArrayList]::new()
while ($job) {
    Start-Sleep 1
    $job = $job | Get-Job -ErrorAction Ignore
    if (!$job) { break }
    if ($Job.HasMoreData) {
        $job | Receive-Job | ForEach-Object {
            if ($_.method) { $Output.Add($_) | Out-Null }
            $_
        }
    }
    if ($job.PSEndTime) {
        $job | Receive-Job -Wait -AutoRemoveJob | ForEach-Object {
            if ($_.method) { $Output.Add($_) | Out-Null }
            $_
        }
    }
}
Write-Host "Capture job ended."