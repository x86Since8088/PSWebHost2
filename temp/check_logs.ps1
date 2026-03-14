$logDir = "C:\SC\PsWebHost\PsWebHost_Data\Logs"
$newestLog = Get-ChildItem -Path $logDir -Filter "log*.tsv" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host "Reading log file: $($newestLog.FullName)"
$logs = Get-Content $newestLog.FullName | ConvertFrom-Csv -Delimiter "`t"
$filtered = $logs | Where-Object {
    $_.Category -like "*Worker*" -or
    $_.Category -like "*Metrics*" -or
    $_.escapedMessage -like "*DuckDB*" -or
    $_.escapedMessage -like "*Worker*" -or
    $_.escapedMessage -like "*stub*" -or
    $_.escapedMessage -like "*init*"
}
$filtered | Select-Object -Last 40 localTime, Severity, Category, escapedMessage | Format-Table -AutoSize -Wrap
