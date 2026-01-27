# Quick Test Guide - URL Layout Feature

## 🧪 How to Test

### Test 1: Basic URL Update (2 minutes)

1. **Open the SPA**
   ```
   http://localhost:8080/spa
   ```

2. **Watch the URL bar**
   - Initially: `http://localhost:8080/spa` (no layout parameter)

3. **Open a card** (e.g., click "System Log")
   - URL should update to: `http://localhost:8080/spa#?layout=eyJ2ZXJz...`
   - ✅ **Expected**: URL changes immediately
   - ❌ **Failure**: URL doesn't change

4. **Open browser console** (F12)
   - Look for: `[URL Layout] Updated URL with current layout`
   - Look for: `Card opened and layout URL updated`

5. **Open another card** (e.g., "File Explorer")
   - URL should update again with new layout
   - ✅ **Expected**: URL parameter changes

### Test 2: Layout Persistence (2 minutes)

1. **With 2+ cards open**, copy the current URL from address bar

2. **Open the URL in a new tab** (Ctrl+Click on address bar, copy, paste in new tab)
   - ✅ **Expected**: New tab opens with same cards in same positions
   - ❌ **Failure**: Default layout loads instead

3. **Close a card** in the new tab
   - ✅ **Expected**: URL updates to reflect removal

4. **Refresh the page** (F5)
   - ✅ **Expected**: Card stays removed (URL persisted the change)

### Test 3: Drag and Resize (3 minutes)

1. **Open 2-3 cards**

2. **Drag a card** to a new position
   - Watch console for: `[URL Layout] Updated URL with current layout`
   - ✅ **Expected**: URL updates after drag stops

3. **Resize a card** using resize handle (bottom-right corner)
   - Watch console for: `✓ Card settings saved after drag/resize, cache invalidated`
   - Watch for: URL update log message
   - ✅ **Expected**: URL updates after resize

4. **Copy the URL**

5. **Open in new tab**
   - ✅ **Expected**: Cards appear in exact same positions and sizes

### Test 4: Share Layout (1 minute)

1. **Create a custom layout**:
   - Open 3 specific cards
   - Arrange them how you like
   - Resize them

2. **Copy the URL from address bar**

3. **Send URL to another browser/user** (or open in incognito window)
   - ✅ **Expected**: Recipient sees exact same layout

### Test 5: Error Handling (2 minutes)

1. **Manually corrupt the URL layout**:
   ```
   http://localhost:8080/spa#?layout=INVALID_DATA
   ```

2. **Open the URL**
   - ✅ **Expected**: Falls back to default layout
   - ✅ **Expected**: Console shows: `[URL Layout] Invalid layout data in URL`
   - ✅ **Expected**: No crashes

3. **Check server logs**:
   ```powershell
   Get-Content "C:\SC\PsWebHost\Logs\*.log" -Tail 50 | Select-String "URLLayout"
   ```
   - Should see warning about invalid layout

## 📊 Expected Console Output

### Successful Load from URL:
```
[URL Layout] Loaded layout from URL: { cards: 2, gridItems: 2 }
Layout loaded from URL (sent to server)
[URL Layout] Applying layout from URL
[URL Layout] Applied grid positions from URL
```

### Card Opened:
```
[openCard] Adding temporary layout item: { ... }
[openCard] Applying saved card settings: { ... }
[openCard] Updated gridLayout with saved settings: [...]
[URL Layout] Updated URL with current layout
Card opened and layout URL updated (sent to server)
```

### Card Removed:
```
[URL Layout] Updated URL with current layout
Card removed and layout URL updated (sent to server)
```

### Drag/Resize:
```
handleDragOrResizeStop: ...
Saving card settings for <endpoint>: { w: 6, h: 12, x: 0, y: 0 }
✓ Card settings saved after drag/resize, cache invalidated
[URL Layout] Updated URL with current layout
```

## 🐛 Troubleshooting

### Issue: URL Doesn't Update

**Check:**
1. Browser console for errors
2. Make sure `window.logToServer` function exists
3. Verify `data.layout.mainPane.content` is not null

**Debug:**
```javascript
// In browser console:
console.log(window.location.search);  // Should show ?layout=...
console.log(data.layout);  // Should have mainPane.content array
```

### Issue: Layout Not Loading from URL

**Check:**
1. URL parameter is correctly formatted
2. Console for `[URL Layout]` messages
3. Server logs for errors

**Debug:**
```javascript
// In browser console, after page loads:
const params = new URLSearchParams(window.location.search);
console.log(params.get('layout'));  // Should show compressed layout

// Try manual decompression:
const compressed = params.get('layout');
const decoded = atob(compressed);
console.log(decoded);  // Should show JSON
```

### Issue: Cards Missing After Load

**Possible Causes:**
1. Card IDs in URL don't match available components
2. Card components failed to load
3. Permission issues

**Check:**
1. Browser console for component load errors
2. Network tab for failed requests
3. Server logs for authentication errors

## 📝 Success Criteria

All these should work:

- [x] URL updates when card is opened
- [x] URL updates when card is closed
- [x] URL updates when card is moved
- [x] URL updates when card is resized
- [x] Opening URL with layout parameter loads that layout
- [x] Layout persists across page refresh
- [x] Invalid layout parameter falls back gracefully
- [x] Server logs show URL layout events
- [x] URL is shareable between users
- [x] No JavaScript errors in console

## 🎯 Real-World Test Scenario

**Scenario:** Create a "System Monitoring" layout

1. **Open these cards**:
   - System Log
   - Memory Histogram
   - Real-time Events
   - Task Manager

2. **Arrange them**:
   - System Log: Top-left, wide
   - Memory Histogram: Top-right
   - Real-time Events: Bottom-left
   - Task Manager: Bottom-right

3. **Resize**:
   - Make System Log take 8 columns wide
   - Make Memory Histogram 4 columns wide
   - Adjust heights to fit your screen

4. **Copy URL** from address bar

5. **Test**:
   - Open URL in new tab → Should see exact layout
   - Send URL to colleague → They see same layout
   - Bookmark URL → Quick access to monitoring dashboard

6. **Verify Logging**:
   ```powershell
   # Check that events were logged
   Get-Content "C:\SC\PsWebHost\Logs\*.log" -Tail 100 |
     Select-String "URLLayout" |
     Format-Table -AutoSize
   ```

## 🚀 Next Steps

After testing:
1. ✅ Verify all tests pass
2. 📝 Document any issues found
3. 🎨 Consider creating preset layouts for common use cases
4. 📊 Monitor URL lengths for large layouts
5. 💡 Gather user feedback on feature usability

## 💡 Tips

- **Bookmark Layouts**: Create bookmarks for different work contexts
- **Share Dashboards**: Send layout URLs to team members
- **Quick Switching**: Keep multiple layout URLs in a document for fast switching
- **Layout Library**: Consider creating a wiki page with useful layout URLs
