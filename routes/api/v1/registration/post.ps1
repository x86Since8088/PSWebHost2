param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    [hashtable]$SessionData,
    [hashtable]$CardSettings
)

# Import required modules
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Database/PSWebHost_Database.psm1") -DisableNameChecking

# --- Helper Functions ---

function Get-SurveyPage($pageName) {
    $surveyPath = Join-Path $PSScriptRoot 'survey.json'
    $survey = Get-Content -Path $surveyPath | ConvertFrom-Json
    return $survey.pages.$pageName
}

function New-HtmlForm($page) {
    $html = "<h2>$($page.title)</h2>"
    if ($page.message) {
        $html += "<p>$($page.message)</p>"
    }
    $html += "<form id='regForm'>"
    if ($page.form.hidden) {
        foreach ($field in $page.form.hidden) {
            $html += "<input type='hidden' name='$($field.name)' value='$($field.value)'>"
        }
    }
    if ($page.form.fields) {
        foreach ($field in $page.form.fields) {
            $required = if ($field.required) { "required" } else { "" }
            $html += "<label for='$($field.name)'>$($field.label)</label>"
            $html += "<input type='$($field.type)' name='$($field.name)' id='$($field.name)' $required>"
        }
    }
    if ($page.form.submit) {
        $html += "<button type='submit' class='btn'>$($page.form.submit.label)</button>"
    }
    $html += "</form>"
    return $html
}

function New-JsonResponse($status, $html) {
    return @{ status = $status; Html = $html } | ConvertTo-Json
}

# --- Main Logic ---

# Read request body
$reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
$bodyContent = $reader.ReadToEnd()
$reader.Close()
$parsedBody = [System.Web.HttpUtility]::ParseQueryString($bodyContent)
$pageName = $parsedBody["page"]

Write-Host "Processing page: $(($bodyContent) -split '\n' -join "`n`t")"

if ([string]::IsNullOrEmpty($pageName)) {
    # Initial request, serve the first page
    $page = Get-SurveyPage -pageName 'ProvideEmail'
    $html = New-HtmlForm -page $page
    $jsonResponse = New-JsonResponse -status 'continue' -html $html
    context_reponse -Response $Response -String $jsonResponse -ContentType "application/json"
    return
}

if ($pageName -eq 'ProvideEmail') {
    $email = $parsedBody["email"]
    
    # Validate email format
    if ($email -notmatch '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') {
        $page = Get-SurveyPage -pageName 'ProvideEmail'
        $html = "<p class='error'>Invalid email address format.</p>" + (New-HtmlForm -page $page)
        $jsonResponse = New-JsonResponse -status 'fail' -html $html
        context_reponse -Response $Response -StatusCode 400 -String $jsonResponse -ContentType "application/json"
        return
    }

    $guid = [Guid]::NewGuid().ToString()
    $requestDate = (Get-Date).ToString("s")
    $requestIp = $Context.Request.RemoteEndPoint.Address.ToString()
    $requestSessionId = $SessionData.SessionID

    New-PSWebSQLiteData -File "pswebhost.db" -Table "account_email_confirmation" -Data @{
        email_request_guid = $guid
        email = $email
        request_date = $requestDate
        request_ip = $requestIp
        request_session_id = $requestSessionId
    }

    # Simulate sending email by logging the link
    $confirmationLink = "http://localhost:8080/api/v1/registration/confirm/email?ref=$guid"
    Write-PSWebHostLog -Severity 'Info' -Category 'Registration' -Message "Confirmation link for ${email}: $confirmationLink"

    $nextPage = Get-SurveyPage -pageName 'ConfirmEmail'
    $html = New-HtmlForm -page $nextPage
    $html = $html.Replace('{email}', $email)
    
    $jsonResponse = New-JsonResponse -status 'continue' -html $html
    context_reponse -Response $Response -String $jsonResponse -ContentType "application/json"
    return
}

if ($pageName -eq 'ConfirmEmail') {
    $email = $parsedBody["email"]
    
    $query = "SELECT * FROM account_email_confirmation WHERE email = '$email' AND response_date IS NOT NULL;"
    $confirmation = Get-PSWebSQLiteData -File "pswebhost.db" -Query $query
    
    if ($confirmation) {
        $page = Get-SurveyPage -pageName 'RegistrationComplete'
        $html = "<h2>$($page.title)</h2><p>$($page.message)</p>"
        $jsonResponse = New-JsonResponse -status 'success' -html $html
        context_reponse -Response $Response -String $jsonResponse -ContentType "application/json"
    } else {
        $page = Get-SurveyPage -pageName 'ConfirmEmail'
        $html = New-HtmlForm -page $page
        $html = $html.Replace('{email}', $email)
        $html = "<p><i>(Not confirmed yet. Please check your email or wait a moment.)</i></p>" + $html
        $jsonResponse = New-JsonResponse -status 'continue' -html $html
        context_reponse -Response $Response -String $jsonResponse -ContentType "application/json"
    }
    return
}