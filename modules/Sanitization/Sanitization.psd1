@{
    ModuleVersion = '0.0.1'
    GUID = 'a2b3c4d5-e6f7-8901-2345-67890abcdef1'
    Author = 'Edward Skarke III'
    CompanyName = 'Self'
    Copyright = '(c) 2025 Edward Skarke III. All rights reserved.'
    Description = 'Functions for sanitizing input and file paths.'
    FunctionsToExport = @(
        'Sanitize-HtmlInput',
        'Write-RequestSanitizationFail',
        'Sanitize-FilePath'
    )
    RootModule = 'Sanitization.psm1'
    RequiredModules = @()
}