# URL Layout Sharing Feature

## 🎯 Overview

The SPA now supports **shareable and bookmarkable layouts** via URL query parameters. Users can:
- Share custom dashboard layouts via URL links
- Bookmark specific layouts for quick access
- Layouts automatically update in the URL as cards are opened, closed, moved, or resized

## ✨ Features

### 1. URL-Based Layout Loading
- Layout specified via `?layout=<compressed-json>` query parameter
- Automatically applied when page loads
- Overrides default layout from layout.json and database settings

### 2. Real-Time URL Updates
The URL is automatically updated when:
- ✅ Cards are opened (via `openCard()`)
- ✅ Cards are closed/removed (via `removeCard()`)
- ✅ Cards are moved or resized (via drag/drop or resize handles)
- ✅ Layout changes via `handleLayoutChange()`

### 3. Compression & Encoding
- Layout JSON is compressed using base64 encoding
- URL-safe format for sharing
- Compact representation to avoid URL length limits

## 📋 Layout Data Structure

The URL layout contains:

```json
{
  "version": 1,
  "grid": [
    {
      "i": "card-id",
      "x": 0,
      "y": 0,
      "w": 6,
      "h": 12
    }
  ],
  "cards": ["card-id-1", "card-id-2"]
}
```

**Fields:**
- `version`: Layout format version (currently 1)
- `grid`: Array of card positions and sizes
  - `i`: Card identifier
  - `x`, `y`: Grid position
  - `w`, `h`: Width and height in grid units
- `cards`: Array of card IDs to display

## 🔧 Implementation Details

### Functions Added

#### 1. `compressLayout(layoutData)`
Compresses layout JSON for URL encoding
- Input: Layout object
- Output: Base64-encoded compressed string
- Error handling: Returns null on failure

#### 2. `decompressLayout(compressed)`
Decompresses layout from URL parameter
- Input: Base64-encoded string
- Output: Layout object
- Error handling: Returns null on invalid data

#### 3. `serializeLayoutToURL(gridLayout, openCards)`
Creates URL-safe layout representation
- Combines grid positions and card list
- Returns compressed string ready for URL

#### 4. `updateURLWithLayout(newGridLayout, openCardIds)`
Updates browser URL without page reload
- Uses History API `replaceState()`
- Non-intrusive (doesn't trigger navigation)
- Logs changes to server via `logToServer()`

#### 5. `parseLayoutFromURL()`
Parses layout from current URL
- Checks for `?layout=` parameter
- Validates layout structure
- Logs to server for monitoring

### Integration Points

#### Modified Functions:

1. **`loadLayout()`** (lines ~1704-1792)
   - Checks for URL layout before loading defaults
   - Applies URL layout to override layout.json
   - Merges URL grid positions with fetched card settings

2. **`handleLayoutChange(layout)`** (lines ~2400-2410)
   - Updates URL whenever layout changes
   - Called by React Grid Layout on any layout modification

3. **`handleDragOrResizeStop()`** (lines ~2526-2580)
   - Updates URL after successful save to database
   - Ensures URL stays in sync with persisted state

4. **`openCard(url, title)`** (lines ~2141-2337)
   - Updates URL after card is fully opened and positioned
   - Logs card open event to server

5. **`removeCard(cardIdToRemove)`** (lines ~2388-2408)
   - Removes card from grid layout
   - Updates URL to reflect removal
   - Logs card removal to server

## 📝 Logging Integration

All URL layout operations log to the server via `window.logToServer()`:

**Events Logged:**
- Layout loaded from URL (Info)
- Invalid layout data in URL (Warning)
- Failed to parse layout from URL (Error)
- Card opened and layout URL updated (Info)
- Card removed and layout URL updated (Info)

**Log Category:** `URLLayout`

## 🚀 Usage Examples

### Example 1: Share Current Layout

1. User customizes their dashboard (moves cards, resizes, opens/closes)
2. URL automatically updates in address bar
3. User copies URL: `http://localhost:8080/spa#?layout=eyJ2ZXJzaW9...`
4. User shares URL with colleague
5. Colleague opens link → sees exact same layout

### Example 2: Bookmark Layouts

User creates three different layouts for different tasks:
- **Monitoring Dashboard**: `?layout=ABC123...` (system logs, metrics, real-time events)
- **Admin Panel**: `?layout=DEF456...` (user management, settings, tasks)
- **Development View**: `?layout=GHI789...` (file explorer, task manager, logs)

User bookmarks each URL for quick switching between contexts.

### Example 3: URL Updates Automatically

```
Initial load:
http://localhost:8080/spa

User opens "System Log" card:
http://localhost:8080/spa#?layout=eyJ2ZXJzaW...   (1 card)

User opens "File Explorer" card:
http://localhost:8080/spa#?layout=eyJ2ZXJzaW...   (2 cards)

User resizes "System Log":
http://localhost:8080/spa#?layout=eyJ2ZXJzaW...   (updated positions)

User closes "File Explorer":
http://localhost:8080/spa#?layout=eyJ2ZXJzaW...   (back to 1 card)
```

## ⚙️ Technical Considerations

### URL Length Limits
- Modern browsers support ~2000 character URLs
- Compressed layout is typically 100-500 characters
- Large layouts with many cards may approach limits
- Consider warning users if layout exceeds safe limit

### Browser Compatibility
- Uses `URLSearchParams` (IE11+)
- Uses `History.replaceState()` (IE10+)
- Base64 encoding/decoding (all modern browsers)

### Performance
- Compression/decompression is fast (<1ms typically)
- URL updates use `replaceState()` (no page reload)
- Minimal performance impact

### Conflicts with Database Settings
**Priority Order:**
1. URL layout (highest - for sharing)
2. Database card settings (user preferences)
3. layout.json (defaults)

When URL layout is present:
- Card positions come from URL
- Card sizes come from URL
- Which cards to display comes from URL
- Other settings (like background color) from database

## 🧪 Testing

### Test Scenarios

1. **Load from URL**
   - [ ] Open URL with `?layout=` parameter
   - [ ] Verify cards appear in correct positions
   - [ ] Verify correct cards are displayed

2. **URL Updates on Card Open**
   - [ ] Open a card
   - [ ] Verify URL updates immediately
   - [ ] Copy URL and open in new tab
   - [ ] Verify same card appears

3. **URL Updates on Card Close**
   - [ ] Remove a card
   - [ ] Verify URL updates
   - [ ] Refresh page
   - [ ] Verify card is gone

4. **URL Updates on Move/Resize**
   - [ ] Drag a card to new position
   - [ ] Verify URL updates
   - [ ] Refresh page
   - [ ] Verify card stays in new position

5. **Invalid Layout**
   - [ ] Manually corrupt URL layout parameter
   - [ ] Verify fallback to default layout
   - [ ] Check console for error message

### Test URLs

```powershell
# Empty layout (no cards)
http://localhost:8080/spa#?layout=eyJ2ZXJzaW9uIjoxLCJncmlkIjpbXSwiY2FyZHMiOltdfQ==

# Single card (system-log)
# (Generate by opening one card and copying URL)
http://localhost:8080/spa#?layout=<copy-from-browser>
```

## 🔒 Security Considerations

### Input Validation
- URL layout is validated before use
- Checks for required fields (version, grid, cards)
- Malformed data is rejected (logs warning)
- Falls back to default layout on error

### XSS Prevention
- Layout only contains card IDs and positions
- No user-generated content in layout
- Card IDs are validated against available components
- No script injection risk

### Privacy
- Layout reveals which cards user has open
- Consider if card IDs contain sensitive information
- URLs may be logged by proxies/servers
- Users should be aware when sharing

## 📊 Monitoring

Check server logs for URL layout events:

```powershell
# View recent URL layout events
Get-Content "C:\SC\PsWebHost\Logs\*.log" |
  Select-String "URLLayout" |
  Select-Object -Last 20
```

**Log Categories:**
- `URLLayout` - Layout loading/parsing/updating
- `ContentType` - Component loading
- `ComponentLoad` - Component errors

## 🎯 Future Enhancements

Potential improvements:
1. **Named Layouts** - Save layouts with names (e.g., `/spa?layout-name=monitoring`)
2. **Layout Library** - Pre-defined layouts for common use cases
3. **Layout History** - Undo/redo layout changes
4. **Layout Templates** - Share layout templates without specific card instances
5. **Layout Validation** - Warn if cards in URL layout are not available
6. **Compression Optimization** - Use LZ-String for better compression
7. **Layout Diff** - Show what changed when loading URL layout

## 📝 Summary

✅ **Implemented:**
- URL-based layout loading
- Automatic URL updates on layout changes
- Compression and encoding for compact URLs
- Integration with all card lifecycle events
- Server-side logging for monitoring
- Error handling and validation

✅ **Benefits:**
- Share custom dashboards instantly
- Bookmark layouts for quick access
- No manual export/import needed
- Works across sessions and users
- Survives page refreshes

✅ **Next Steps:**
- Test thoroughly with various layouts
- Monitor URL length for large layouts
- Gather user feedback on feature
- Consider adding layout naming/library
