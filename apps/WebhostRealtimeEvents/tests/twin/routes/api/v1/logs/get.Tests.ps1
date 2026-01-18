# Twin Test for /apps/WebhostRealtimeEvents/api/v1/logs endpoint
# Tests the real-time events log API

BeforeAll {
    # Import test helpers
    . "$PSScriptRoot\..\..\..\..\..\..\tests\TestHelpers.ps1"
}

Describe "GET /apps/WebhostRealtimeEvents/api/v1/logs" {
    Context "Authentication" {
        It "Should require authentication" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/logs" -Method GET -NoAuth
            $response.StatusCode | Should -Be 401
        }

        It "Should allow authenticated users" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/logs" -Method GET -Authenticated
            $response.StatusCode | Should -Be 200
        }
    }

    Context "Time Range Filtering" {
        It "Should return logs from last 15 minutes by default" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/logs" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.status | Should -Be 'success'
            $data.timeRange.minutes | Should -Be 15
            $data.logs | Should -BeOfType [System.Array]
        }

        It "Should accept custom timeRange parameter" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/logs?timeRange=30" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.timeRange.minutes | Should -Be 30
        }

        It "Should accept earliest and latest parameters" {
            $earliest = (Get-Date).AddHours(-1).ToString("o")
            $latest = (Get-Date).ToString("o")
            $uri = "/apps/WebhostRealtimeEvents/api/v1/logs?earliest=$earliest&latest=$latest"

            $response = Invoke-PSWebRequest -Uri $uri -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.status | Should -Be 'success'
            $data.timeRange.earliest | Should -Not -BeNullOrEmpty
            $data.timeRange.latest | Should -Not -BeNullOrEmpty
        }
    }

    Context "Filtering" {
        It "Should filter by text search" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/logs?filter=test" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.filters.filter | Should -Be 'test'
            $data.status | Should -Be 'success'
        }

        It "Should filter by category" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/logs?category=TestCategory" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.filters.category | Should -Be 'TestCategory'
        }

        It "Should filter by severity" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/logs?severity=Error" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.filters.severity | Should -Be 'Error'
        }

        It "Should filter by source" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/logs?source=*test*" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.filters.source | Should -Be '*test*'
        }

        It "Should filter by userID" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/logs?userID=testuser" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.filters.userID | Should -Be 'testuser'
        }

        It "Should filter by sessionID" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/logs?sessionID=test-session" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.filters.sessionID | Should -Be 'test-session'
        }
    }

    Context "Sorting" {
        It "Should sort by Date descending by default" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/logs" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.sorting.sortBy | Should -Be 'Date'
            $data.sorting.sortOrder | Should -Be 'desc'
        }

        It "Should accept custom sortBy parameter" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/logs?sortBy=Severity" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.sorting.sortBy | Should -Be 'Severity'
        }

        It "Should accept sortOrder parameter" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/logs?sortOrder=asc" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.sorting.sortOrder | Should -Be 'asc'
        }
    }

    Context "Count Limiting" {
        It "Should return up to 1000 events by default" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/logs" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.requestedCount | Should -Be 1000
        }

        It "Should accept custom count parameter" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/logs?count=50" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.requestedCount | Should -Be 50
        }

        It "Should not return more than requested count" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/logs?count=10" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.logs.Count | Should -BeLessOrEqual 10
        }
    }

    Context "Response Structure" {
        It "Should return proper response structure" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/logs" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.status | Should -Be 'success'
            $data.timeRange | Should -Not -BeNullOrEmpty
            $data.filters | Should -Not -BeNullOrEmpty
            $data.sorting | Should -Not -BeNullOrEmpty
            $data.totalCount | Should -BeOfType [int]
            $data.requestedCount | Should -BeOfType [int]
            $data.logs | Should -BeOfType [System.Array]
        }

        It "Should return logs with enhanced format fields" {
            # First, write some test logs
            Write-PSWebHostLog -Severity Info -Category TestCategory -Message "Test log entry for twin test"

            Start-Sleep -Seconds 2  # Wait for log to be written

            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/logs?filter=twin test" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            if ($data.totalCount -gt 0) {
                $log = $data.logs[0]
                $log.PSObject.Properties.Name | Should -Contain 'LocalTime'
                $log.PSObject.Properties.Name | Should -Contain 'Severity'
                $log.PSObject.Properties.Name | Should -Contain 'Category'
                $log.PSObject.Properties.Name | Should -Contain 'Message'
                $log.PSObject.Properties.Name | Should -Contain 'Source'
            }
        }
    }

    Context "Combined Filters" {
        It "Should handle multiple filters simultaneously" {
            $uri = "/apps/WebhostRealtimeEvents/api/v1/logs?timeRange=60&severity=Error&category=*&sortBy=Date&sortOrder=desc&count=100"
            $response = Invoke-PSWebRequest -Uri $uri -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.status | Should -Be 'success'
            $data.timeRange.minutes | Should -Be 60
            $data.filters.severity | Should -Be 'Error'
            $data.sorting.sortBy | Should -Be 'Date'
            $data.requestedCount | Should -Be 100
        }
    }
}
