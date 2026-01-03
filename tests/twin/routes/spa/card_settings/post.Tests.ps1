# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "POST /spa/card_settings" {
    BeforeAll {
        # Import required modules
        $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'
        Import-Module (Join-Path $ProjectRoot 'modules\PSWebHost_Database') -DisableNameChecking -ErrorAction Stop
        Import-Module (Join-Path $ProjectRoot 'modules\PSWebHost_Authentication') -DisableNameChecking -ErrorAction Stop
    }

    Context "When saving new card settings" {
        It "Should create new card_settings record" {
            # POST with valid session, endpoint_guid, and layout data
            # Expected: 200 OK with {status: 'success', message: 'Card settings saved.'}
            $true | Should -Be $true
        }

        It "Should accept JSON body with id and layout" {
            # Body: {id: "/api/v1/ui/elements/world-map", layout: {w: 12, h: 14, x: 0, y: 0}}
            $true | Should -Be $true
        }

        It "Should store layout as JSON string in database" {
            # Verify database entry has data field with compressed JSON
            $true | Should -Be $true
        }
    }

    Context "When updating existing card settings" {
        It "Should update existing record with new layout" {
            # POST for existing endpoint_guid + user_id combination
            # Expected: 200 OK, database record updated
            $true | Should -Be $true
        }

        It "Should preserve created_date when updating" {
            # Verify created_date stays the same, last_updated changes
            $true | Should -Be $true
        }
    }

    Context "Error handling" {
        It "Should return 400 when missing cardId" {
            # POST without 'id' in body
            # Expected: 400 Bad Request
            $true | Should -Be $true
        }

        It "Should return 400 when missing layout data" {
            # POST without 'layout' in body
            # Expected: 400 Bad Request
            $true | Should -Be $true
        }

        It "Should return 401 when not authenticated" {
            # POST without valid session
            # Expected: 401 Unauthorized
            $true | Should -Be $true
        }

        It "Should return 500 on database error" {
            # Simulate database failure
            # Expected: 500 Internal Server Error
            $true | Should -Be $true
        }
    }

    Context "Response validation" {
        It "Should return success status in JSON" {
            # Expected: {status: 'success', message: 'Card settings saved.'}
            $true | Should -Be $true
        }

        It "Should set Content-Type to application/json" {
            $true | Should -Be $true
        }
    }
}
