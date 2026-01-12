#Requires -Version 7

<#
.SYNOPSIS
    uPlot Chart Builder Home Component
.DESCRIPTION
    Serves the main landing page with chart type cards and data source selection
#>

param($Request, $Response, $Session)

# Build HTML response with integrated component
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>uPlot Chart Builder - PSWebHost</title>

    <!-- Font Awesome -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">

    <!-- Component Styles -->
    <link rel="stylesheet" href="/apps/uplot/public/elements/uplot-home/style.css">

    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            min-height: 100vh;
        }

        .page-container {
            min-height: 100vh;
            padding: 20px;
        }

        .loading-spinner {
            display: flex;
            justify-content: center;
            align-items: center;
            height: 400px;
        }

        .spinner {
            border: 4px solid #f3f4f6;
            border-top: 4px solid #3b82f6;
            border-radius: 50%;
            width: 50px;
            height: 50px;
            animation: spin 1s linear infinite;
        }

        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
    </style>
</head>
<body>
    <div class="page-container">
        <div class="loading-spinner">
            <div class="spinner"></div>
        </div>
        <uplot-home-component></uplot-home-component>
    </div>

    <!-- Console Logger -->
    <script src="/apps/uplot/public/elements/console-logger.js"></script>

    <!-- Home Component -->
    <script src="/apps/uplot/public/elements/uplot-home/component.js"></script>

    <script>
        // Hide loading spinner once component is loaded
        document.addEventListener('DOMContentLoaded', () => {
            setTimeout(() => {
                document.querySelector('.loading-spinner').style.display = 'none';
            }, 100);
        });
    </script>
</body>
</html>
"@

# Set response content type and send HTML
$Response.ContentType = 'text/html; charset=utf-8'
$Response.Write($html)
