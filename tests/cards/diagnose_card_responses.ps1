# Diagnose Card Response Pattern

Write-Host "`n===== Diagnosing Card Responses =====" -ForegroundColor Cyan

$testCards = @(
    @{ Name = "System Log"; Url = "http://localhost:8080/cards/system-log" }
    @{ Name = "Memory Explorer"; Url = "http://localhost:8080/cards/memory-explorer" }
    @{ Name = "Docker Manager"; Url = "http://localhost:8080/apps/dockermanager/cards/docker-manager" }
)

foreach ($card in $testCards) {
    Write-Host "`n--- $($card.Name) ---" -ForegroundColor Yellow
    Write-Host "URL: $($card.Url)" -ForegroundColor Gray

    try {
        # Get session cookie
        $response1 = Invoke-WebRequest -Uri $card.Url -SessionVariable session -UseBasicParsing -ErrorAction Stop

        # Get actual content
        $response2 = Invoke-WebRequest -Uri $card.Url -WebSession $session -UseBasicParsing -ErrorAction Stop

        if ($response2.StatusCode -eq 200) {
            $json = $response2.Content | ConvertFrom-Json

            Write-Host "Response Keys:" -ForegroundColor Green
            $json.PSObject.Properties | ForEach-Object {
                Write-Host "  - $($_.Name): " -NoNewline -ForegroundColor White
                if ($_.Value -is [string] -and $_.Value.Length -lt 100) {
                    Write-Host "$($_.Value)" -ForegroundColor Gray
                } elseif ($_.Value -is [string]) {
                    Write-Host "$($_.Value.Substring(0,100))..." -ForegroundColor Gray
                } else {
                    Write-Host "$($_.Value.GetType().Name)" -ForegroundColor Gray
                }
            }

            # Check critical fields
            Write-Host "`nCritical Fields:" -ForegroundColor Cyan
            if ($json.scriptPath) {
                Write-Host "  ✓ scriptPath: $($json.scriptPath)" -ForegroundColor Green
            } else {
                Write-Host "  × scriptPath: MISSING" -ForegroundColor Red
            }

            if ($json.componentPath) {
                Write-Host "  ✓ componentPath: $($json.componentPath)" -ForegroundColor Green
            } else {
                Write-Host "  × componentPath: MISSING" -ForegroundColor Red
            }

            if ($json.url) {
                Write-Host "  ℹ url: $($json.url)" -ForegroundColor Yellow
            }

        } else {
            Write-Host "  Status: $($response2.StatusCode)" -ForegroundColor Red
        }

    } catch {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n===== Diagnosis Complete =====" -ForegroundColor Cyan
