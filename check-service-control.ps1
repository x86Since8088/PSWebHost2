$data = Get-Content PsWebHost_Data/system/utility/Analyze-Dependencies.json | ConvertFrom-Json
$data.Results | Where-Object { $_.FilePath -like '*service-control*' } | Select-Object FilePath | Format-List
