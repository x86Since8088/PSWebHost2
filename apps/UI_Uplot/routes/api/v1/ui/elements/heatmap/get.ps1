#Requires -Version 7

<#
.SYNOPSIS
    Heatmap Component Endpoint
.DESCRIPTION
    Serves the heatmap viewer with color scale visualization
#>

param($Request, $Response, $Session)

# Build HTML response
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Heatmap - uPlot Chart Builder</title>

    <!-- Font Awesome -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">

    <!-- uPlot CSS -->
    <link rel="stylesheet" href="/public/lib/uPlot.min.css">

    <!-- Component Styles -->
    <link rel="stylesheet" href="/apps/uplot/public/elements/heatmap/style.css">
</head>
<body>
    <heat-map></heat-map>

    <!-- Console Logger -->
    <script src="/apps/uplot/public/elements/console-logger.js"></script>

    <!-- uPlot Library -->
    <script src="/public/lib/uPlot.iife.min.js"></script>

    <!-- Heatmap Component -->
    <script src="/apps/uplot/public/elements/heatmap/component.js"></script>
</body>
</html>
"@

# Set response content type and send HTML
$Response.ContentType = 'text/html; charset=utf-8'
$Response.Write($html)
