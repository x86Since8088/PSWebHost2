function Get-AuthenticationMethod {
    [cmdletbinding()]
    param()

    if ($PSBoundParameters.Verbose.IsPresent) {
        $caller = (Get-PSCallStack)[1].FunctionName
        Write-Verbose "Function 'Get-AuthenticationMethod' called from '$caller'."
    }

    # This function would typically query a database or configuration file
    # to get the available authentication methods.
    # For now, we'll return a static list.
    return @("Password", "OTP_Email", "OTP_SMS")
}

function Get-AuthenticationMethodForm {
    [cmdletbinding()]
    param(
        [string]$Name
    )

    if ($PSBoundParameters.Verbose.IsPresent) {
        $caller = (Get-PSCallStack)[1].FunctionName
        Write-Verbose "Function 'Get-AuthenticationMethodForm' called from '$caller'."
    }

    $myTag = '[Get-AuthenticationMethodForm]'
    if (-not $Name) { Write-Error "$myTag The -Name parameter is required."; return }

    # This function would return the form fields required for a specific
    # authentication method.
    $form = @{}
    switch ($Name) {
        "Password" {
            $form = @{
                "Username" = @{
                    "type" = "text"
                    "required" = $true
                }
                "Password" = @{
                    "type" = "password"
                    "required" = $true
                }
            }
        }
        "OTP_Email" {
            $form = @{
                "Email" = @{
                    "type" = "email"
                    "required" = $true
                }
            }
        }
        "OTP_SMS" {
            $form = @{
                "PhoneNumber" = @{
                    "type" = "tel"
                    "required" = $true
                }
            }
        }
    }
    return $form
}

function Get-PSWebHostUser {
    [cmdletbinding()]
    param(
        [parameter(ParameterSetName='Email')]
        [Parameter(Mandatory=$false)]
        [string]$Email,
        [parameter(ParameterSetName='UserID')]
        [Parameter(Mandatory=$false)]
        [string]$UserID,
        [parameter(ParameterSetName='Listall')]
        [switch]$Listall
    )

    if ($PSBoundParameters.Verbose.IsPresent) {
        $caller = (Get-PSCallStack)[1].FunctionName
        Write-Verbose "Function 'Get-PSWebHostUser' called from '$caller'."
    }

    $MyTag = "[Get-PSWebHostUser]"
    if ($PSBoundParameters.ContainsKey('Email')) {
        $safeEmail = Sanitize-SqlQueryString -String $Email
        $query = "SELECT * FROM Users WHERE Email = '$safeEmail';"
    }
    elseif ($PSBoundParameters.ContainsKey('UserID')) {
        $safeUserID = Sanitize-SqlQueryString -String $UserID
        $query = "SELECT * FROM Users WHERE UserID = '$safeUserID';"
    }
    elseif ($Listall) {
        $query = "SELECT * FROM Users;"
    }
    else {
        Write-Error "$MyTag you must provide -Email, -UserID or -Listall"
        return
    }
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: Get-PSWebSQLiteData -File $dbFile -Query `n`t$query"
    $user = Get-PSWebSQLiteData -File $dbFile -Query $query
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Retrieved user data: $(($user | Out-String).trim('\s') -split '\n' -join "`n`t")"
    return $user
}

function Get-PSWebHostUsers {
    [cmdletbinding()]
    param()

    if ($PSBoundParameters.Verbose.IsPresent) {
        $caller = (Get-PSCallStack)[1].FunctionName
        Write-Verbose "Function 'Get-PSWebHostUsers' called from '$caller'."
    }

    $MyTag = "[Get-PSWebHostUsers]"
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $query = "SELECT Email FROM Users;"
    Write-Verbose "$MyTag Executing: Get-PSWebSQLiteData -File $dbFile -Query `n`t$query"
    $users = Get-PSWebSQLiteData -File $dbFile -Query $query
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Retrieved users: $(($users | Out-String).trim('\s') -split '\n' -join "`n`t")"
    if ($users) {
        return $users.Email
    } else {
        return @()
    }
}

function Get-UserAuthenticationMethods {
    [cmdletbinding()]
    param(
        [string]$Email
    )

    if ($PSBoundParameters.Verbose.IsPresent) {
        $caller = (Get-PSCallStack)[1].FunctionName
        Write-Verbose "Function 'Get-UserAuthenticationMethods' called from '$caller'."
    }

    $MyTag = "[Get-UserAuthenticationMethods]"
    if (-not $Email) { Write-Error "The -Email parameter is required."; return }
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: Get-PSWebHostUser -Email '$Email'"
    $user = Get-PSWebHostUser -Email $Email
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Retrieved user: $(($user | Out-String).trim('\s') -split '\n' -join "`n`t")"
    if (-not $user) {
        return @()
    }

    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $safeUserID = Sanitize-SqlQueryString -String $user.UserID
    $query = "SELECT provider FROM auth_user_provider WHERE UserID = '$safeUserID';"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: Get-PSWebSQLiteData -File $dbFile -Query `n`t$query"
    $authMethods = Get-PSWebSQLiteData -File $dbFile -Query $query
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Retrieved authentication methods: $(($authMethods | Out-String).trim('\s') -split '\n' -join "`n`t")"
    if ($authMethods) {
        return $authMethods.provider
    } else {
        return @()
    }
}

function Get-PSWebHostRole {
    [cmdletbinding()]
    param(
        [parameter(ParameterSetName='ByUser')]
        [string]$UserID,

        [parameter(ParameterSetName='ListAll')]
        [switch]$ListAll
    )

    if ($PSBoundParameters.Verbose.IsPresent) {
        $caller = (Get-PSCallStack)[1].FunctionName
        Write-Verbose "Function 'Get-PSWebHostRole' called from '$caller'."
    }

    $MyTag = "[Get-PSWebHostRole]"
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

    if ($ListAll) {
        $query = "SELECT DISTINCT RoleName FROM PSWeb_Roles;"
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: Get-PSWebSQLiteData -File $dbFile -Query `n`t$query"
        $roles = Get-PSWebSQLiteData -File $dbFile -Query $query
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Retrieved roles: $(($roles | Out-String).trim('\s') -split '\n' -join "`n`t")"
        if ($roles) {
            return $roles.RoleName
        } else {
            return @()
        }
    }
    
    if (-not $UserID) { Write-Error "The -UserID parameter is required for this parameter set."; return }

    $safeUserID = Sanitize-SqlQueryString -String $UserID

    # Get roles assigned directly to the user
    $queryDirectRoles = "SELECT RoleName FROM PSWeb_Roles WHERE PrincipalID = '$safeUserID';"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: Get-PSWebSQLiteData -File $dbFile -Query `n`t$queryDirectRoles"
    $directRoles = Get-PSWebSQLiteData -File $dbFile -Query $queryDirectRoles
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Retrieved direct roles: $(($directRoles | Out-String).trim('\s') -split '\n' -join "`n`t")"

    # Get roles assigned to groups the user is in
    $queryGroupRoles = "SELECT r.RoleName FROM PSWeb_Roles r JOIN User_Groups_Map ugm ON r.PrincipalID = ugm.GroupID WHERE ugm.UserID = '$safeUserID';"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: Get-PSWebSQLiteData -File $dbFile -Query `n`t$queryGroupRoles"
    $groupRoles = Get-PSWebSQLiteData -File $dbFile -Query $queryGroupRoles
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Retrieved group roles: $(($groupRoles | Out-String).trim('\s') -split '\n' -join "`n`t")"

    $allRoles = @()
    if ($directRoles) {
        $allRoles += $directRoles.RoleName
    }
    if ($groupRoles) {
        $allRoles += $groupRoles.RoleName
    }

    return $allRoles | Select-Object -Unique
}

function Invoke-AuthenticationMethod {
    [cmdletbinding()]
    param(
        [string]$Name,
        [hashtable]$FormData
    )

    if ($PSBoundParameters.Verbose.IsPresent) {
        $caller = (Get-PSCallStack)[1].FunctionName
        Write-Verbose "Function 'Invoke-AuthenticationMethod' called from '$caller'."
    }

    $MyTag = "[Invoke-AuthenticationMethod]"
    if (-not $Name) { Write-Error "The -Name parameter is required."; return }
    if (-not $FormData) { Write-Error "The -FormData parameter is required."; return }

    switch ($Name) {
        "Password" {
            # --- Password Authentication Logic ---
            $email = $FormData.Username
            $password = $FormData.Password

            # 1. Get user from database
            $user = Get-PSWebHostUser -Email $email
            if (-not $user) {
                Write-Warning "Authentication failed: User '$email' not found."
                return $false
            }

            # 2. Get stored password hash for the user
            $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
            $safeUserID = Sanitize-SqlQueryString -String $user.UserID
            # The password hash is stored in the 'data' column as JSON
            $query = "SELECT data FROM auth_user_provider WHERE UserID = '$safeUserID' AND provider = 'Password';"
            Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: Get-PSWebSQLiteData -File $dbFile -Query `n`t$query"
            $authMethod = Get-PSWebSQLiteData -File $dbFile -Query $query
            Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Retrieved authentication method data: $(($authMethod | Out-String).trim('\s') -split '\n' -join "`n`t")"
            if (-not $authMethod) {
                Write-Warning "Authentication failed: No password set for user '$email'."
                return $false
            }
            # Parse the JSON to get the password hash and salt
            $authData = $authMethod.data | ConvertFrom-Json
            $storedPasswordHash = $authData.Password
            $storedSalt = $authData.Salt

            if (-not $storedSalt) {
                Write-Warning "Authentication failed: No salt found for user '$email'."
                return $false
            }

            # 3. Hash the provided password with the user's salt
            $saltBytes = [System.Convert]::FromBase64String($storedSalt)
            $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($password, $saltBytes, 10000)
            $providedPasswordHashBytes = $pbkdf2.GetBytes(20)
            $providedPasswordHash = [System.Convert]::ToBase64String($providedPasswordHashBytes)

            # 4. Compare the hashes
            Write-Verbose "$MyTag Comparing hashes - Provided: $providedPasswordHash, Stored: $storedPasswordHash"
            if ($providedPasswordHash -eq $storedPasswordHash) {
                Write-Verbose "Password authentication successful for user '$email'."
                return $true
            } else {
                Write-Warning "Password authentication failed for user '$email'. Hash mismatch."
                return $false
            }
        }
        "Windows" {
            # --- Windows Authentication Logic ---
            $username = $FormData.Username
            $password = $FormData.Password

            $scriptPath = Join-Path $Global:PSWebServer.Project_Root.Path "system/auth/Test-PSWebWindowsAuth.ps1"
            if (-not (Test-Path $scriptPath)) {
                Write-Error "Test-PSWebWindowsAuth.ps1 not found at $scriptPath. Cannot perform Windows authentication."
                return $false
            }

            # Execute the external script
            Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: $scriptPath -Username $username -Password `$password -ContextType "LocalMachine""
            $isAuthenticated = & $scriptPath -Username $username -Password $password -ContextType "LocalMachine" # Assuming LocalMachine for now
            Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Windows authentication result: $isAuthenticated"

            if ($isAuthenticated) {
                Write-Verbose "Windows authentication successful for user '$username'."
                return $true
            } else {
                Write-Warning "Windows authentication failed for user '$username'."
                return $false
            }
        }
        default {
            Write-Error "Authentication method '$Name' is not supported yet."
            return $false
        }
    }
}

function Test-IsValidEmailAddress {
    [cmdletbinding()]
    param(
        [string]$Email,
        [string]$Regex = '^[a-zA-Z0-9._+-]+@[a-zA-Z0-9\.-]+',
        [string]$AddCustomRegex
    )

    if ($PSBoundParameters.Verbose.IsPresent) {
        $caller = (Get-PSCallStack)[1].FunctionName
        Write-Verbose "Function 'Test-IsValidEmailAddress' called from '$caller'."
    }

    $MyTag = "[Test-IsValidEmailAddress]"
    # Basic email validation regex
    if ($AddCustomRegex) {$Regex+="|$AddCustomRegex"}
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing high-risk unicode check for email: $Email"
    $InvalidCharacters = Test-StringForHighRiskUnicode -String $Email
    if ($InvalidCharacters.IsValid -eq $false) {
        Write-PSWebHostLog -Severity Warning -Category Email_Conatins_High_Risk_Unicode "$MyTag Email_Conatins_High_Risk_Unicode: $InvalidCharacters" -WriteHost:$PSBoundParameters.Verbose -ForegroundColor yellow
        return $InvalidCharacters
    }
    if (-not ($Email -match $Regex)) {
        $return = @{ isValid = $false; Message = "Email address format is invalid." }
        Write-PSWebHostLog -Severity Warning -Category Email_Format_Invalid -message "$MyTag Invalid Characters: $($return|ConvertTo-Json -Compress)" -WriteHost:$PSBoundParameters.Verbose -ForegroundColor yellow
        return $return
    }
    return @{ isValid = $true; Message = "Email address is valid." }
}

function Test-StringForHighRiskUnicode {
    [cmdletbinding()]
    param(
        [string]$String
    )

    if ($PSBoundParameters.Verbose.IsPresent) {
        $caller = (Get-PSCallStack)[1].FunctionName
        Write-Verbose "Function 'Test-StringForHighRiskUnicode' called from '$caller'."
    }

    $MyTag = "[Test-StringForHighRiskUnicode]"
    # Define a hashtable of forbidden character codes to enhance security.
    # This list includes non-printable control characters, ambiguous symbols, and characters
    # that can be used to obscure or manipulate text in potentially malicious ways.
    [hashtable]$Forbidden = @{
        # C0 Control Characters (Risk: 8-10 - High/Critical)
        0x00 = @{ Abbreviation = 'NUL'; Risk = 10; Description = 'Null character, can cause premature string termination and buffer overflows.' }
        0x01 = @{ Abbreviation = 'SOH'; Risk = 8; Description = 'Start of Heading, a control character.' }
        0x02 = @{ Abbreviation = 'STX'; Risk = 8; Description = 'Start of Text, a control character.' }
        0x03 = @{ Abbreviation = 'ETX'; Risk = 8; Description = 'End of Text, a control character.' }
        0x04 = @{ Abbreviation = 'EOT'; Risk = 8; Description = 'End of Transmission, a control character.' }
        0x05 = @{ Abbreviation = 'ENQ'; Risk = 8; Description = 'Enquiry, a control character.' }
        0x06 = @{ Abbreviation = 'ACK'; Risk = 8; Description = 'Acknowledge, a control character.' }
        0x07 = @{ Abbreviation = 'BEL'; Risk = 8; Description = 'Bell character, can cause an audible or visual alert.' }
        0x08 = @{ Abbreviation = 'BS'; Risk = 8; Description = 'Backspace, a control character.' }
        0x09 = @{ Abbreviation = 'HT'; Risk = 8; Description = 'Horizontal Tab, a control character.' }
        0x0A = @{ Abbreviation = 'LF'; Risk = 9; Description = 'Line Feed, can split strings and be used in injection attacks (e.g., HTTP Response Splitting).' }
        0x0B = @{ Abbreviation = 'VT'; Risk = 8; Description = 'Vertical Tab, a control character.' }
        0x0C = @{ Abbreviation = 'FF'; Risk = 8; Description = 'Form Feed, a control character.' }
        0x0D = @{ Abbreviation = 'CR'; Risk = 9; Description = 'Carriage Return, can split strings and be used in injection attacks.' }
        0x0E = @{ Abbreviation = 'SO'; Risk = 8; Description = 'Shift Out, a control character.' }
        0x0F = @{ Abbreviation = 'SI'; Risk = 8; Description = 'Shift In, a control character.' }
        0x10 = @{ Abbreviation = 'DLE'; Risk = 8; Description = 'Data Link Escape, a control character.' }
        0x11 = @{ Abbreviation = 'DC1'; Risk = 8; Description = 'Device Control 1, a control character.' }
        0x12 = @{ Abbreviation = 'DC2'; Risk = 8; Description = 'Device Control 2, a control character.' }
        0x13 = @{ Abbreviation = 'DC3'; Risk = 8; Description = 'Device Control 3, a control character.' }
        0x14 = @{ Abbreviation = 'DC4'; Risk = 8; Description = 'Device Control 4, a control character.' }
        0x15 = @{ Abbreviation = 'NAK'; Risk = 8; Description = 'Negative Acknowledge, a control character.' }
        0x16 = @{ Abbreviation = 'SYN'; Risk = 8; Description = 'Synchronous Idle, a control character.' }
        0x17 = @{ Abbreviation = 'ETB'; Risk = 8; Description = 'End of Transmission Block, a control character.' }
        0x18 = @{ Abbreviation = 'CAN'; Risk = 8; Description = 'Cancel, a control character.' }
        0x19 = @{ Abbreviation = 'EM'; Risk = 8; Description = 'End of Medium, a control character.' }
        0x1A = @{ Abbreviation = 'SUB'; Risk = 8; Description = 'Substitute, a control character.' }
        0x1B = @{ Abbreviation = 'ESC'; Risk = 9; Description = 'Escape, can be used to initiate escape sequences.' }
        0x1C = @{ Abbreviation = 'FS'; Risk = 8; Description = 'File Separator, a control character.' }
        0x1D = @{ Abbreviation = 'GS'; Risk = 8; Description = 'Group Separator, a control character.' }
        0x1E = @{ Abbreviation = 'RS'; Risk = 8; Description = 'Record Separator, a control character.' }
        0x1F = @{ Abbreviation = 'US'; Risk = 8; Description = 'Unit Separator, a control character.' }
        # DEL character (Risk: 8 - High)
        0x7F = @{ Abbreviation = 'DEL'; Risk = 8; Description = 'Delete character, non-printable control character.' }
        # C1 Control Characters (Risk: 8 - High)
        0x80 = @{ Abbreviation = 'PAD'; Risk = 8; Description = 'Padding Character, a control character.' }
        0x81 = @{ Abbreviation = 'HOP'; Risk = 8; Description = 'High Octet Preset, a control character.' }
        0x82 = @{ Abbreviation = 'BPH'; Risk = 8; Description = 'Break Permitted Here, a control character.' }
        0x83 = @{ Abbreviation = 'NBH'; Risk = 8; Description = 'No Break Here, a control character.' }
        0x84 = @{ Abbreviation = 'IND'; Risk = 8; Description = 'Index, a control character.' }
        0x85 = @{ Abbreviation = 'NEL'; Risk = 9; Description = 'Next Line, can also be used for injection attacks.' }
        0x86 = @{ Abbreviation = 'SSA'; Risk = 8; Description = 'Start of Selected Area, a control character.' }
        0x87 = @{ Abbreviation = 'ESA'; Risk = 8; Description = 'End of Selected Area, a control character.' }
        0x88 = @{ Abbreviation = 'HTS'; Risk = 8; Description = 'Horizontal Tabulation Set, a control character.' }
        0x89 = @{ Abbreviation = 'HTJ'; Risk = 8; Description = 'Horizontal Tabulation with Justification, a control character.' }
        0x8A = @{ Abbreviation = 'VTS'; Risk = 8; Description = 'Vertical Tabulation Set, a control character.' }
        0x8B = @{ Abbreviation = 'PLD'; Risk = 8; Description = 'Partial Line Down, a control character.' }
        0x8C = @{ Abbreviation = 'PLU'; Risk = 8; Description = 'Partial Line Up, a control character.' }
        0x8D = @{ Abbreviation = 'RI'; Risk = 8; Description = 'Reverse Index, a control character.' }
        0x8E = @{ Abbreviation = 'SS2'; Risk = 8; Description = 'Single Shift Two, a control character.' }
        0x8F = @{ Abbreviation = 'SS3'; Risk = 8; Description = 'Single Shift Three, a control character.' }
        0x90 = @{ Abbreviation = 'DCS'; Risk = 8; Description = 'Device Control String, a control character.' }
        0x91 = @{ Abbreviation = 'PU1'; Risk = 8; Description = 'Private Use 1, a control character.' }
        0x92 = @{ Abbreviation = 'PU2'; Risk = 8; Description = 'Private Use 2, a control character.' }
        0x93 = @{ Abbreviation = 'STS'; Risk = 8; Description = 'Set Transmit State, a control character.' }
        0x94 = @{ Abbreviation = 'CCH'; Risk = 8; Description = 'Cancel Character, a control character.' }
        0x95 = @{ Abbreviation = 'MW'; Risk = 8; Description = 'Message Waiting, a control character.' }
        0x96 = @{ Abbreviation = 'SPA'; Risk = 8; Description = 'Start of Guarded Area, a control character.' }
        0x97 = @{ Abbreviation = 'EPA'; Risk = 8; Description = 'End of Guarded Area, a control character.' }
        0x98 = @{ Abbreviation = 'SOS'; Risk = 8; Description = 'Start of String, a control character.' }
        0x99 = @{ Abbreviation = 'SGC'; Risk = 8; Description = 'Single Graphic Character, a control character.' }
        0x9A = @{ Abbreviation = 'SCI'; Risk = 8; Description = 'Single Character Introducer, a control character.' }
        0x9B = @{ Abbreviation = 'CSI'; Risk = 8; Description = 'Control Sequence Introducer, a control character.' }
        0x9C = @{ Abbreviation = 'ST'; Risk = 8; Description = 'String Terminator, a control character.' }
        0x9D = @{ Abbreviation = 'OSC'; Risk = 8; Description = 'Operating System Command, a control character.' }
        0x9E = @{ Abbreviation = 'PM'; Risk = 8; Description = 'Privacy Message, a control character.' }
        0x9F = @{ Abbreviation = 'APC'; Risk = 8; Description = 'Application Program Command, a control character.' }
        # Invisible and Formatting Characters (Risk: 5-9 - Medium/High)
        0x00AD = @{ Abbreviation = 'SHY'; Risk = 6; Description = 'Soft Hyphen, an invisible formatting character that suggests a line break point.' }
        0x200B = @{ Abbreviation = 'ZWSP'; Risk = 7; Description = 'Zero Width Space, an invisible character that can bypass simple string length checks or filters.' }
        0x200C = @{ Abbreviation = 'ZWNJ'; Risk = 7; Description = 'Zero Width Non-Joiner, affects ligature formation and can evade text-based filters.' }
        0x200D = @{ Abbreviation = 'ZWJ'; Risk = 7; Description = 'Zero Width Joiner, affects ligature formation and can evade text-based filters.' }
        0x2060 = @{ Abbreviation = 'WJ'; Risk = 7; Description = 'Word Joiner, a zero-width non-breaking space, can be used to bypass filters.' }
        0xFEFF = @{ Abbreviation = 'BOM'; Risk = 8; Description = 'Byte Order Mark / Zero Width No-Break Space, can break parsers and affect string comparisons.' }
        # Bidirectional and Isolate Characters (Risk: 9 - High)
        0x200E = @{ Abbreviation = 'LRM'; Risk = 9; Description = 'Left-to-Right Mark, can be used to create visually deceptive text (Bidi attacks).' }
        0x200F = @{ Abbreviation = 'RLM'; Risk = 9; Description = 'Right-to-Left Mark, can be used to create visually deceptive text (Bidi attacks).' }
        0x202A = @{ Abbreviation = 'LRE'; Risk = 9; Description = 'Left-to-Right Embedding, can be used to create visually deceptive text (Bidi attacks).' }
        0x202B = @{ Abbreviation = 'RLE'; Risk = 9; Description = 'Right-to-Left Embedding, can be used to create visually deceptive text (Bidi attacks).' }
        0x202C = @{ Abbreviation = 'PDF'; Risk = 9; Description = 'Pop Directional Formatting, used in Bidi attacks.' }
        0x202D = @{ Abbreviation = 'LRO'; Risk = 9; Description = 'Left-to-Right Override, used in Bidi attacks.' }
        0x202E = @{ Abbreviation = 'RLO'; Risk = 9; Description = 'Right-to-Left Override, used in Bidi attacks.' }
        0x2066 = @{ Abbreviation = 'LRI'; Risk = 9; Description = 'Left-to-Right Isolate, used in Bidi attacks.' }
        0x2067 = @{ Abbreviation = 'RLI'; Risk = 9; Description = 'Right-to-Left Isolate, used in Bidi attacks.' }
        0x2068 = @{ Abbreviation = 'FSI'; Risk = 9; Description = 'First Strong Isolate, used in Bidi attacks.' }
        0x2069 = @{ Abbreviation = 'PDI'; Risk = 9; Description = 'Pop Directional Isolate, used in Bidi attacks.' }
        # Other Whitespace and Separators (Risk: 5-7 - Medium)
        0x2028 = @{ Abbreviation = 'LS'; Risk = 7; Description = 'Line Separator, can break strings unexpectedly.' }
        0x2029 = @{ Abbreviation = 'PS'; Risk = 7; Description = 'Paragraph Separator, can break strings unexpectedly.' }
        0x202F = @{ Abbreviation = 'NNBSP'; Risk = 6; Description = 'Narrow No-Break Space, a whitespace character that can be hard to spot.' }
        0x205F = @{ Abbreviation = 'MMSP'; Risk = 6; Description = 'Medium Mathematical Space, a whitespace character that can be hard to spot.' }
        0x3000 = @{ Abbreviation = 'IDSP'; Risk = 6; Description = 'Ideographic Space, a wide whitespace character that can be hard to spot.' }
    }
    [uint32[]]$StringCharIntegers = $String.ToCharArray()
    $FindingsHT = @{}
    $Forbidden.Keys |
        Where-Object { $StringCharIntegers -contains $_ }|
        ForEach-Object{
            $FindingsHT[$_] = $Forbidden[$_]
        }
    
    if ($FindingsHT.Count -gt 0) {
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Found high-risk characters: $(($FindingsHT.Keys | ForEach-Object { "0x{0:X4}" -f $_ }) -join ', ')"
        return @{
            Findings = $FindingsHT; 
            IsValid = $false; 
            Message = "String contains high-risk or non-printable characters.`n`t" +
                ($FindingsHT.Keys | ForEach-Object {
                    $detail = $FindingsHT[$_]
                    "0x{0:X4} ('{1}') - Risk: {2} - {3}" -f $_, $detail.Abbreviation, $detail.Risk, $detail.Description
                }).Join("`n`t")
        }
    }

    return @{ IsValid = $true; Message = "ok" }
}

function Test-IsValidPassword {
    [cmdletbinding()]
    param(
        [string]$Password,
        $Length = 8,
        $Uppercase = 2,
        $LowerCase = 2,
        $Symbols = 2,
        $Numbers = 2,
        $ValidSymbolCharactersRegex = '[!@#$%^&*()_+\-=\[\]{};'':"\\|,.<>/?`~]'
    )

    if ($PSBoundParameters.Verbose.IsPresent) {
        $caller = (Get-PSCallStack)[1].FunctionName
        Write-Verbose "Function 'Test-IsValidPassword' called from '$caller'."
    }

    $MyTag = "[Test-IsValidPassword]"
    if ($Password.Length -lt 8) {
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Password length is less than minimum required length of 8."
        return @{ IsValid = $false; Message = "Password must be at least 8 characters long." }
    }
    # Check for minimum uppercase characters
    if (($Password.ToCharArray() -match '[A-Z]').Count -lt $Uppercase) {
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Not enough uppercase characters regex: '[A-Z]'"
        return @{ IsValid = $false; Message = "Password must contain at least $Uppercase uppercase letters." }
    }
    # Check for minimum lowercase characters
    if (($Password.ToCharArray() -match '[a-z]').Count -lt $LowerCase) {
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Not enough lowercase characters regex: '[a-z]'"
        return @{ IsValid = $false; Message = "Password must contain at least $LowerCase lowercase letters." }
    }
    # Check for minimum numbers
    if (($Password.ToCharArray() -match '[0-9]').Count -lt $Numbers) {
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Not enough number characters regex: '[0-9]'"
        return @{ IsValid = $false; Message = "Password must contain at least $Numbers numbers." }
    }
    # Check for minimum symbols
    if ($Symbols -gt 0) { # Only check if a minimum number of symbols is required
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Valid symbol characters regex: $ValidSymbolCharactersRegex '$($Password.ToCharArray() -match $ValidSymbolCharactersRegex |ForEach-Object{[uint32]$_})'"
        if (($Password.ToCharArray() -match $ValidSymbolCharactersRegex).Count -lt $Symbols) {
            return @{ IsValid = $false; Message = "Password must contain at least $Symbols symbols." }
        }
    }
    # Check for unapproved characters
    if (($Password.ToCharArray() -match "[^a-zA-Z0-9$($ValidSymbolCharactersRegex)]").Count -gt 0) {
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Password contains unapproved characters."
        return @{ IsValid = $false; Message = "Password contains unapproved characters." }
    }

    $InvalidCharacters = Test-StringForHighRiskUnicode -String $Password
    if ($InvalidCharacters.IsValid -eq $false) {
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Password failed high-risk unicode check."
        return $InvalidCharacters
    }    
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Password passed high-risk unicode check."
    return @{ IsValid = $true; Message = "Password is valid." }
}

function Test-LoginLockout {
    [cmdletbinding()]
    param (
        [string]$IPAddress,
        [string]$Username
    )

    if ($PSBoundParameters.Verbose.IsPresent) {
        $caller = (Get-PSCallStack)[1].FunctionName
        Write-Verbose "Function 'Test-LoginLockout' called from '$caller'."
    }

    $MyTag = "[Test-LoginLockout]"
    if (-not $IPAddress) { Write-Host -ForegroundColor Red "$MyTag The -IPAddress parameter is required."; return $false}
    if (-not $Username) { Write-Host  -ForegroundColor Red "$MyTag The -Username parameter is required."; return $false}
    $lastAttempt = Get-LastLoginAttempt -IPAddress $IPAddress
    $now = Get-Date

    if ($lastAttempt) {
        if ($lastAttempt.IPAddressLockedUntil -and ($lastAttempt.IPAddressLockedUntil -as [datetime]) -gt $now) {
            $result =  [PSCustomObject]@{ 
                LockedOut = $true
                LockedUntil = ($lastAttempt.IPAddressLockedUntil -as [datetime])
                Message = "Too many requests from this IP address. Please try again after $(($lastAttempt.IPAddressLockedUntil -as [datetime]).ToString('o'))."
            }
            Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) IP Address lockout detected: $(($result | Out-String).trim('\s') -split '\n' -join "`n`t")"
            return $result
        }
        if ($lastAttempt.UserNameLockedUntil -and ($lastAttempt.UserNameLockedUntil -as [datetime]) -gt $now) {
            $result = [PSCustomObject]@{ 
                LockedOut = $true
                LockedUntil = ($lastAttempt.UserNameLockedUntil -as [datetime])
                Message = "Too many requests for this user. Please try again after $([math]::Round((($lastAttempt.UserNameLockedUntil -as [datetime]) - (Get-Date)).TotalSeconds)) seconds."
            }
            Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Username lockout detected: $(($result | Out-String).trim('\s') -split '\n' -join "`n`t")"
            return $result
        }
    }
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) No lockout detected for IP '$IPAddress' and Username '$Username'." 
    return [PSCustomObject]@{
        LockedOut = $false
    }
}

function Protect-String {
    [cmdletbinding()]
    param(
        [string]$PlainText
    )
    $MyTag = "[Protect-String]"
    if (-not $PlainText) { Write-Error "$MyTag The -PlainText parameter is required."; return }
    $secureString = $PlainText | ConvertTo-SecureString -AsPlainText -Force
    # The encrypted string is tied to the current user context and machine
    return $secureString | ConvertFrom-SecureString
}

function Unprotect-String {
    [cmdletbinding()]
    param(
        [string]$EncryptedString
    )
    $MyTag = "[Unprotect-String]"
    if (-not $EncryptedString) { Write-Error "$MyTag The -EncryptedString parameter is required."; return }
    $secureString = $EncryptedString | ConvertTo-SecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
    $plainText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Successfully decrypted string."
    return $plainText
}

function Register-PSWebHostUser {
    [cmdletbinding()]
    param(
        [string]$UserName,
        [string]$Email,
        [string]$Phone,
        [string]$Provider,
        [string]$Password,
        [hashtable]$ProviderData
    )
    $MyTag = "[Register-PSWebHostUser]"
    if (-not $UserName) { Write-Error "$MyTag The -UserName parameter is required."; return }
    if (-not $Provider) { Write-Error "$MyTag The -Provider parameter is required."; return }

    # 1. Generate UserID
    $userID = [Guid]::NewGuid().ToString()

    # 2. Store user in database
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

    # Generate password hash based on provider type
    $passwordHash = ""
    if ($Provider -eq "Password") {
        # 3. Generate Salt and Hash Password
        $saltBytes = New-Object byte[] 16
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($saltBytes)
        $saltString = [System.Convert]::ToBase64String($saltBytes)

        $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Password, $saltBytes, 10000)
        $passwordHashBytes = $pbkdf2.GetBytes(20) # 20 bytes for a 160-bit hash
        $passwordHash = [System.Convert]::ToBase64String($passwordHashBytes)

        # Initialize ProviderData if null
        if (-not $ProviderData) {
            $ProviderData = @{}
        }
        $ProviderData.Password = $passwordHash
        $ProviderData.Salt = $saltString
    } else {
        # For non-password providers (Windows, etc), use empty password hash
        $passwordHash = ""
    }

    # Users table only has: ID, UserID, Email, PasswordHash
    $userData = @{
        ID = $userID
        UserID = $userID
        Email = $Email
        PasswordHash = $passwordHash
    }

    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) New-PSWebSQLiteData -File $dbFile -Table 'Users' -Data `n`t$(($userData | Out-String).trim('\s') -split '\n' -join "`n`t")"
    New-PSWebSQLiteData -File $dbFile -Table "Users" -Data $userData
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed: New-PSWebSQLiteData"

    # 4. Store auth provider in database
    $authProviderData = @{
        UserID = $userID
        UserName = $UserName
        provider = $Provider
        created = (Get-Date -UFormat %s)
        locked_out = $false
        enabled = $true
    }
    if ($ProviderData) {
        $authProviderData.data = ($ProviderData | ConvertTo-Json -Compress)
    }


    $columns = ($authProviderData.Keys | ForEach-Object { "`"$_`"" }) -join ", "
    $values = $authProviderData.Values | ForEach-Object {
        if ($_ -is [string]) {
            "'$(Sanitize-SqlQueryString -String $_)'"
        } elseif ($_ -is [bool]) {
            if ($_) { 1 } else { 0 }
        } elseif ($_ -eq $null) {
            "NULL"
        } else {
            $_
        }
    }
    $valuesString = $values -join ", "
    $query = "INSERT INTO auth_user_provider ($columns) VALUES ($valuesString);"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: New-PSWebSQLiteNonQuery -File $dbFile -Query `n`t$query"
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed: New-PSWebSQLiteNonQuery"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) User '$UserName' created with UserID '$userID'." -Verbose
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Retrieving newly created user with UserID '$userID'."
    return Get-PSWebHostUser -UserID $userID
}

function New-PSWebHostUser {
    [cmdletbinding()]
    param(
        [string]$Email,
        [string]$UserName,
        [string]$Password,
        [string]$Phone
    )
    $MyTag = "[New-PSWebHostUser]"
    if (-not $Email) { Write-Error "The -Email parameter is required."; return }

    if (-not $UserName) {
        $UserName = $Email
    }
    if (-not $Password) {
        # Generate a random password if not provided
        $Password = [System.Web.Security.Membership]::GeneratePassword(12,2)
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) No password provided. Generated random password."
    }
    write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing Register-PSWebHostUser -UserName '$UserName' -Email '$Email' -Phone '$Phone' -Provider 'Password' -Password `$Password"
    Register-PSWebHostUser -UserName $UserName -Email $Email -Phone $Phone -Provider "Password" -Password $Password
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed: Register-PSWebHostUser"
}

function PSWebLogon {
    [cmdletbinding()]
    param(
        [string]$ProviderName,
        [ValidateSet('Success', 'Fail','Error')] [string]$Result,
        [System.Net.HttpListenerRequest]$Request,
        [string]$UserID = "anonymous" # Default to anonymous if not provided for success
    )
    $MyTag = "[PSWebLogon]"
    if (-not $UserID) { Write-Error "The -UserID parameter is required."; return }
    if (-not $ProviderName) { Write-Error "The -ProviderName parameter is required."; return }
    if (-not $Result) { Write-Error "The -Result parameter is required."; return }
    if (-not $Request) { Write-Error "The -Request parameter is required."; return }

    $ipAddress = $Request.RemoteEndPoint.Address.ToString()
    $sessionCookie = $Request.Cookies["PSWebSessionID"]
    $sessionID = $null
    if ($sessionCookie) { $sessionID = $sessionCookie.Value }
    $SessionData = $Global:PSWebSessions[$sessionID]
    [datetime]$now = Get-Date

    # Get existing login attempt data
    $lastAttempt = Get-LastLoginAttempt -IPAddress $ipAddress

    $userViolations = [int]$lastAttempt.UserViolationsCount
    $ipViolations = [int]$lastAttempt.IPViolationCount

    # Convert lockout timestamps to datetime or null (using untyped variables to allow null)
    $userNameLockedUntil = $null
    $ipAddressLockedUntil = $null

    # Check UserNameLockedUntil - handle null, empty, and DBNull
    if ($lastAttempt.UserNameLockedUntil) {
        $value = $lastAttempt.UserNameLockedUntil
        if ($value -isnot [System.DBNull] -and ![string]::IsNullOrWhiteSpace($value)) {
            try {
                $userNameLockedUntil = [datetime]::FromFileTimeUtc([long]$value * 10000000 + 116444736000000000)
            } catch {
                $userNameLockedUntil = $null
            }
        }
    }

    # Check IPAddressLockedUntil - handle null, empty, and DBNull
    if ($lastAttempt.IPAddressLockedUntil) {
        $value = $lastAttempt.IPAddressLockedUntil
        if ($value -isnot [System.DBNull] -and ![string]::IsNullOrWhiteSpace($value)) {
            try {
                $ipAddressLockedUntil = [datetime]::FromFileTimeUtc([long]$value * 10000000 + 116444736000000000)
            } catch {
                $ipAddressLockedUntil = $null
            }
        }
    }

    if ($Result -eq "Fail") {
        $userViolations++
        $ipViolations++

        $lockoutUntil = $now.AddSeconds(4.5) # Default 4.5 second cooldown

        if ($userViolations % 5 -eq 0) { # Every 5 failed attempts for the user
            $lockoutUntil = $now.AddMinutes(1)
        }
        if ($ipViolations -gt 10) {
            $ipAddressLockedUntil = $now.AddHours(1)
        }
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Login failed. User violations: $userViolations, IP violations: $ipViolations. User lockout until: $lockoutUntil, IP lockout until: $ipAddressLockedUntil"
        Set-LastLoginAttempt -IPAddress $ipAddress -Username $UserID -Time $now -UserNameLockedUntil $lockoutUntil -IPAddressLockedUntil $ipAddressLockedUntil -UserViolationsCount $userViolations -IPViolationCount $ipViolations
        Write-PSWebHostLog -Severity 'Warning' -Category 'Auth' -Message "Login failed for user '$UserID' from IP '$ipAddress' via '$ProviderName'. Violations: User=$userViolations, IP=$ipViolations." -Data @{ UserID = $UserID; IPAddress = $ipAddress; Provider = $ProviderName; Result = $Result }
    } else { # Success
        # Reset violation counts on success
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Login successful. Resetting violation counts for user '$UserID' and IP '$ipAddress'."
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing Set-LastLoginAttempt -IPAddress $ipAddress -Username $UserID -Time $now -UserViolationsCount 0 -IPViolationCount 0 -UserNameLockedUntil `$null -IPAddressLockedUntil `$null"
        try{
            Set-LastLoginAttempt -IPAddress $ipAddress -Username $UserID -Time $now -UserViolationsCount 0 -IPViolationCount 0 -UserNameLockedUntil $null -IPAddressLockedUntil $null
        }
        catch{
            write-PSWebHostLog -Severity critical -Category Set-LastLoginAttempt -message "$MyTag Failed to reset login attempt data for user '$UserID' and IP '$ipAddress'. Error: $_"
        }
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed: Set-LastLoginAttempt"
        # Record successful login session
        if ($sessionID) {
            $logonExpires = $now.AddHours(8) # Example: Session expires in 8 hours
            Set-LoginSession -SessionID $sessionID -UserID $UserID -Provider $ProviderName -AuthenticationTime $now -AuthenticationState 'Authenticated' -LogonExpires $logonExpires -UserAgent $Request.UserAgent 
        }
        Write-PSWebHostLog -Severity 'Info' -Category 'Auth' -Message "Login successful for user '$UserID' from IP '$ipAddress' via '$ProviderName'." -Data @{ UserID = $UserID; IPAddress = $ipAddress; Provider = $ProviderName; Result = $Result }
    }
}


function Add-PSWebHostRole {
    [cmdletbinding()]
    param(
        [string]$RoleName
    )
    $MyTag = "[Add-PSWebHostRole]"
    if (-not $RoleName) { Write-Error "The -RoleName parameter is required."; return }
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $safeRoleName = Sanitize-SqlQueryString -String $RoleName
    $query = "INSERT INTO PSWeb_Roles (PrincipalID, PrincipalType, RoleName) VALUES ('$safeRoleName', 'role', '$safeRoleName');"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: Invoke-PSWebSQLiteNonQuery -File $dbFile -Query `n`t$query"
    Write-PSWebHostLog -Severity 'Info' -Category 'RoleManagement' -Message "Adding role '$RoleName' to PSWebHost." -Data @{ RoleName = $RoleName }
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed: Invoke-PSWebSQLiteNonQuery"
}

function Remove-PSWebHostRole {
    [cmdletbinding()]
    param(
        [string]$RoleName
    )
    $MyTag = "[Remove-PSWebHostRole]"
    if (-not $RoleName) { Write-Error "The -RoleName parameter is required."; return }
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $safeRoleName = Sanitize-SqlQueryString -String $RoleName
    $query = "DELETE FROM PSWeb_Roles WHERE RoleName = '$safeRoleName';"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: Invoke-PSWebSQLiteNonQuery -File $dbFile -Query `n`t$query"
    Write-PSWebHostLog -Severity 'Info' -Category 'RoleManagement' -Message "Removing role '$RoleName' from PSWebHost." -Data @{ RoleName = $RoleName }
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed: Invoke-PSWebSQLiteNonQuery"
}

function Add-PSWebHostRoleAssignment {
    [cmdletbinding()]
    param(
        [string]$UserID,
        [string]$RoleName
    )
    $MyTag = "[Add-PSWebHostRoleAssignment]"
    if (-not $UserID) { Write-Error "The -UserID parameter is required."; return }
    if (-not $RoleName) { Write-Error "The -RoleName parameter is required."; return }
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $safeUserID = Sanitize-SqlQueryString -String $UserID
    $safeRoleName = Sanitize-SqlQueryString -String $RoleName
    $query = "INSERT INTO PSWeb_Roles (PrincipalID, PrincipalType, RoleName) VALUES ('$safeUserID', 'user', '$safeRoleName');"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: Invoke-PSWebSQLiteNonQuery -File $dbFile -Query `n`t$query"
    Write-PSWebHostLog -Severity 'Info' -Category 'RoleManagement' -Message "Assigning role '$RoleName' to user '$UserID'." -Data @{ RoleName = $RoleName; UserID = $UserID }
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed: Invoke-PSWebSQLiteNonQuery"
}

function Remove-PSWebHostRoleAssignment {
    [cmdletbinding()]
    param(
        [string]$UserID,
        [string]$RoleName
    )
    $MyTag = "[Remove-PSWebHostRoleAssignment]"
    if (-not $UserID) { Write-Error "The -UserID parameter is required."; return }
    if (-not $RoleName) { Write-Error "The -RoleName parameter is required."; return }
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $safeUserID = Sanitize-SqlQueryString -String $UserID
    $safeRoleName = Sanitize-SqlQueryString -String $RoleName
    $query = "DELETE FROM PSWeb_Roles WHERE PrincipalID = '$safeUserID' AND RoleName = '$safeRoleName';"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: Invoke-PSWebSQLiteNonQuery -File $dbFile -Query `n`t$query"
    Write-PSWebHostLog -Severity 'Info' -Category 'RoleManagement' -Message "Removing role '$RoleName' from user '$UserID'." -Data @{ RoleName = $RoleName; UserID = $UserID }
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query
}

function Add-PSWebHostGroup {
    [cmdletbinding()]
    param(
        [string]$GroupName
    )
    $MyTag = "[Add-PSWebHostGroup]"
    if (-not $GroupName) { Write-Error "The -GroupName parameter is required."; return }
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $safeGroupName = Sanitize-SqlQueryString -String $GroupName
    $groupID = [Guid]::NewGuid().ToString()
    $query = "INSERT INTO User_Groups (GroupID, Name, Created, Updated) VALUES ('$groupID', '$safeGroupName', '$(Get-Date -UFormat %s)', '$(Get-Date -UFormat %s)');"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: Invoke-PSWebSQLiteNonQuery -File $dbFile -Query `n`t$query"
    Write-PSWebHostLog -Severity 'Info' -Category 'GroupManagement' -Message "Adding group '$GroupName' to PSWebHost." -Data @{ GroupName = $GroupName }
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed: Invoke-PSWebSQLiteNonQuery"
}

function Remove-PSWebHostGroup {
    [cmdletbinding()]
    param(
        [string]$GroupID
    )
    $MyTag = "[Remove-PSWebHostGroup]"
    if (-not $GroupID) { Write-Error "The -GroupID parameter is required."; return }
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $safeGroupID = Sanitize-SqlQueryString -String $GroupID
    $query = "DELETE FROM User_Groups WHERE GroupID = '$safeGroupID';"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: Invoke-PSWebSQLiteNonQuery -File $dbFile -Query `n`t$query"
    Write-PSWebHostLog -Severity 'Info' -Category 'GroupManagement' -Message "Removing group with ID '$GroupID' from PSWebHost." -Data @{ GroupID = $GroupID }
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed: Invoke-PSWebSQLiteNonQuery"
}

function Add-PSWebHostGroupMember {
    [cmdletbinding()]
    param(
        [string]$UserID,
        [string]$GroupID
    )
    $MyTag = "[Add-PSWebHostGroupMember]"
    if (-not $UserID) { Write-Error "The -UserID parameter is required."; return }
    if (-not $GroupID) { Write-Error "The -GroupID parameter is required."; return }
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $safeUserID = Sanitize-SqlQueryString -String $UserID
    $safeGroupID = Sanitize-SqlQueryString -String $GroupID
    $query = "INSERT INTO User_Groups_Map (UserID, GroupID) VALUES ('$safeUserID', '$safeGroupID');"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: Invoke-PSWebSQLiteNonQuery -File $dbFile -Query `n`t$query"
    Write-PSWebHostLog -Severity 'Info' -Category 'GroupManagement' -Message "Adding user '$UserID' to group '$GroupID'." -Data @{ UserID = $UserID; GroupID = $GroupID }
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed: Invoke-PSWebSQLiteNonQuery"
}

function Remove-PSWebHostGroupMember {
    [cmdletbinding()]
    param(
        [string]$UserID,
        [string]$GroupID
    )
    $MyTag = "[Remove-PSWebHostGroupMember]"
    if (-not $UserID) { Write-Error "The -UserID parameter is required."; return }
    if (-not $GroupID) { Write-Error "The -GroupID parameter is required."; return }
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $safeUserID = Sanitize-SqlQueryString -String $UserID
    $safeGroupID = Sanitize-SqlQueryString -String $GroupID
    $query = "DELETE FROM User_Groups_Map WHERE UserID = '$safeUserID' AND GroupID = '$safeGroupID';"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: Invoke-PSWebSQLiteNonQuery -File $dbFile -Query `n`t$query"
    Write-PSWebHostLog -Severity 'Info' -Category 'GroupManagement' -Message "Removing user '$UserID' from group '$GroupID'." -Data @{ UserID = $UserID; GroupID = $GroupID }
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query
}

function Get-PSWebHostGroup {
    [cmdletbinding()]
    param(
        [string]$Name
    )
    $MyTag = "[Get-PSWebHostGroup]"
    if (-not $Name) { Write-Error "The -Name parameter is required."; return }
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $safeName = Sanitize-SqlQueryString -String $Name
    $query = "SELECT * FROM User_Groups WHERE Name = '$safeName';"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: Get-PSWebSQLiteData -File $dbFile -Query `n`t$query"
    write-PSWebHostLog -Severity 'Info' -Category 'GroupManagement' -Message "Retrieving group with name '$Name'." -Data @{ GroupName = $Name }
    Get-PSWebSQLiteData -File $dbFile -Query $query
}

# --- Re-implemented Session and Settings Functions ---

function Get-LoginSession {
    param([string]$SessionID)
    $MyTag = "[Get-LoginSession]"
    if (-not $SessionID) { Write-Error "$MyTag The -SessionID parameter is required."; return }
    $safeSessionID = Sanitize-SqlQueryString -String $SessionID
    $query = "SELECT * FROM LoginSessions WHERE SessionID = '$safeSessionID' LIMIT 1;"
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    Write-PSWebHostLog -Message "$MyTag Calling: Get-PSWebSQLiteData -File $dbFile -Query `n`t$query" -Severity 'info' -Category 'Auth'
    $result = Get-PSWebSQLiteData -File $dbFile -Query $query
    if (-not $result) {
        Write-PSWebHostLog "$MyTag No session found for SessionID: $SessionID" -Severity 'info' -Category 'Auth'
        return $null
    }
    # Get-PSWebSQLiteData returns an array even for single results, unwrap it
    $Session = if ($result -is [System.Array]) {
        Write-PSWebHostLog "$MyTag Result is array with $($result.Count) elements, unwrapping first element" -Severity 'info' -Category 'Auth'
        $result[0]
    } else {
        Write-PSWebHostLog "$MyTag Result is single object, returning as-is" -Severity 'info' -Category 'Auth'
        $result
    }
    Write-PSWebHostLog "$MyTag Completed Get-PSWebSQLiteData Session type: $($Session.GetType().FullName) Session: $Session" -Severity 'info' -Category 'Auth'
    return $Session
}

function Set-LoginSession {
    [cmdletbinding()]
    param(
        [string]$SessionID,
        [string]$UserID,
        [string]$Provider,
        [datetime]$AuthenticationTime = (Get-Date),
        [string]$AuthenticationState,
        [datetime]$LogonExpires,
        [string]$UserAgent
    )
    $MyTag = '[Set-LoginSession]'
    if (-not $SessionID) { Write-PSWebHostLog -Severity Error -Category 'Set-LoginSession_Parameter' -message "$MyTag The -SessionID parameter is required." -WriteHost -ForegroundColor Red; return }
    if (-not $UserID) { Write-PSWebHostLog -Severity Error -Category 'Set-LoginSession_Parameter' -message "$MyTag The -UserID parameter is required." -WriteHost -ForegroundColor Red  ; return }
    if (-not $Provider) { Write-PSWebHostLog -Severity Error -Category 'Set-LoginSession_Parameter' -message "$MyTag The -Provider parameter is required." -WriteHost -ForegroundColor Red; return }
    if (-not $AuthenticationTime) { Write-PSWebHostLog -Severity Error -Category 'Set-LoginSession_Parameter' -message "The -AuthenticationTime parameter is required." -WriteHost -ForegroundColor Red; return }
    # AuthenticationState may be omitted by callers; if so, preserve existing state or default to 'completed' when a UserID is provided.
    if (-not $LogonExpires) { Write-PSWebHostLog -Severity Error -Category 'Set-LoginSession_Parameter' -message "$MyTag The -LogonExpires parameter is required." -WriteHost -ForegroundColor Red; return }
    if (-not $UserAgent) { Write-PSWebHostLog -Severity Error -Category 'Set-LoginSession_Parameter' -message "$MyTag The -UserAgent parameter is required." -WriteHost -ForegroundColor Red; return }
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Calling: Sanitize-SqlQueryString -String $SessionID"
    $safeSessionID = Sanitize-SqlQueryString -String $SessionID
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed Sanitize-SqlQueryString"

    # Check if session exists
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Calling: Get-LoginSession -SessionID $safeSessionID"
    $existing = Get-LoginSession -SessionID $safeSessionID
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed Get-LoginSession"

    if (-not $AuthenticationState -or $AuthenticationState -eq '') {
        if ($existing -and $existing.AuthenticationState) {
            $AuthenticationState = $existing.AuthenticationState
        } elseif ($UserID -and $UserID.Trim() -ne '') {
            # If a UserID is being set but no state provided, assume completed
            $AuthenticationState = 'completed'
        } else {
            $AuthenticationState = ''
        }
    }

    $data = @{
        SessionID = $safeSessionID
        UserID = Sanitize-SqlQueryString -String $UserID
        Provider = Sanitize-SqlQueryString -String $Provider
        AuthenticationTime = ($AuthenticationTime | Get-Date -UFormat %s)
        AuthenticationState = $AuthenticationState
        LogonExpires = ($LogonExpires | Get-Date -UFormat %s)
        UserAgent = Sanitize-SqlQueryString -String $UserAgent
    }

    if ($existing) {
        # Update
        $updatePairs = ($data.Keys | ForEach-Object { "$_ = '$($data[$_])'" }) -Join ', '
        $query = "UPDATE LoginSessions SET $updatePairs WHERE SessionID = '$safeSessionID';"
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Calling: Invoke-PSWebSQLiteNonQuery -File '$dbFile' -Query `n`t$query"
        write-PSWebHostLog -Severity 'Info' -Category 'Auth' -Message "Updating login session for SessionID '$SessionID'." -Data @{ SessionID = $SessionID; UserID = $UserID }
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed Invoke-PSWebSQLiteNonQuery"
    } else {
        # Insert
        $columns = ($data.Keys | ForEach-Object { "`"$_`"" }) -join ", "
        $values = ($data.Keys | ForEach-Object { "'$($data[$_])'" }) -Join ', '
        $query = "INSERT INTO LoginSessions ($columns) VALUES ($values);"
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Calling: Invoke-PSWebSQLiteNonQuery -File '$dbFile' -Query `n`t$query"
        write-PSWebHostLog -Severity 'Info' -Category 'Auth' -Message "Creating new login session for SessionID '$SessionID'." -Data @{ SessionID = $SessionID; UserID = $UserID }
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed Invoke-PSWebSQLiteNonQuery"
    }
}

function Get-LastLoginAttempt {
    param([string]$IPAddress)
    $MyTag = "[Get-LastLoginAttempt]"
    if (-not $IPAddress) { Write-Error "$MyTag The -IPAddress parameter is required."; return }
    $safeIP = Sanitize-SqlQueryString -String $IPAddress
    $query = "SELECT * FROM LastLoginAttempt WHERE IPAddress = '$safeIP' ORDER BY Time DESC LIMIT 1;"
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Calling: Get-PSWebSQLiteData -File $dbFile -Query `n`t$query"
    Get-PSWebSQLiteData -File $dbFile -Query $query
    write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed Get-PSWebSQLiteData"
}

function Set-LastLoginAttempt {
    param(
        [string]$IPAddress,
        [string]$Username,
        [datetime]$Time,
        $UserNameLockedUntil = $null,
        $IPAddressLockedUntil = $null,
        [int]$UserViolationsCount,
        [int]$IPViolationCount
    )
    $MyTag = "[Set-LastLoginAttempt]"
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    
    # Sanitize inputs
    $safeIPAddress = Sanitize-SqlQueryString -String $IPAddress
    $safeUsername = Sanitize-SqlQueryString -String $Username
    $unixTime = ($Time | Get-Date -UFormat %s)
    $unixUserLock = if($UserNameLockedUntil) { ($UserNameLockedUntil | Get-Date -UFormat %s) } else { 'NULL' }
    $unixIPLock = if($IPAddressLockedUntil) { ($IPAddressLockedUntil | Get-Date -UFormat %s) } else { 'NULL' }

    # Construct the INSERT OR REPLACE query manually
    $query = "INSERT OR REPLACE INTO LastLoginAttempt (IPAddress, Username, Time, UserNameLockedUntil, IPAddressLockedUntil, UserViolationsCount, IPViolationCount) VALUES ('$safeIPAddress', '$safeUsername', '$unixTime', $unixUserLock, $unixIPLock, $UserViolationsCount, $IPViolationCount);"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Callling: Invoke-PSWebSQLiteNonQuery -File '$dbFile' -Query `n`t$query"
    write-PSWebHostLog -Severity 'Info' -Category 'Auth' -Message "Setting last login attempt for IP '$IPAddress' and Username '$Username'." -Data @{ IPAddress = $IPAddress; Username = $Username; Time = $Time; UserNameLockedUntil = $UserNameLockedUntil; IPAddressLockedUntil = $IPAddressLockedUntil; UserViolationsCount = $UserViolationsCount; IPViolationCount = $IPViolationCount }
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed Invoke-PSWebSQLiteNonQuery"
}

function Get-CardSettings {
    param(
        [string]$EndpointGuid, 
        [string]$UserId
    )
    $MyTag = "[Get-CardSettings]"
    if (-not $EndpointGuid) { Write-Error "$MyTag The -EndpointGuid parameter is required."; return }
    if (-not $UserId) { Write-Error "$MyTag The -UserId parameter is required."; return }
    $safeGuid = Sanitize-SqlQueryString -String $EndpointGuid
    $safeUser = Sanitize-SqlQueryString -String $UserId
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

    # Read JSON from the `data` column (alias it as SettingsJson for compatibility)
    $query = "SELECT data AS SettingsJson FROM card_settings WHERE user_id = '$safeUser' AND endpoint_guid = '$safeGuid' LIMIT 1;"
    write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: $query"
    try {
        $result = Get-PSWebSQLiteData -File $dbFile -Query $query -ErrorAction Stop
        write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed data query"
    } catch {
        Write-PSWebHostLog -Severity Error -Category 'SQLData' -message "$MyTag Data column query failed: $($_.Exception.Message)" -WriteHost -ForegroundColor Red
        return $null
    }

    if ($result) {
        $row = if ($result -is [System.Array]) { $result[0] } else { $result }
        if ($row.PSObject.Properties.Name -contains 'SettingsJson') {
            return $row.SettingsJson
        } elseif ($row.PSObject.Properties.Name -contains 'data') {
            return $row.data
        } else {
            $firstProp = $row.PSObject.Properties | Select-Object -First 1
            return $firstProp.Value
        }
    }

    return $null
}

function Set-CardSettings {
    param(
        [string]$EndpointGuid,
        [string]$UserId,
        [string]$Data
    )
    $MyTag = "[Set-CardSettings]"
    if (-not $EndpointGuid) { Write-Error "$MyTag The -EndpointGuid parameter is required."; return }
    if (-not $UserId) { Write-Error "$MyTag The -UserId parameter is required."; return }
    if (-not $Data) { Write-Error "$MyTag The -Data parameter is required."; return }

    $safeGuid = Sanitize-SqlQueryString -String $EndpointGuid
    $safeUser = Sanitize-SqlQueryString -String $UserId
    $safeData = Sanitize-SqlQueryString -String $Data
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Use INSERT OR REPLACE to handle both insert and update
    $query = @"
INSERT OR REPLACE INTO card_settings (endpoint_guid, user_id, data, created_date, last_updated)
VALUES (
    '$safeGuid',
    '$safeUser',
    '$safeData',
    COALESCE((SELECT created_date FROM card_settings WHERE endpoint_guid = '$safeGuid' AND user_id = '$safeUser'), '$now'),
    '$now'
);
"@

    write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing: $query"
    Write-Host "$MyTag Saving card settings - EndpointGuid: $safeGuid, UserId: $safeUser, DataLength: $($safeData.Length)"
    try {
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query -ErrorAction Stop
        write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Card settings saved successfully"
        Write-Host "$MyTag Card settings saved successfully" -ForegroundColor Green
        return $true
    } catch {
        $errorMsg = "$MyTag Failed to save card settings: $($_.Exception.Message)"
        Write-PSWebHostLog -Severity Error -Category 'SQLData' -message $errorMsg -WriteHost -ForegroundColor Red
        Write-Host "$MyTag SQL Query was: $query" -ForegroundColor Red
        Write-Host "$MyTag Exception Details: $($_.Exception | Format-List -Force | Out-String)" -ForegroundColor Red
        return $false
    }
}

function Set-CardSession {
    param(
        [string]$SessionID,
        [string]$UserID,
        [string]$CardGUID,
        [string]$DataBackend,
        [string]$CardDefinition
    )
    $MyTag = "[Set-CardSession]"
    if (-not $SessionID) { Write-Error "$MyTag The -SessionID parameter is required."; return }
    if (-not $UserID) { Write-Error "$MyTag The -UserID parameter is required."; return }
    if (-not $CardGUID) { Write-Error "$MyTag The -CardGUID parameter is required."; return }
    if (-not $DataBackend) { Write-Error "$MyTag The -DataBackend parameter is required."; return }
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $data = @{
        SessionID = Sanitize-SqlQueryString -String $SessionID
        UserID = Sanitize-SqlQueryString -String $UserID
        CardGUID = Sanitize-SqlQueryString -String $CardGUID
        DataBackend = Sanitize-SqlQueryString -String $DataBackend
        CardDefinition = Sanitize-SqlQueryString -String $CardDefinition # Assuming this is already compressed/encoded
    }
    # This table name is a guess
    $columns = ($data.Keys | ForEach-Object { "`"$_`"" }) -join ", "
    $values = $data.Values | ForEach-Object {
        if ($_ -is [string]) {
            "'$_'" # Already sanitized
        } else {
            $_
        }
    }
    $valuesString = $values -join ", "
    $query = "INSERT OR REPLACE INTO CardSessions ($columns) VALUES ($valuesString);"
    write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Calling: Invoke-PSWebSQLiteNonQuery -File '$dbFile' -Query `n`t$query"
    write-PSWebHostLog -Severity 'Info' -Category 'CardSession' -Message "Setting card session for SessionID '$SessionID', UserID '$UserID', CardGUID '$CardGUID'." -Data @{ SessionID = $SessionID; UserID = $UserID; CardGUID = $CardGUID }
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed Invoke-PSWebSQLiteNonQuery" 
}

function Remove-LoginSession {
    param([string]$SessionID)
    $MyTag = "[Remove-LoginSession]"
    if (-not $SessionID) { Write-Error "$MyTag The -SessionID parameter is required."; return }
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $safeSessionID = Sanitize-SqlQueryString -String $SessionID
    $query = "DELETE FROM LoginSessions WHERE SessionID = '$safeSessionID';"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Calling: Invoke-PSWebSQLiteNonQuery -File '$dbFile' -Query `n`t$query"
    write-PSWebHostLog -Severity 'Info' -Category 'Auth' -Message "Removing login session for SessionID '$SessionID'." -Data @{ SessionID = $SessionID }
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed Invoke-PSWebSQLiteNonQuery"
}
