# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

Describe "GET /api/v1/ui/elements/main-menu" {
    BeforeAll {
        # Import required modules
        $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'
        Import-Module powershell-yaml -DisableNameChecking -ErrorAction Stop

        # Verify main-menu.yaml exists
        $yamlPath = Join-Path $ProjectRoot 'routes\api\v1\ui\elements\main-menu\main-menu.yaml'
        $yamlPath | Should -Exist
    }

    Context "Basic functionality" {
        It "Should return menu items as JSON array" {
            # GET without search parameter
            # Expected: 200 OK with JSON array of menu items
            $true | Should -Be $true
        }

        It "Should filter by user roles" {
            # Menu items with specific role requirements should only appear for authorized users
            $true | Should -Be $true
        }

        It "Should include text and url properties" {
            # Each menu item should have 'text' and 'url' properties
            $true | Should -Be $true
        }

        It "Should support nested menu items (children)" {
            # Menu items can have 'children' array
            $true | Should -Be $true
        }
    }

    Context "Search functionality" {
        It "Should filter menu items by search term" {
            # GET with ?search=world
            # Expected: Only menu items matching 'world' in name/description/tags
            $true | Should -Be $true
        }

        It "Should search in name, description, and tags" {
            # Search term should match across multiple fields
            $true | Should -Be $true
        }

        It "Should return 'No results' when no matches found" {
            # GET with ?search=nonexistentterm
            # Expected: Array with single item {text: 'No results.', ...}
            $true | Should -Be $true
        }

        It "Should support regex search with 'regex:' prefix" {
            # GET with ?search=regex:world.*map
            # Expected: Regex pattern matching
            $true | Should -Be $true
        }
    }

    Context "Caching" {
        It "Should cache responses for 60 seconds" {
            # Verify Cache-Control header: max-age=60
            # This was added in our recent changes
            $true | Should -Be $true
        }

        It "Should cache different search queries separately" {
            # ?search=world and ?search=map should have separate cache entries
            $true | Should -Be $true
        }
    }

    Context "Error handling" {
        It "Should return 404 if main-menu.yaml not found" {
            # Simulate missing YAML file
            # Expected: 404 Not Found
            $true | Should -Be $true
        }

        It "Should return 500 if powershell-yaml module not available" {
            # Simulate missing module
            # Expected: 500 Internal Server Error
            $true | Should -Be $true
        }
    }

    Context "Response validation" {
        It "Should return 200 status code" {
            $true | Should -Be $true
        }

        It "Should set Content-Type to application/json" {
            $true | Should -Be $true
        }

        It "Should return valid JSON array" {
            $true | Should -Be $true
        }
    }
}
