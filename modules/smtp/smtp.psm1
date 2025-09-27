function Send-SmtpEmail {
    [cmdletbinding()]
    param(
        [string[]]$To,
        [string]$Subject,
        [string]$Body
    )
    if (-not $To) { Write-Error "The -To parameter is required."; return }
    if (-not $Subject) { Write-Error "The -Subject parameter is required."; return }
    if (-not $Body) { Write-Error "The -Body parameter is required."; return }

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13;

    Write-Verbose "Attempting to send email to: $($To -join ', ')"

    # Get SMTP settings from the global config
    $smtpSettings = $Global:PSWebServer.Config.Smtp
    if (-not $smtpSettings) {
        Write-Error "SMTP settings are not configured in config/settings.json"
        return
    }
    Write-Verbose "SMTP settings loaded from config."

    $smtpServer = $smtpSettings.Server
    $smtpPort = $smtpSettings.Port
    $fromAddress = $smtpSettings.FromAddress
    $username = $smtpSettings.Username
    
    # Check for the secure password string
    if (-not [string]::IsNullOrEmpty($smtpSettings.PasswordSecureString)) {
        $securePassword = $smtpSettings.PasswordSecureString | ConvertTo-SecureString
    } else {
        Write-Error "SMTP password is not configured correctly in config/settings.json."
        return
    }
    
    # Create credential object
    $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)
    Write-Verbose "SMTP credential created for user '$username'."

    # Send the email
    try {
        Write-Verbose "Sending email with the following parameters:"
        Write-Verbose "  - To: $($To -join ', ')"
        Write-Verbose "  - From: $fromAddress"
        Write-Verbose "  - Subject: $Subject"
        Write-Verbose "  - SmtpServer: $smtpServer"
        Write-Verbose "  - Port: $smtpPort"
        
        Send-MailMessage -To $To -From $fromAddress -Subject $Subject -Body $Body -SmtpServer $smtpServer -Port $smtpPort -UseSsl -Credential $credential
        
        Write-Verbose "Email sent successfully to $($To -join ', ')"
    } catch [System.Net.Mail.SmtpException] {
        Write-Verbose "Encountered an SmtpException while sending email."
        $errorMessage = "Failed to send email. SMTP Error: $($_.Exception.Message)"
        $statusCode = $_.Exception.StatusCode
        
        if ($statusCode -eq 'MailboxUnavailable' -or $statusCode -eq 'MailboxBusy' -or $statusCode -eq 'TransactionFailed') {
            $errorMessage += " This might be a temporary issue with the recipient's mailbox."
        }
        elseif ($statusCode -eq 'GeneralFailure' -or $statusCode -eq 'ServiceNotAvailable') {
            $errorMessage += " The SMTP service might be unavailable. Check the server address and port."
        }
        elseif ($_.Exception.Message -like '*Authentication unsuccessful*') {
            $errorMessage += " This is an authentication failure. Please check the following:"
            $errorMessage += " 1. The username and password in config/settings.json are correct."
            $errorMessage += " 2. If using MFA, an App Password may be required."
            $errorMessage += " 3. The email account may have SMTP AUTH disabled by an administrator."
        }
        
        Write-Error $errorMessage
    } catch {
        Write-Verbose "Encountered a general error while sending email."
        Write-Error "Failed to send email with an unexpected error: $_"
    }
}