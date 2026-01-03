param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Helper function to create a JSON response
function New-JsonResponse($status, $message) {
    return @{ status = $status; Message = $message } | ConvertTo-Json
}

# Get user ID from session
if (-not $sessiondata -or -not $sessiondata.UserID) {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'User not authenticated'
    context_reponse -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
    return
}

$userID = $sessiondata.UserID

# Read request body
$reader = New-Object System.IO.StreamReader($Request.InputStream)
$body = $reader.ReadToEnd()
$reader.Close()

try {
    $data = $body | ConvertFrom-Json
}
catch {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'Invalid JSON in request body'
    context_reponse -Response $Response -StatusCode 400 -String $jsonResponse -ContentType "application/json"
    return
}

# Validate action
if (-not $data.action) {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'Missing required parameter: action'
    context_reponse -Response $Response -StatusCode 400 -String $jsonResponse -ContentType "application/json"
    return
}

try {
    switch ($data.action) {
        'createFolder' {
            # Create a new folder
            if (-not $data.name) {
                throw "Missing required parameter: name"
            }

            $getScript = Join-Path $Global:PSWebServer.Project_Root.Path "system\utility\UserData_Folder_Get.ps1"
            $folderPath = $data.path -replace '^/', ''
            $newFolderPath = if ($folderPath) { "$folderPath\$($data.name)" } else { $data.name }

            $result = & $getScript -UserID $userID -Application "file-explorer" -SubFolder $newFolderPath -CreateIfMissing

            $response = @{
                status = 'success'
                message = 'Folder created successfully'
                path = $newFolderPath
            }
            $jsonResponse = $response | ConvertTo-Json -Compress
            context_reponse -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
        }

        'uploadFile' {
            # Upload/save a file
            if (-not $data.name -or -not $data.content) {
                throw "Missing required parameters: name, content"
            }

            $saveScript = Join-Path $Global:PSWebServer.Project_Root.Path "system\utility\UserData_Folder_Save.ps1"
            $filePath = $data.path -replace '^/', ''

            # Decode base64 content if present
            if ($data.encoding -eq 'base64') {
                $bytes = [System.Convert]::FromBase64String($data.content)
                $result = & $saveScript -UserID $userID -Application "file-explorer" -SubFolder $filePath -Name $data.name -Bytes $bytes -Force
            }
            else {
                $result = & $saveScript -UserID $userID -Application "file-explorer" -SubFolder $filePath -Name $data.name -Content $data.content -Force
            }

            $response = @{
                status = 'success'
                message = 'File uploaded successfully'
                file = $result.Name
            }
            $jsonResponse = $response | ConvertTo-Json -Compress
            context_reponse -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
        }

        'rename' {
            # Rename a file or folder
            if (-not $data.oldName -or -not $data.newName) {
                throw "Missing required parameters: oldName, newName"
            }

            $renameScript = Join-Path $Global:PSWebServer.Project_Root.Path "system\utility\UserData_Folder_Rename.ps1"
            $folderPath = $data.path -replace '^/', ''

            $params = @{
                UserID = $userID
                Application = "file-explorer"
                OldName = $data.oldName
                NewName = $data.newName
            }
            if ($folderPath) { $params.SubFolder = $folderPath }
            if ($data.isFolder) { $params.IsFolder = $true }

            $result = & $renameScript @params -Force

            $response = @{
                status = 'success'
                message = 'Item renamed successfully'
                newName = $result.Name
            }
            $jsonResponse = $response | ConvertTo-Json -Compress
            context_reponse -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
        }

        'delete' {
            # Delete a file or folder
            if (-not $data.name) {
                throw "Missing required parameter: name"
            }

            $removeScript = Join-Path $Global:PSWebServer.Project_Root.Path "system\utility\UserData_Folder_Remove.ps1"
            $folderPath = $data.path -replace '^/', ''

            $params = @{
                UserID = $userID
                Application = "file-explorer"
                Name = $data.name
                Force = $true
            }
            if ($folderPath) { $params.SubFolder = $folderPath }
            if ($data.isFolder) { $params.RemoveFolder = $true }

            $result = & $removeScript @params

            $response = @{
                status = 'success'
                message = 'Item deleted successfully'
                removed = $result
            }
            $jsonResponse = $response | ConvertTo-Json -Compress
            context_reponse -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
        }

        default {
            throw "Unknown action: $($data.action)"
        }
    }
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Error in file-explorer POST: $($_.Exception.Message)" -Data @{ UserID = $userID; Action = $data.action }
    $jsonResponse = New-JsonResponse -status 'fail' -message "An error occurred: $($_.Exception.Message)"
    context_reponse -Response $Response -StatusCode 500 -String $jsonResponse -ContentType "application/json"
}
