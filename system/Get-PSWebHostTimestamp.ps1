# Get-PSWebHostTimestamp
# Returns a standardized timestamp string for PSWebHost
# Format: ISO 8601 with timezone offset, safe for filenames
# Example: 2025-12-31T012345_1234567-0800
#
# This format includes:
# - Full date and time
# - Timezone offset (handles daylight savings changes)
# - Safe for use in filenames (no colons or periods)

function Get-PSWebHostTimestamp {
    [CmdletBinding()]
    param(
        [Parameter()]
        [datetime]$DateTime = (Get-Date),

        [Parameter()]
        [switch]$ForFilename
    )

    # Get ISO 8601 format with timezone: 2025-12-31T01:23:45.1234567-08:00
    $timestamp = $DateTime.ToString('o')

    if ($ForFilename) {
        # Make it filename-safe by removing colons and replacing periods with underscores
        # Result: 2025-12-31T012345_1234567-0800
        $timestamp = $timestamp.Replace(':', '').Replace('.', '_')
    }

    return $timestamp
}
