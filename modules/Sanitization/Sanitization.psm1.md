# Sanitization.psm1

This PowerShell module provides essential functions for sanitizing user-provided input to prevent common web security vulnerabilities.

## Functions

### Sanitize-HtmlInput

This function is used to mitigate Cross-Site Scripting (XSS) attacks and to remove potentially harmful ANSI escape sequences. It takes a string as input, removes any ANSI escape codes, and then encodes the result using `[System.Web.HttpUtility]::HtmlEncode`, which converts characters like `<` and `>` into their HTML-safe equivalents (e.g., `&lt;` and `&gt;`).

### Sanitize-FilePath

This is a critical security function designed to prevent path traversal (also known as "directory traversal") attacks. Its goal is to ensure that a file path provided by a user does not access unintended files or directories outside of a restricted base directory.

**Workflow**:
1.  It checks for simple path traversal sequences (e.g., `..` or `../`).
2.  It combines the provided path with the specified `$BaseDirectory`.
3.  It resolves the absolute, canonical path (e.g., converting `c:\temp\..\windows` to `c:\windows`).
4.  It performs a final check to confirm that the fully resolved path still starts with the intended base directory.
5.  It returns a hashtable with a `Score` of `pass` or `fail` and either the sanitized path or an error message.

### Write-RequestSanitizationFail

This is a helper function used by `Sanitize-FilePath` to log detailed information when a sanitization check fails. It records the attempted path, an error message, and a full call stack to aid in security analysis and debugging.

