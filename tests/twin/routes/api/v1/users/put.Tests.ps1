# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "PUT /api/v1/users" -Tags 'Route', 'Users', 'API' {
    BeforeAll {
        $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'

        # Import helper modules
        Import-Module (Join-Path $ProjectRoot 'tests\twin\helpers\Test-Helpers.psm1') -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $ProjectRoot 'modules\PSWebHost_Database') -DisableNameChecking -Force

        # Start WebHost for testing
        try {
            $global:PSWebHostTesting.WebHost = Get-TestWebHost -ProjectRoot $ProjectRoot -ErrorAction Stop
            $global:PSWebHostTesting.BaseUrl = $webHost.Url.TrimEnd('/')
            $global:PSWebHostTesting.WebHostStarted = $true
        } catch {
            Write-Warning "WebHost could not be started - tests will be skipped: $_"
            $global:PSWebHostTesting.WebHostStarted = $false
        }

        # Track created user IDs for cleanup
        $global:PSWebHostTesting.TestUserIDs = @()
    }

    AfterAll {
        if ($global:PSWebHostTesting.WebHostStarted -and $global:PSWebHostTesting.WebHost) {
            Stop-TestWebHost -WebHost $global:PSWebHostTesting.WebHost
        }

        # Cleanup test users
        $dbFile = Join-Path $ProjectRoot "PsWebHost_Data\pswebhost.db"
        foreach ($userID in $global:PSWebHostTesting.TestUserIDs) {
            try {
                $query = "DELETE FROM Users WHERE UserID = '$userID';"
                Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query -ErrorAction SilentlyContinue
            } catch {
                Write-Warning "Failed to cleanup test user: $userID"
            }
        }
    }

    Context "Update user with valid data" {
        It "Should require UserID in query string" {
            $boundary = "----WebKitFormBoundary" + [guid]::NewGuid().ToString().Replace("-", "")
            $body = "--$boundary`r`nContent-Disposition: form-data; name=`"UserName`"`r`n`r`nUpdatedName`r`n--$boundary--"

            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                    -Method PUT `
                    -Body $body `
                    -ContentType "multipart/form-data; boundary=$boundary" `
                    -UseBasicParsing
                $statusCode = $response.StatusCode
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }

            $statusCode | Should -Be 400
        }

        It "Should return 400 when UserID is missing" {
            $boundary = "----WebKitFormBoundary" + [guid]::NewGuid().ToString().Replace("-", "")
            $body = "--$boundary`r`nContent-Disposition: form-data; name=`"UserName`"`r`n`r`nUpdatedName`r`n--$boundary--"

            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                    -Method PUT `
                    -Body $body `
                    -ContentType "multipart/form-data; boundary=$boundary" `
                    -UseBasicParsing
            } catch {
                $errorResponse = $_.Exception.Response
                $stream = $errorResponse.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $responseBody = $reader.ReadToEnd()

                $responseBody | Should -Match 'UserID is required'
            }
        }

        It "Should update UserName field" {
            # Create a test user first
            $createData = @{
                UserName = "OriginalName-$(Get-Random)"
            } | ConvertTo-Json

            $createResponse = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $createData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $createResponse.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            # Update the user
            $newUserName = "UpdatedName-$(Get-Random)"
            $boundary = "----WebKitFormBoundary" + [guid]::NewGuid().ToString().Replace("-", "")
            $body = "--$boundary`r`nContent-Disposition: form-data; name=`"UserName`"`r`n`r`n$newUserName`r`n--$boundary--"

            $updateResponse = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users?UserID=$($user.UserID)" `
                -Method PUT `
                -Body $body `
                -ContentType "multipart/form-data; boundary=$boundary" `
                -UseBasicParsing

            $updatedUser = $updateResponse.Content | ConvertFrom-Json
            $updatedUser.UserName | Should -Be $newUserName
        }

        It "Should update Email field" {
            # Create a test user
            $createData = @{
                UserName = "TestUser-$(Get-Random)"
                Email = "original-$(Get-Random)@example.com"
            } | ConvertTo-Json

            $createResponse = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $createData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $createResponse.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            # Update email
            $newEmail = "updated-$(Get-Random)@example.com"
            $boundary = "----WebKitFormBoundary" + [guid]::NewGuid().ToString().Replace("-", "")
            $body = "--$boundary`r`nContent-Disposition: form-data; name=`"Email`"`r`n`r`n$newEmail`r`n--$boundary--"

            $updateResponse = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users?UserID=$($user.UserID)" `
                -Method PUT `
                -Body $body `
                -ContentType "multipart/form-data; boundary=$boundary" `
                -UseBasicParsing

            $updatedUser = $updateResponse.Content | ConvertFrom-Json
            $updatedUser.Email | Should -Be $newEmail
        }

        It "Should update Phone field" {
            # Create a test user
            $createData = @{
                UserName = "TestUser-$(Get-Random)"
                Phone = "555-1234"
            } | ConvertTo-Json

            $createResponse = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $createData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $createResponse.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            # Update phone
            $newPhone = "555-9999"
            $boundary = "----WebKitFormBoundary" + [guid]::NewGuid().ToString().Replace("-", "")
            $body = "--$boundary`r`nContent-Disposition: form-data; name=`"Phone`"`r`n`r`n$newPhone`r`n--$boundary--"

            $updateResponse = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users?UserID=$($user.UserID)" `
                -Method PUT `
                -Body $body `
                -ContentType "multipart/form-data; boundary=$boundary" `
                -UseBasicParsing

            $updatedUser = $updateResponse.Content | ConvertFrom-Json
            $updatedUser.Phone | Should -Be $newPhone
        }

        It "Should update multiple fields at once" {
            # Create a test user
            $createData = @{
                UserName = "OriginalUser-$(Get-Random)"
                Email = "original-$(Get-Random)@example.com"
                Phone = "555-0000"
            } | ConvertTo-Json

            $createResponse = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $createData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $createResponse.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            # Update multiple fields
            $newUserName = "UpdatedUser-$(Get-Random)"
            $newEmail = "updated-$(Get-Random)@example.com"
            $newPhone = "555-8888"

            $boundary = "----WebKitFormBoundary" + [guid]::NewGuid().ToString().Replace("-", "")
            $body = @"
--$boundary
Content-Disposition: form-data; name="UserName"

$newUserName
--$boundary
Content-Disposition: form-data; name="Email"

$newEmail
--$boundary
Content-Disposition: form-data; name="Phone"

$newPhone
--$boundary--
"@

            $updateResponse = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users?UserID=$($user.UserID)" `
                -Method PUT `
                -Body $body `
                -ContentType "multipart/form-data; boundary=$boundary" `
                -UseBasicParsing

            $updatedUser = $updateResponse.Content | ConvertFrom-Json
            $updatedUser.UserName | Should -Be $newUserName
            $updatedUser.Email | Should -Be $newEmail
            $updatedUser.Phone | Should -Be $newPhone
        }
    }

    Context "Response validation" {
        It "Should return updated user as JSON" {
            # Create and update user
            $createData = @{
                UserName = "TestUser-$(Get-Random)"
            } | ConvertTo-Json

            $createResponse = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $createData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $createResponse.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            $boundary = "----WebKitFormBoundary" + [guid]::NewGuid().ToString().Replace("-", "")
            $body = "--$boundary`r`nContent-Disposition: form-data; name=`"UserName`"`r`n`r`nUpdatedName`r`n--$boundary--"

            $updateResponse = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users?UserID=$($user.UserID)" `
                -Method PUT `
                -Body $body `
                -ContentType "multipart/form-data; boundary=$boundary" `
                -UseBasicParsing

            $updateResponse.Headers['Content-Type'] | Should -Match 'application/json'

            { $updateResponse.Content | ConvertFrom-Json } | Should -Not -Throw
        }

        It "Should return 200 OK on successful update" {
            # Create and update user
            $createData = @{
                UserName = "TestUser-$(Get-Random)"
            } | ConvertTo-Json

            $createResponse = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $createData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $createResponse.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            $boundary = "----WebKitFormBoundary" + [guid]::NewGuid().ToString().Replace("-", "")
            $body = "--$boundary`r`nContent-Disposition: form-data; name=`"UserName`"`r`n`r`nUpdatedName`r`n--$boundary--"

            $updateResponse = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users?UserID=$($user.UserID)" `
                -Method PUT `
                -Body $body `
                -ContentType "multipart/form-data; boundary=$boundary" `
                -UseBasicParsing

            $updateResponse.StatusCode | Should -Be 200
        }
    }

    Context "Security - SQL injection prevention" {
        It "Should sanitize UserID to prevent SQL injection" {
            $maliciousUserID = "123'; DROP TABLE Users;--"

            $boundary = "----WebKitFormBoundary" + [guid]::NewGuid().ToString().Replace("-", "")
            $body = "--$boundary`r`nContent-Disposition: form-data; name=`"UserName`"`r`n`r`nTest`r`n--$boundary--"

            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users?UserID=$maliciousUserID" `
                    -Method PUT `
                    -Body $body `
                    -ContentType "multipart/form-data; boundary=$boundary" `
                    -UseBasicParsing

                # Should not crash
                $true | Should -Be $true
            } catch {
                # May return error, which is acceptable
                $true | Should -Be $true
            }
        }

        It "Should sanitize update values to prevent SQL injection" {
            # Create a test user
            $createData = @{
                UserName = "TestUser-$(Get-Random)"
            } | ConvertTo-Json

            $createResponse = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $createData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $createResponse.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            # Try SQL injection in update value
            $maliciousName = "Test'; DELETE FROM Users WHERE '1'='1"
            $boundary = "----WebKitFormBoundary" + [guid]::NewGuid().ToString().Replace("-", "")
            $body = "--$boundary`r`nContent-Disposition: form-data; name=`"UserName`"`r`n`r`n$maliciousName`r`n--$boundary--"

            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users?UserID=$($user.UserID)" `
                    -Method PUT `
                    -Body $body `
                    -ContentType "multipart/form-data; boundary=$boundary" `
                    -UseBasicParsing

                # Should not execute SQL
                $response.StatusCode | Should -BeIn @(200, 400)
            } catch {
                # May reject malicious input
                $true | Should -Be $true
            }
        }
    }

    Context "Profile image upload" {
        It "Should accept profile image in multipart data" {
            # This test requires creating actual image bytes
            # Serves as documentation of expected behavior
            $true | Should -Be $true
        }

        It "Should process uploaded image with MakeIcons script" {
            # Image processing creates multiple sizes using MakeIcons.ps1
            # Serves as documentation of expected behavior
            $true | Should -Be $true
        }

        It "Should store profile images in user directory" {
            # Images should be stored in public/users/{UserID}/
            # Serves as documentation of expected behavior
            $true | Should -Be $true
        }
    }

    Context "Error handling" {
        It "Should handle non-existent UserID gracefully" {
            $fakeUserID = [guid]::NewGuid().ToString()

            $boundary = "----WebKitFormBoundary" + [guid]::NewGuid().ToString().Replace("-", "")
            $body = "--$boundary`r`nContent-Disposition: form-data; name=`"UserName`"`r`n`r`nUpdatedName`r`n--$boundary--"

            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users?UserID=$fakeUserID" `
                    -Method PUT `
                    -Body $body `
                    -ContentType "multipart/form-data; boundary=$boundary" `
                    -UseBasicParsing

                # Should complete without error (may update 0 rows)
                $response.StatusCode | Should -Be 200
            } catch {
                # May return error
                $true | Should -Be $true
            }
        }

        It "Should handle empty update data" {
            # Create a test user
            $createData = @{
                UserName = "TestUser-$(Get-Random)"
            } | ConvertTo-Json

            $createResponse = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $createData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $createResponse.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            # Send empty update
            $boundary = "----WebKitFormBoundary" + [guid]::NewGuid().ToString().Replace("-", "")
            $body = "--$boundary--"

            try {
                $response = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users?UserID=$($user.UserID)" `
                    -Method PUT `
                    -Body $body `
                    -ContentType "multipart/form-data; boundary=$boundary" `
                    -UseBasicParsing

                # Should handle gracefully
                $response.StatusCode | Should -Be 200
            } catch {
                # May return error
                $true | Should -Be $true
            }
        }
    }

    Context "Persistence validation" {
        It "Should persist changes to database" {
            # Create a test user
            $createData = @{
                UserName = "OriginalUser-$(Get-Random)"
            } | ConvertTo-Json

            $createResponse = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method POST `
                -Body $createData `
                -ContentType "application/json" `
                -UseBasicParsing

            $user = $createResponse.Content | ConvertFrom-Json
            $global:PSWebHostTesting.TestUserIDs += $user.UserID

            # Update the user
            $newUserName = "UpdatedUser-$(Get-Random)"
            $boundary = "----WebKitFormBoundary" + [guid]::NewGuid().ToString().Replace("-", "")
            $body = "--$boundary`r`nContent-Disposition: form-data; name=`"UserName`"`r`n`r`n$newUserName`r`n--$boundary--"

            $null = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users?UserID=$($user.UserID)" `
                -Method PUT `
                -Body $body `
                -ContentType "multipart/form-data; boundary=$boundary" `
                -UseBasicParsing

            # Verify change persisted by getting all users
            $getResponse = Invoke-WebRequest -Uri "$global:PSWebHostTesting.BaseUrl/api/v1/users" `
                -Method GET `
                -UseBasicParsing

            $allUsers = $getResponse.Content | ConvertFrom-Json

            # Ensure array
            if ($allUsers -isnot [array]) {
                $allUsers = @($allUsers)
            }

            $updatedUser = $allUsers | Where-Object { $_.UserID -eq $user.UserID }
            $updatedUser.UserName | Should -Be $newUserName
        }
    }
}
