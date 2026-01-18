# Card Error Display Implementation

**Date:** 2026-01-17
**Status:** ✅ Implemented

---

## Overview

When a card loads but the endpoint returns a non-200 HTTP status code, the error details are now displayed directly in the card instead of just failing silently or logging to console.

---

## What Changed

### 1. Enhanced Error Capture in `loadComponentScript()`

**File:** `public/psweb_spa.js` (lines 1200-1337)

**Changes:**
- Function now returns a result object: `{ success: boolean, error?: object }`
- When endpoint returns non-200 status:
  - Captures HTTP status code and status text
  - Reads and stores the response body
  - Creates detailed error object
  - Logs to server for diagnostics
  - Returns error info instead of just resolving

**Error Object Structure:**
```javascript
{
    status: 404,              // HTTP status code
    statusText: 'Not Found',  // HTTP status text
    message: 'HTTP 404: Not Found',
    body: 'Detailed error message from server',
    url: '/api/v1/ui/elements/my-component'
}
```

**Handles Multiple Error Scenarios:**
- **HTTP errors** (non-200 status codes) - Shows status, message, and response body
- **Network errors** - Shows connection failure details
- **Missing component path** - Shows configuration error
- **Script load failures** - Shows JavaScript execution errors

### 2. Error Propagation in `openCard()`

**File:** `public/psweb_spa.js` (lines 1339-1375)

**Changes:**
- Captures the result from `loadComponentScript()`
- Includes error information in the element properties:
  ```javascript
  const newElement = {
      Title: title,
      Element_Id: elementId,
      url: elementUrl,
      id: cardId,
      backgroundColor: cardSettings?.backgroundColor,
      loadError: loadResult.success ? null : loadResult.error  // NEW
  };
  ```

### 3. Error Display in Card Component

**File:** `public/psweb_spa.js` (lines 805-856)

**Changes:**
- Checks for `element.loadError` before rendering component
- If error present, displays formatted error message instead of component
- Provides expandable details section for response body

**Error Display Features:**
- ⚠️ Clear visual indicator (warning icon and yellow background)
- **Status Code** - Prominently displayed (e.g., "404 Not Found")
- **URL** - Shows the failing endpoint
- **Message** - Clear error description
- **Response Body** - Expandable `<details>` section for server response

---

## User Experience

### Before

When an endpoint returned a 404 or 500 error:
- ❌ Card showed "Loading component..." indefinitely
- ❌ Error only visible in browser console
- ❌ No indication to user what went wrong
- ❌ Had to open DevTools to diagnose

### After

When an endpoint returns a non-200 status:
- ✅ Card displays clear error message
- ✅ Shows HTTP status code and description
- ✅ Shows the failing URL
- ✅ Shows server response body (if available)
- ✅ All information visible in the card itself
- ✅ Error also logged to server for diagnostics

---

## Example Error Displays

**Note:** The error display automatically adapts colors based on your theme. The examples below show the content structure - colors will vary based on dark/light theme detection.

### HTTP 404 Not Found

**Dark Theme:** Orange border with amber text on semi-transparent dark background
**Light Theme:** Amber border with brown text on light yellow background

```
⚠️ Failed to Load Component

Status: 404 Not Found
URL: /apps/MyApp/api/v1/ui/elements/my-component
Message:
  HTTP 404: Not Found

Response Body:
  {
    "error": "Component 'my-component' not found",
    "availableComponents": ["other-component", "another-component"]
  }
```

### HTTP 500 Internal Server Error

**Dark Theme:** Bright orange border, light text that contrasts with dark background
**Light Theme:** Traditional amber/yellow warning colors

```
⚠️ Failed to Load Component

Status: 500 Internal Server Error
URL: /apps/MyApp/api/v1/ui/elements/broken-component
Message:
  HTTP 500: Internal Server Error

Response Body:
  Error in endpoint /apps/MyApp/api/v1/ui/elements/broken-component:
  Cannot read property 'foo' of undefined
  at line 42 in get.ps1
```

### Network Error

**Dark Theme:** Semi-transparent amber background with theme text color
**Light Theme:** Light yellow background with dark text

```
⚠️ Failed to Load Component

Status: 0 Network Error
URL: /api/v1/ui/elements/my-component
Message:
  Failed to fetch: NetworkError when attempting to fetch resource
```

### Missing Component Path

```
⚠️ Failed to Load Component

Status: 404 Not Found
URL: /api/v1/ui/elements/my-component
Message:
  No component path found for my-component. Component paths must be
  explicitly specified via:
    1. componentPath in layout.json, OR
    2. scriptPath in /api/v1/ui/elements/my-component endpoint response
```

### Dark Theme Example

When using dark themes like:
```css
:root {
  --card-bg-color: #2a2a2a;
  --text-color: #f0f0f0;
}
```

The error display will use:
- **Orange/amber tones** that stand out against dark backgrounds
- **Semi-transparent backgrounds** that blend with the theme
- **Light text colors** from CSS variables for readability
- **Increased border thickness** (2px) for visibility

### Light Theme Example

When using light themes (default or custom):
```css
:root {
  --card-bg-color: #ffffff;
  --text-color: #333;
}
```

The error display will use:
- **Traditional warning colors** (yellow/amber)
- **Dark text** on light backgrounds
- **Professional warning appearance** similar to standard alert boxes

---

## Styling

The error display uses a **theme-aware** design that automatically adapts to dark and light themes:

### Theme Detection

The error display automatically detects the current theme by:
1. Checking the card's background color (if set via card settings)
2. Reading CSS variables (like `--card-bg-color`)
3. Calculating luminance using WCAG formula
4. Determining if theme is dark (luminance < 0.5) or light (luminance >= 0.5)

### Dark Theme Colors

When using dark themes (e.g., `--card-bg-color: #2a2a2a`):

- **Container Background:** `rgba(255, 152, 0, 0.15)` - Semi-transparent amber
- **Border:** `#ff9800` - Bright orange (2px solid)
- **Heading Color:** `#ffb74d` - Light amber
- **Text Color:** Uses `--text-color` CSS variable (fallback: `#f0f0f0`)
- **Code Background:** `rgba(0, 0, 0, 0.3)` - Semi-transparent black
- **Code Border:** `rgba(255, 152, 0, 0.3)` - Semi-transparent orange
- **Font:** Monospace for URLs and technical details

### Light Theme Colors

When using light themes (e.g., default white background):

- **Container Background:** `#fff3cd` - Light yellow
- **Border:** `#ffc107` - Amber (2px solid)
- **Heading Color:** `#856404` - Dark brown
- **Text Color:** `#333` - Dark gray
- **Code Background:** `#f8f9fa` - Light gray
- **Code Border:** `#dee2e6` - Light gray
- **Font:** Monospace for URLs and technical details

### Response Body Styling

- Always visible (not collapsible) when present
- Pre-formatted text with scroll
- Max height 400px to prevent overwhelming the card
- Consistent styling with theme colors

---

## Server-Side Logging

All errors are automatically logged to the server via `window.logToServer()`:

```javascript
window.logToServer('Error', 'ComponentLoad',
    `Endpoint ${endpointUrl} returned ${metadataRes.status}`,
    {
        elementId: elementId,
        status: metadataRes.status,
        statusText: metadataRes.statusText,
        body: errorBody
    }
);
```

This enables:
- Server-side error tracking
- Debugging without browser access
- Historical error analysis
- Pattern detection

---

## Testing

### Test Scenario 1: 404 Endpoint

1. Create a menu item pointing to non-existent endpoint:
   ```yaml
   - Name: Test 404
     url: /api/v1/ui/elements/does-not-exist
   ```

2. Click the menu item
3. **Expected:** Card opens with error display showing 404 status

### Test Scenario 2: 500 Server Error

1. Create an endpoint that throws an error:
   ```powershell
   # get.ps1
   throw "Simulated error"
   ```

2. Click menu item for that endpoint
3. **Expected:** Card shows 500 error with exception details

### Test Scenario 3: Network Failure

1. Stop the PSWebHost server
2. Try to open a card
3. **Expected:** Card shows network error message

### Test Scenario 4: Missing scriptPath

1. Create endpoint that doesn't return `scriptPath`:
   ```powershell
   @{
       component = 'test'
       # Missing scriptPath field
   } | ConvertTo-Json
   ```

2. Click menu item
3. **Expected:** Card shows "No component path found" error

---

## Benefits

### For Users
- **Clear Feedback** - Immediately see what went wrong
- **Actionable Information** - Error details help understand the issue
- **No DevTools Required** - All info visible in the UI
- **Professional UX** - Graceful error handling

### For Developers
- **Faster Debugging** - Error details displayed prominently
- **Server Logs** - Errors automatically logged for analysis
- **Response Body** - See exact server response
- **URL Context** - Know which endpoint failed

### For Administrators
- **Error Tracking** - Server logs capture all component load failures
- **Pattern Detection** - Identify commonly failing endpoints
- **Diagnostics** - Full error context for troubleshooting
- **User Reports** - Users can describe errors they see

---

## Backwards Compatibility

✅ **Fully backwards compatible**

- Existing components continue to work normally
- Error display only activates when loading fails
- No changes required to existing endpoints or components
- Error handling is additive, not breaking

---

## Future Enhancements

### Possible Improvements

1. **Retry Button**
   - Add "Retry" button to error display
   - Attempt to reload the component
   - Useful for transient network errors

2. **Error Reporting**
   - "Report Error" button
   - Automatically create issue with error details
   - Include browser info, timestamp, session

3. **Fallback Components**
   - Define fallback component per endpoint
   - Show alternative UI when primary fails
   - Graceful degradation

4. **Error Theming**
   - Respect dark/light theme settings
   - Configurable error colors
   - Custom error templates

5. **Analytics Integration**
   - Track error rates per component
   - Alert on error spikes
   - Dashboard for component health

---

## Code Example: Custom Error Response

Endpoints can now provide rich error information:

```powershell
# routes/api/v1/ui/elements/my-component/get.ps1

param($Context, $Request, $Response)

try {
    # Validate prerequisites
    if (-not (Test-DatabaseConnection)) {
        $Response.StatusCode = 503
        $Response.ContentType = "application/json"

        $errorResponse = @{
            error = "Service Unavailable"
            message = "Database connection failed. Please contact administrator."
            details = @{
                database = $dbPath
                lastError = $Global:LastDbError
            }
            helpUrl = "https://docs.example.com/troubleshooting#db-connection"
        } | ConvertTo-Json

        $buffer = [System.Text.Encoding]::UTF8.GetBytes($errorResponse)
        $Response.OutputStream.Write($buffer, 0, $buffer.Length)
        $Response.Close()
        return
    }

    # Normal response
    $componentInfo = @{
        component = 'my-component'
        scriptPath = '/apps/MyApp/public/elements/my-component/component.js'
        title = 'My Component'
    }

    context_response -Response $Response -String ($componentInfo | ConvertTo-Json) -ContentType "application/json"

} catch {
    # Internal error
    $Response.StatusCode = 500
    $Response.ContentType = "application/json"

    $errorResponse = @{
        error = "Internal Server Error"
        message = $_.Exception.Message
        stackTrace = $_.ScriptStackTrace
    } | ConvertTo-Json

    $buffer = [System.Text.Encoding]::UTF8.GetBytes($errorResponse)
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.Close()
}
```

The error response will be automatically displayed in the card with all details visible to the user.

---

## Summary

✅ **Implemented comprehensive error display for card loading failures**

**Key Features:**
- Captures HTTP errors, network errors, and configuration errors
- Displays detailed error information in the card
- Shows status code, URL, message, and response body
- Logs all errors to server for diagnostics
- **Theme-aware colors** that automatically adapt to dark/light themes
- Uses WCAG luminance calculation to detect theme type
- Respects CSS variables (e.g., `--text-color`, `--card-bg-color`)
- Fully backwards compatible
- Clear, professional error UI

**Impact:**
- Better user experience during errors
- Consistent appearance with your theme (dark or light)
- Excellent visibility in both dark and light environments
- Faster debugging for developers
- Better diagnostics for administrators
- Professional error handling throughout the application

---

**Last Updated:** 2026-01-17
**Author:** PSWebHost Development Team
**Status:** ✅ Production Ready
