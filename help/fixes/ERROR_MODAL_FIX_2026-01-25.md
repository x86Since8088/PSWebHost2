# Error Modal Demo Fix - 2026-01-25

## Problem

The "Test Error Modals" page (`/public/error-modal-demo.html`) was throwing a JavaScript error:

```
Uncaught TypeError: window.showErrorModal is not a function
    showAdminModal http://localhost:8080/public/error-modal-demo.html:237
```

## Root Cause

The `psweb_spa.js` file contains **JSX syntax** (React components written with XML-like tags) which browsers cannot parse directly. When a browser tries to execute raw JSX, it encounters a syntax error and stops processing the entire file, preventing `window.showErrorModal` from being defined.

### Technical Details

1. **JSX Syntax in psweb_spa.js**: The file contains components like:
   ```javascript
   const IFrameComponent = ({ element }) => {
       return <iframe src={element.url} style={{...}} />;
   };
   ```

2. **Babel Requirement**: JSX must be transpiled to `React.createElement()` calls before browsers can execute it.

3. **Missing Babel**: The error-modal-demo.html page was loading psweb_spa.js as a regular script:
   ```html
   <script src="/public/psweb_spa.js"></script>  <!-- WRONG -->
   ```

4. **Correct Method**: The spa-shell.html page properly loads Babel and marks the script as needing transpilation:
   ```html
   <script src="/public/lib/babel.min.js"></script>
   <script type="text/babel" src="/public/psweb_spa.js"></script>  <!-- CORRECT -->
   ```

## Solution

Updated the following files to load Babel before psweb_spa.js:

### 1. `/public/error-modal-demo.html`
```html
<!-- Load Babel for JSX transpilation -->
<script src="/public/lib/babel.min.js"></script>

<!-- Load the error modal system from the SPA (requires Babel for JSX) -->
<script type="text/babel" src="/public/psweb_spa.js"></script>
```

### 2. `/public/test-error-modal-simple.html`
Same fix applied to the diagnostic test page.

### 3. `/public/psweb_spa.js` - IFrameComponent
Converted the IFrameComponent to use `React.createElement()` instead of JSX as a defensive measure:
```javascript
const IFrameComponent = ({ element }) => {
    return React.createElement('iframe', {
        src: element.url,
        style: { width: '100%', height: '100%', border: 'none' }
    });
};
```

This makes it compatible with both Babel and non-Babel environments.

## Testing

After the fix:

1. Navigate to `http://localhost:8080/public/error-modal-demo.html`
2. Click "Show Admin Error Modal"
3. Verify the modal appears with full error details
4. Click "Show Basic Error Modal"
5. Verify the modal appears with basic error info
6. Click "Show Minimal Error Modal"
7. Verify the modal appears with minimal message

All three test buttons should now work correctly.

## Best Practices Going Forward

**When creating new HTML pages that use `psweb_spa.js`:**

1. Always load React libraries first:
   ```html
   <script src="/public/lib/react.development.js"></script>
   <script src="/public/lib/react-dom.development.js"></script>
   ```

2. Load Babel for JSX transpilation:
   ```html
   <script src="/public/lib/babel.min.js"></script>
   ```

3. Load psweb_spa.js with `type="text/babel"`:
   ```html
   <script type="text/babel" src="/public/psweb_spa.js"></script>
   ```

**Example Template:**
```html
<!DOCTYPE html>
<html>
<head>
    <title>My Page</title>
    <!-- React -->
    <script src="/public/lib/react.development.js"></script>
    <script src="/public/lib/react-dom.development.js"></script>
    <!-- Babel for JSX -->
    <script src="/public/lib/babel.min.js"></script>
</head>
<body>
    <div id="app"></div>

    <!-- Load PSWebHost SPA with Babel -->
    <script type="text/babel" src="/public/psweb_spa.js"></script>

    <!-- Your custom code -->
    <script type="text/babel">
        // Your JSX code here
    </script>
</body>
</html>
```

## Files Modified

- `/public/error-modal-demo.html` - Added Babel loading
- `/public/test-error-modal-simple.html` - Added Babel loading
- `/public/psweb_spa.js` - Converted IFrameComponent to React.createElement

## Related Files

- `/public/spa-shell.html` - Reference implementation showing correct Babel usage
- `/public/lib/babel.min.js` - Babel standalone transpiler
- `/public/psweb_spa.js` - Main SPA JavaScript file with JSX components
