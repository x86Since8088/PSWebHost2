$data = Get-Content PsWebHost_Data/system/utility/Analyze-Dependencies.json | ConvertFrom-Json
Write-Host "Sample paths in analysis:"
$data.Results | Where-Object { $_.FilePath -like '*docker*' -or $_.FilePath -like '*linux*' -or $_.FilePath -like '*service*' } | Select-Object -First 15 FilePath | Format-Table
