# Twin Test for /apps/WebhostRealtimeEvents/api/v1/status endpoint
# Tests the app status endpoint

BeforeAll {
    # Import test helpers
    . "$PSScriptRoot\..\..\..\..\..\..\tests\TestHelpers.ps1"
}

Describe "GET /apps/WebhostRealtimeEvents/api/v1/status" {
    Context "Authentication" {
        It "Should require authentication" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/status" -Method GET -NoAuth
            $response.StatusCode | Should -Be 401
        }

        It "Should allow authenticated users" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/status" -Method GET -Authenticated
            $response.StatusCode | Should -Be 200
        }
    }

    Context "Response Structure" {
        It "Should return proper status structure" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/status" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.status | Should -Be 'healthy'
            $data.appName | Should -Be 'WebHost Realtime Events'
            $data.appVersion | Should -Not -BeNullOrEmpty
            $data.timestamp | Should -Not -BeNullOrEmpty
        }

        It "Should return features list" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/status" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.features | Should -Not -BeNullOrEmpty
            $data.features.timeRangeFiltering | Should -Be $true
            $data.features.textSearch | Should -Be $true
            $data.features.sortable | Should -Be $true
            $data.features.exportCSV | Should -Be $true
        }

        It "Should return log file information" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/status" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.logFile | Should -Not -BeNullOrEmpty
            $data.logFile.path | Should -Not -BeNullOrEmpty
            $data.logFile.PSObject.Properties.Name | Should -Contain 'exists'
            $data.logFile.PSObject.Properties.Name | Should -Contain 'sizeBytes'
            $data.logFile.PSObject.Properties.Name | Should -Contain 'sizeMB'
        }

        It "Should return configuration values" {
            $response = Invoke-PSWebRequest -Uri "/apps/WebhostRealtimeEvents/api/v1/status" -Method GET -Authenticated
            $data = $response.Content | ConvertFrom-Json

            $data.defaultTimeRange | Should -Be 15
            $data.maxEvents | Should -BeGreaterThan 0
        }
    }
}
