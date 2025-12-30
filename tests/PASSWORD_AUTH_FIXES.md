# Password Authentication Fixes

## Issues Identified

1. **No validation error logging** - The password POST route didn't log validation failures
2. **Incorrect HTTP status code** - Used 400 instead of 422 for validation errors
3. **Poor error message formatting** - Plain text errors instead of HTML-formatted messages
4. **Missing state parameter** - Login form didn't pass `state` query parameter to POST endpoint
5. **Nested HTML tags** - JavaScript wrapped already-formatted HTML error messages

## Changes Made

### 1. routes/api/v1/authprovider/password/post.ps1

**Added:**
- `$MyTag` variable for consistent logging
- Logging of incoming POST requests
- HTML formatting for error messages (`<p class="error">...</p>`)
- Validation failure logging with details
- Changed status code from 400 to 422 for validation errors

**Before:**
```powershell
if ([string]::IsNullOrEmpty($email)) {
    $fail+='Email is required.'
}
```

**After:**
```powershell
if ([string]::IsNullOrEmpty($email)) {
    $fail+='<p class="error">Email is required.</p>'
}
```

### 2. routes/api/v1/authprovider/password/login.html

**Fixed error display:**
- Changed to use `result.Message` (capital M) to match server response
- Removed wrapping of already-formatted HTML errors in additional `<p>` tags
- Errors now display with proper HTML formatting

**Added state parameter:**
- Extract `state` from URL query parameters
- Include `state` and `RedirectTo` in POST URL query string
- Maintains authentication flow state properly

**Before:**
```javascript
const response = await fetch('/api/v1/authprovider/password', {
    method: 'POST',
    ...
});
```

**After:**
```javascript
let postUrl = '/api/v1/authprovider/password';
const queryParams = new URLSearchParams();
if (state) queryParams.append('state', state);
if (redirectTo) queryParams.append('RedirectTo', redirectTo);
if (queryParams.toString()) {
    postUrl += '?' + queryParams.toString();
}

const response = await fetch(postUrl, {
    method: 'POST',
    ...
});
```

### 3. modules/PSWebHost_Authentication/PSWebHost_Authentication.psm1

**Fixed typo:**
- Line 119: `writre-verbose` → `Write-Verbose`

## Password Requirements

The default password validation requires:
- Minimum 8 characters
- At least 2 uppercase letters
- At least 2 lowercase letters
- At least 2 numbers
- At least 2 symbols from: `!@#$%^&*()_+-=[]{};':"\\|,.<>/?~`

**Example valid password:** `TestPassword12!@`

## Testing

1. **Create a test user:**
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\sc\PsWebHost\tests\Create-PasswordUser.ps1"
   ```

2. **Test validation errors:**
   - Navigate to: `http://localhost:8080/api/v1/authprovider/password/login.html`
   - Try invalid password: `TestPassword!` (missing numbers)
   - Should see: "Password must contain at least 2 numbers."

3. **Test successful login:**
   - Email: `test@localhost`
   - Password: `TestPassword12!@`
   - Should redirect to spa after successful authentication

## Benefits

1. **Better UX** - Users see specific validation errors instead of generic "400 Bad Request"
2. **Easier debugging** - Validation failures are logged with details
3. **Proper HTTP semantics** - 422 status code indicates validation error
4. **Consistent with Windows auth** - Both routes now handle errors the same way
5. **Maintains state** - Authentication flow state is preserved through redirects
