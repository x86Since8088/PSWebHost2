#Requires -Version 7

<#
.SYNOPSIS
    Multi-Axis Chart Component Endpoint
.DESCRIPTION
    Serves the multi-axis chart viewer with uPlot integration
#>

param($Request, $Response, $Session)

# Build HTML response
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Multi-Axis Chart - uPlot Chart Builder</title>

    <!-- Font Awesome -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">

    <!-- uPlot CSS -->
    <link rel="stylesheet" href="/public/lib/uPlot.min.css">

    <!-- Component Styles -->
    <link rel="stylesheet" href="/apps/uplot/public/elements/multi-axis/style.css">
</head>
<body>
    <multi-axis></multi-axis>

    <!-- Console Logger -->
    <script src="/apps/uplot/public/elements/console-logger.js"></script>

    <!-- uPlot Library -->
    <script src="/public/lib/uPlot.iife.min.js"></script>

    <!-- uPlot Data Adapter -->
    <script src="/public/lib/uplot-data-adapter.js"></script>

    <!-- Multi-Axis Chart Component -->
    <script src="/apps/uplot/public/elements/multi-axis/component.js"></script>
</body>
</html>
"@

# Set response content type and send HTML
$Response.ContentType = 'text/html; charset=utf-8'
$Response.Write($html)
