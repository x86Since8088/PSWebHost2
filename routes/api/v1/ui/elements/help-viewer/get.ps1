param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

# Help Viewer API endpoint
# Converts markdown files to HTML for display in the help viewer card

# Define the markdown converter function first
function Convert-MarkdownToHtml {
    param([string]$Markdown)

    # Basic markdown to HTML conversion
    $html = $Markdown

    # Escape HTML special characters first (except for our conversions)
    # Skip this for now to allow HTML in markdown

    # Headers (must be at start of line)
    $html = $html -replace '(?m)^######\s+(.+)$', '<h6>$1</h6>'
    $html = $html -replace '(?m)^#####\s+(.+)$', '<h5>$1</h5>'
    $html = $html -replace '(?m)^####\s+(.+)$', '<h4>$1</h4>'
    $html = $html -replace '(?m)^###\s+(.+)$', '<h3>$1</h3>'
    $html = $html -replace '(?m)^##\s+(.+)$', '<h2>$1</h2>'
    $html = $html -replace '(?m)^#\s+(.+)$', '<h1>$1</h1>'

    # Code blocks (fenced)
    $html = $html -replace '(?ms)```(\w*)\r?\n(.*?)```', '<pre><code class="language-$1">$2</code></pre>'

    # Inline code
    $html = $html -replace '`([^`]+)`', '<code>$1</code>'

    # Bold and italic
    $html = $html -replace '\*\*\*(.+?)\*\*\*', '<strong><em>$1</em></strong>'
    $html = $html -replace '\*\*(.+?)\*\*', '<strong>$1</strong>'
    $html = $html -replace '\*(.+?)\*', '<em>$1</em>'
    $html = $html -replace '___(.+?)___', '<strong><em>$1</em></strong>'
    $html = $html -replace '__(.+?)__', '<strong>$1</strong>'
    $html = $html -replace '_(.+?)_', '<em>$1</em>'

    # Links
    $html = $html -replace '\[([^\]]+)\]\(([^\)]+)\)', '<a href="$2">$1</a>'

    # Images
    $html = $html -replace '!\[([^\]]*)\]\(([^\)]+)\)', '<img src="$2" alt="$1" />'

    # Horizontal rules
    $html = $html -replace '(?m)^---+\s*$', '<hr />'
    $html = $html -replace '(?m)^\*\*\*+\s*$', '<hr />'

    # Unordered lists (simple)
    $html = $html -replace '(?m)^\s*[-*+]\s+(.+)$', '<li>$1</li>'

    # Ordered lists (simple)
    $html = $html -replace '(?m)^\s*\d+\.\s+(.+)$', '<li>$1</li>'

    # Wrap consecutive list items
    $html = $html -replace '(<li>.*?</li>)(\s*<li>)', '$1$2'

    # Blockquotes
    $html = $html -replace '(?m)^>\s+(.+)$', '<blockquote>$1</blockquote>'

    # Paragraphs - wrap text blocks
    $html = $html -replace '(?m)^([^<\r\n].+)$', '<p>$1</p>'

    # Clean up empty paragraphs
    $html = $html -replace '<p>\s*</p>', ''

    # Add basic styling
    $styledHtml = @"
<style>
.markdown-body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; }
.markdown-body h1 { border-bottom: 1px solid var(--border-color, #eee); padding-bottom: 0.3em; }
.markdown-body h2 { border-bottom: 1px solid var(--border-color, #eee); padding-bottom: 0.3em; }
.markdown-body code { background: var(--code-bg, #f4f4f4); padding: 2px 6px; border-radius: 3px; font-family: 'Consolas', 'Monaco', monospace; }
.markdown-body pre { background: var(--code-bg, #f4f4f4); padding: 16px; border-radius: 6px; overflow: auto; }
.markdown-body pre code { background: none; padding: 0; }
.markdown-body blockquote { border-left: 4px solid var(--accent-color, #0366d6); margin: 0; padding-left: 16px; color: var(--text-muted, #6a737d); }
.markdown-body a { color: var(--link-color, #0366d6); text-decoration: none; }
.markdown-body a:hover { text-decoration: underline; }
.markdown-body li { margin: 4px 0; }
.markdown-body hr { border: none; border-top: 1px solid var(--border-color, #eee); margin: 24px 0; }
</style>
$html
"@

    return $styledHtml
}

# Get the requested help file path
$filePath = $Request.QueryString["file"]

if ([string]::IsNullOrEmpty($filePath)) {
    $errorResponse = @{
        status = 'error'
        message = 'No help file specified. Use ?file=path/to/file.md'
    } | ConvertTo-Json
    context_response -Response $Response -StatusCode 400 -String $errorResponse -ContentType "application/json"
    return
}

# Security: Sanitize the file path to prevent directory traversal
$filePath = $filePath -replace '\.\.', '' -replace '//', '/'
$filePath = $filePath.TrimStart('/', '\')

# Look for the file in multiple locations
$searchPaths = @(
    (Join-Path $Global:PSWebServer.Project_Root.Path "public/help/$filePath"),
    (Join-Path $Global:PSWebServer.Project_Root.Path $filePath),
    (Join-Path $Global:PSWebServer.Project_Root.Path "docs/$filePath")
)

$foundPath = $null
foreach ($path in $searchPaths) {
    if (Test-Path $path -PathType Leaf) {
        $foundPath = $path
        break
    }
}

if (-not $foundPath) {
    $errorResponse = @{
        status = 'error'
        message = "Help file not found: $filePath"
        searched = $searchPaths
    } | ConvertTo-Json
    context_response -Response $Response -StatusCode 404 -String $errorResponse -ContentType "application/json"
    return
}

# Read the markdown content
try {
    $markdownContent = Get-Content -Path $foundPath -Raw -ErrorAction Stop

    # Convert markdown to HTML using a simple converter
    $html = Convert-MarkdownToHtml -Markdown $markdownContent

    $successResponse = @{
        status = 'success'
        file = $filePath
        html = $html
        content = $markdownContent
    } | ConvertTo-Json -Depth 10

    context_response -Response $Response -String $successResponse -ContentType "application/json"
} catch {
    $errorResponse = @{
        status = 'error'
        message = "Error reading help file: $($_.Exception.Message)"
    } | ConvertTo-Json
    context_response -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
}
