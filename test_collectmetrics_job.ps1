#Requires -Version 7

# Test script for CollectMetrics job
$variables = @{
    Interval = '10'
}

& ".\system\utility\TaskManagement_AppJobFolder_Test.ps1" -AppName "WebHostMetrics" -JobName "CollectMetrics" -Variables $variables
