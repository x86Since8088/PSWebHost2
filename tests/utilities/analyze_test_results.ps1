$report = Get-Content 'C:\SC\PsWebHost\card_test_report_20260201_204042.json' | ConvertFrom-Json

Write-Host '=== OVERALL SUMMARY ===' -ForegroundColor Cyan
Write-Host "Total Cards: $($report.TotalCards)"
Write-Host "Passed Cards: $($report.PassedCards)"
Write-Host "Failed Cards: $($report.FailedCards)"
Write-Host "Tests Passed: $($report.TestsPassed)"
Write-Host "Tests Failed: $($report.TestsFailed)"
Write-Host "Tests Warning: $($report.TestsWarning)"
Write-Host ""

Write-Host '=== CARDS BY STATUS ===' -ForegroundColor Cyan
$report.CardResults | Group-Object OverallStatus | ForEach-Object {
    Write-Host "  $($_.Name): $($_.Count) cards"
}

Write-Host "`n=== ERROR TYPE BREAKDOWN ===" -ForegroundColor Cyan
$errorDetails = $report.CardResults | Where-Object { $_.OverallStatus -eq 'Error' } | ForEach-Object {
    $_.Tests | Where-Object { $_.Status -eq 'Error' } | ForEach-Object { $_.Details }
}
$errorDetails | Group-Object | Sort-Object Count -Descending | ForEach-Object {
    Write-Host "  [$($_.Count)] $($_.Name)"
}

Write-Host "`n=== CARDS WITH 404 ERRORS ===" -ForegroundColor Yellow
$report.CardResults | Where-Object { $_.Tests.Details -like '*404*' } | ForEach-Object {
    Write-Host "  - $($_.CardName) ($($_.App))"
}

Write-Host "`n=== CARDS WITH TIMEOUT ERRORS ===" -ForegroundColor Yellow
$report.CardResults | Where-Object { $_.Tests.Details -like '*Timeout*' -or $_.Tests.Details -like '*HttpClient.Timeout*' } | ForEach-Object {
    Write-Host "  - $($_.CardName) ($($_.App))"
}

Write-Host "`n=== CARDS WITH COMPONENT REGISTRATION WARNINGS ===" -ForegroundColor Yellow
$report.CardResults | Where-Object { $_.IssuesFound -like '*window.cardComponents registration*' } | ForEach-Object {
    Write-Host "  - $($_.CardName) ($($_.App))"
}
