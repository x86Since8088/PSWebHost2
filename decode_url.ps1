$url = 'eyJ2ZXJzaW9uIjoyLCJjYXJkcyI6W3siaWQiOiJyZWFsdGltZS1ldmVudHMtMTc2OTQ5MzY1OTgzOSIsIngiOjAsInkiOjAsInciOjEyLCJoIjozMCwiZWxlbWVudElkIjoicmVhbHRpbWUtZXZlbnRzIiwidGl0bGUiOiJSZWFsLXRpbWUgRXZlbnRzIiwiZW5kcG9pbnQiOiIvYXBwcy9XZWJob3N0UmVhbHRpbWVFdmVudHMvYXBpL3YxL3VpL2VsZW1lbnRzL3JlYWx0aW1lLWV2ZW50cyJ9LHsiaWQiOiJmaWxlLWV4cGxvcmVyLTE3Njk0OTQ4NTEyMzUiLCJ4IjowLCJ5IjozMCwidyI6MTIsImgiOjE0LCJlbGVtZW50SWQiOiJmaWxlLWV4cGxvcmVyIiwidGl0bGUiOiJGaWxlIEV4cGxvcmVyIiwiZW5kcG9pbnQiOiIvYXBwcy9XZWJob3N0RmlsZUV4cGxvcmVyL2FwaS92MS91aS9lbGVtZW50cy9maWxlLWV4cGxvcmVyIn0seyJpZCI6InRhc2stbWFuYWdlci0xNzY5NDk0OTYwMDM1IiwieCI6MCwieSI6NDQsInciOjEyLCJoIjoxNCwiZWxlbWVudElkIjoidGFzay1tYW5hZ2VyIiwidGl0bGUiOiJUYXNrIE1hbmFnZW1lbnQiLCJlbmRwb2ludCI6Ii9hcHBzL1dlYkhvc3RUYXNrTWFuYWdlbWVudC9hcGkvdjEvdWkvZWxlbWVudHMvdGFzay1tYW5hZ2VyIn0seyJpZCI6InRhc2stbWFuYWdlci0xNzY5NDk0OTYwMDM1IiwieCI6MCwieSI6NDQsInciOjEyLCJoIjoxNCwiZWxlbWVudElkIjoidGFzay1tYW5hZ2VyIiwidGl0bGUiOiJUYXNrIE1hbmFnZW1lbnQiLCJlbmRwb2ludCI6Ii9hcHBzL1dlYkhvc3RUYXNrTWFuYWdlbWVudC9hcGkvdjEvdWkvZWxlbWVudHMvdGFzay1tYW5hZ2VyIn1dfQ=='
$decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($url))
$layout = $decoded | ConvertFrom-Json

Write-Host "`nVersion: $($layout.version)" -ForegroundColor Cyan
Write-Host "Card Count: $($layout.cards.Count)" -ForegroundColor Cyan

Write-Host "`nCards:" -ForegroundColor Yellow
$layout.cards | ForEach-Object {
    Write-Host "  - $($_.id)" -ForegroundColor White
    Write-Host "    Title: $($_.title)" -ForegroundColor Gray
    Write-Host "    Position: x=$($_.x) y=$($_.y)" -ForegroundColor Gray
    Write-Host "    Size: w=$($_.w) h=$($_.h)" -ForegroundColor Gray
    Write-Host "    Endpoint: $($_.endpoint)" -ForegroundColor DarkGray
    Write-Host ""
}

# Check for duplicates
$duplicates = $layout.cards | Group-Object -Property id | Where-Object { $_.Count -gt 1 }
if ($duplicates) {
    Write-Host "⚠ DUPLICATES FOUND:" -ForegroundColor Red
    $duplicates | ForEach-Object {
        Write-Host "  - $($_.Name) appears $($_.Count) times" -ForegroundColor Red
    }
} else {
    Write-Host "✓ No duplicate cards" -ForegroundColor Green
}
