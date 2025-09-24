function Get-AuthenticationMethod {
    [cmdletbinding()]
    param()

    # This function would typically query a database or configuration file
    # to get the available authentication methods.
    # For now, we'll return a static list.
    return @("Password", "OTP_Email", "OTP_SMS")
}

function Get-AuthenticationMethodForm {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )

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
        [Parameter(Mandatory=$true)]
        [string]$Email
    )

    $dbFile = "pswebhost.db"
    $query = "SELECT * FROM Users WHERE Email = '$Email';"
    $user = Get-PSWebSQLiteData -File $dbFile -Query $query
    return $user
}

function Get-PSWebHostUsers {
    [cmdletbinding()]
    param()
    $dbFile = "pswebhost.db"
    $query = "SELECT Email FROM Users;"
    $users = Get-PSWebSQLiteData -File $dbFile -Query $query
    if ($users) {
        return $users.Email
    } else {
        return @()
    }
}

function Get-UserAuthenticationMethods {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Email
    )

    $user = Get-PSWebHostUser -Email $Email
    if (-not $user) {
        return @()
    }

    $dbFile = "pswebhost.db"
    $query = "SELECT provider FROM auth_user_provider WHERE UserID = '$($user.UserID)';"
    $authMethods = Get-PSWebSQLiteData -File $dbFile -Query $query
    
    if ($authMethods) {
        return $authMethods.provider
    } else {
        return @()
    }
}

function Get-UserRoles {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$UserID
    )

    $dbFile = "pswebhost.db"

    # Get roles assigned directly to the user
    $queryDirectRoles = "SELECT RoleName FROM PSWeb_Roles WHERE PrincipalID = '$UserID';"
    $directRoles = Get-PSWebSQLiteData -File $dbFile -Query $queryDirectRoles

    # Get roles assigned to groups the user is in
    $queryGroupRoles = "SELECT r.RoleName FROM PSWeb_Roles r JOIN User_Groups_Map ugm ON r.PrincipalID = ugm.GroupID WHERE ugm.UserID = '$UserID';"
    $groupRoles = Get-PSWebSQLiteData -File $dbFile -Query $queryGroupRoles

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
        [Parameter(Mandatory=$true)]
        [string]$Name,

        [Parameter(Mandatory=$true)]
        [hashtable]$FormData
    )

    switch ($Name) {
        "Password" {
            # --- Password Authentication Logic ---
            $email = $FormData.Username
            $password = $FormData.Password

            # 1. Get user from database
            $user = Get-PSWebSQLiteData -File $dbFile -Query $query
            if (-not $user) {
                Write-Warning "Authentication failed: User '$email' not found."
                return $false
            }

            # 2. Get stored password hash for the user
            $dbFile = "pswebhost.db"
            $query = "SELECT Data FROM AuthenticationMethods WHERE UserID = ' $($user.UserID)' AND Authentication_Method = 'Password';"
            $authMethod = Get-PSWebSQLiteData -File $dbFile -Query $query
            if (-not $authMethod) {
                Write-Warning "Authentication failed: No password set for user '$email'."
                return $false
            }
            $storedPasswordHash = $authMethod.Data

            # 3. Hash the provided password with the user's salt
            $saltBytes = [System.Convert]::FromBase64String($user.Salt)
            $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($password, $saltBytes, 10000)
            $providedPasswordHashBytes = $pbkdf2.GetBytes(20)
            $providedPasswordHash = [System.Convert]::ToBase64String($providedPasswordHashBytes)

            # 4. Compare the hashes
            if ($providedPasswordHash -eq $storedPasswordHash) {
                Write-Verbose "Password authentication successful for user '$email'."
                return $true
            } else {
                Write-Warning "Password authentication failed for user '$email'."
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
            $isAuthenticated = & $scriptPath -Username $username -Password $password -ContextType "LocalMachine" # Assuming LocalMachine for now

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
    param(
        [string]$Email,
        [string]$Regex = '^[a-zA-Z0-9._\+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
        [string]$AddCustomRegex
    )
    # Basic email validation regex
    if ($AddCustomRegex) {$Regex+="|$AddCustomRegex"}
    $InvalidCharacters = Test-StringForHighRiskUnicode -String $Email
    if ($InvalidCharacters.IsValid -eq $false) {
        return $InvalidCharacters
    }
    if (-not ($Email -match $Regex)) {
        return @{ isValid = $false; Message = "Email address format is invalid." }
    }
    return @{ isValid = $true; Message = "Email address is valid." }
}


function Test-StringForHighRiskUnicode {
    param(
        [string]$String
    )
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
    param(
        [string]$Password,
        $Length = 8,
        $Uppercase = 2,
        $LowerCase = 2,
        $Symbols = 2,
        $Numbers = 2,
        $ValidSymbolCharactersRegex = '[!@#$%^&*()_+\-=\[\]{};'':"\\|,.<>/?`~]'
    )
    if ($Password.Length -lt 8) {
        return @{ IsValid = $false; Message = "Password must be at least 8 characters long." }
    }
    # Check for minimum uppercase characters
    if (($Password.ToCharArray() -match '[A-Z]').Count -lt $Uppercase) {
        return @{ IsValid = $false; Message = "Password must contain at least $Uppercase uppercase letters." }
    }
    # Check for minimum lowercase characters
    if (($Password.ToCharArray() -match '[a-z]').Count -lt $LowerCase) {
        return @{ IsValid = $false; Message = "Password must contain at least $LowerCase lowercase letters." }
    }
    # Check for minimum numbers
    if (($Password.ToCharArray() -match '[0-9]').Count -lt $Numbers) {
        return @{ IsValid = $false; Message = "Password must contain at least $Numbers numbers." }
    }
    # Check for minimum symbols
    if ($Symbols -gt 0) { # Only check if a minimum number of symbols is required
        if (($Password.ToCharArray() -match $ValidSymbolCharacters).Count -lt $Symbols) {
            return @{ IsValid = $false; Message = "Password must contain at least $Symbols symbols." }
        }
    }
    # Check for unapproved characters
    if (($Password.ToCharArray() -match "[^a-zA-Z0-9$($ValidSymbolCharactersRegex)]").Count -gt 0) {
        return @{ IsValid = $false; Message = "Password contains unapproved characters." }
    }

    $InvalidCharacters = Test-StringForHighRiskUnicode -String $Password
    if ($InvalidCharacters.IsValid -eq $false) {
        return $InvalidCharacters
    }    

    return @{ IsValid = $true; Message = "Password is valid." }
}

function Test-LoginLockout {
    param (
        [string]$IPAddress,
        [string]$Username
    )
    $lastAttempt = Get-LastLoginAttempt -IPAddress $IPAddress
    $now = Get-Date

    if ($lastAttempt) {
        if ($lastAttempt.IPAddressLockedUntil -and ($lastAttempt.IPAddressLockedUntil -as [datetime]) -gt $now) {
            return [PSCustomObject]@{
                LockedOut = $true
                LockedUntil = ($lastAttempt.IPAddressLockedUntil -as [datetime])
                Message = "Too many requests from this IP address. Please try again after $(($lastAttempt.IPAddressLockedUntil -as [datetime]).ToString('o'))."
            }
        }
        if ($lastAttempt.UserNameLockedUntil -and ($lastAttempt.UserNameLockedUntil -as [datetime]) -gt $now) {
            return [PSCustomObject]@{
                LockedOut = $true
                LockedUntil = ($lastAttempt.UserNameLockedUntil -as [datetime])
                Message = "Too many requests for this user. Please try again after $(($lastAttempt.UserNameLockedUntil -as [datetime]).ToString('o'))."
            }
        }
    }
    return [PSCustomObject]@{
        LockedOut = $false
    }
}

function New-PSWebHostUser {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Email,

        [Parameter(Mandatory=$true)]
        [string]$Password,

        [string]$Phone
    )

    # 1. Generate Salt
    $saltBytes = New-Object byte[] 16
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($saltBytes)
    $saltString = [System.Convert]::ToBase64String($saltBytes)

    # 2. Generate UserID
    $epoch = [int64](((Get-Date).ToUniversalTime()) - (Get-Date "1970-01-01")).TotalSeconds
    $toHash = "$epoch$saltString"
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($toHash))
    $userID = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()

    # 3. Hash Password
    $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Password, $saltBytes, 10000)
    $passwordHashBytes = $pbkdf2.GetBytes(20) # 20 bytes for a 160-bit hash
    $passwordHash = [System.Convert]::ToBase64String($passwordHashBytes)

    # 4. Store user in database
    $dbFile = "pswebhost.db"
    New-PSWebSQLiteData -File $dbFile -Table "Users" -Data @{
        UserID = $userID
        Email = $Email
        Phone = $Phone
        Salt = $saltString
    }

    # 5. Store auth method in database
    New-PSWebSQLiteData -File $dbFile -Table "AuthenticationMethods" -Data @{
        UserID = $userID
        Authentication_Method = "Password"
        Data = $passwordHash
    }

    Write-Verbose "User '$Email' created with UserID '$userID'." -Verbose
    return $userID
}

function New-PSWebUser {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Email,
        [string]$UserName,
        [string]$Phone
    )

    # 1. Generate UserID
    $epoch = [int64](((Get-Date).ToUniversalTime()) - (Get-Date "1970-01-01")).TotalSeconds
    $random = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
    $toHash = "$epoch$random$Email"
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($toHash))
    $userID = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()

    # 2. Store user in database
    $dbFile = "pswebhost.db"
    New-PSWebSQLiteData -File $dbFile -Table "Users" -Data @{
        UserID = $userID
        Email = $Email
        UserName = if ($UserName) { $UserName } else { $Email }
        Phone = $Phone
    }

    Write-Verbose "User '$Email' created with UserID '$userID'." -Verbose
    return Get-PSWebHostUser -Email $Email
}

function PSWebLogon {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$ProviderName,
        [Parameter(Mandatory=$true)] [ValidateSet('Success', 'Fail','Error')] [string]$Result,
        [Parameter(Mandatory=$true)] [System.Net.HttpListenerRequest]$Request,
        [string]$UserID = "anonymous" # Default to anonymous if not provided for success
    )

    $ipAddress = $Request.RemoteEndPoint.Address.ToString()
    $sessionCookie = $Request.Cookies["PSWebSessionID"]
    $sessionID = $null
    if ($sessionCookie) { $sessionID = $sessionCookie.Value }
    $SessionData = $Global:PSWebSessions[$sessionID]
    $now = Get-Date

    # Get existing login attempt data
    $lastAttempt = Get-LastLoginAttempt -IPAddress $ipAddress

    $userViolations = [int]$lastAttempt.UserViolationsCount
    $ipViolations = [int]$lastAttempt.IPViolationCount
    $userNameLockedUntil = $lastAttempt.UserNameLockedUntil
    $ipAddressLockedUntil = $lastAttempt.IPAddressLockedUntil
    
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
        Set-LastLoginAttempt -IPAddress $ipAddress -Username $UserID -Time $now -UserNameLockedUntil $lockoutUntil -IPAddressLockedUntil $ipAddressLockedUntil -UserViolationsCount $userViolations -IPViolationCount $ipViolations
        Write-PSWebHostLog -Severity 'Warning' -Category 'Auth' -Message "Login failed for user '$UserID' from IP '$ipAddress' via '$ProviderName'. Violations: User=$userViolations, IP=$ipViolations." -Data @{ UserID = $UserID; IPAddress = $ipAddress; Provider = $ProviderName; Result = $Result }
    } else { # Success
        # Reset violation counts on success
        Set-LastLoginAttempt -IPAddress $ipAddress -Username $UserID -Time $now -UserViolationsCount 0 -IPViolationCount 0 -UserNameLockedUntil $null -IPAddressLockedUntil $null
        # Record successful login session
        if ($sessionID) {
            $logonExpires = $now.AddHours(8) # Example: Session expires in 8 hours
            Set-LoginSession -SessionID $sessionID -UserID $UserID -Provider $ProviderName -AuthenticationTime $now -LogonExpires $logonExpires
        }
        Write-PSWebHostLog -Severity 'Info' -Category 'Auth' -Message "Login successful for user '$UserID' from IP '$ipAddress' via '$ProviderName'." -Data @{ UserID = $UserID; IPAddress = $ipAddress; Provider = $ProviderName; Result = $Result }
    }
}