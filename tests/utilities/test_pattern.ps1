$requestedPath = "/apps/WebHostDebugExtensions/public/debug-poll-service.js"

Write-Host "Testing URL: $requestedPath"

if ($requestedPath -match '^/apps/(?<appname>[a-zA-Z0-9_-]+)/public/(?<filepath>.+)$') {
    Write-Host "Pattern MATCHED!" -ForegroundColor Green
    Write-Host "  AppName: $($matches.appname)"
    Write-Host "  FilePath: $($matches.filepath)"
} else {
    Write-Host "Pattern DID NOT MATCH!" -ForegroundColor Red
}

Write-Host "`nChecking switch -regex:"
switch -regex ($requestedPath) {
    '^/public/' {
        Write-Host "Matched: ^/public/" -ForegroundColor Yellow
    }
    '^/apps/[^/]+/public/' {
        Write-Host "Matched: ^/apps/[^/]+/public/" -ForegroundColor Green
    }
    default {
        Write-Host "Matched: default" -ForegroundColor Red
    }
}
