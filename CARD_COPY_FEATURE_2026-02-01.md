# Card Copy Feature

**Date:** 2026-02-01
**Feature:** Open multiple copies of the same card with unique identifiers

---

## Overview

Added `window.openCardCopy()` function to allow users to intentionally open multiple instances of the same card, each with a unique identifier.

This complements the duplicate prevention in `window.openCard()`:
- **openCard** - Opens first instance or scrolls to existing (prevents duplicates)
- **openCardCopy** - Always opens a new copy with unique ID (allows intentional duplicates)

---

## User Interface

### Main Menu Card Controls

When a card is **closed**:
```
[+]  Card Name
```
- Click **+** → Opens first instance

When a card is **open**:
```
[+] [×]  Card Name
```
- Click **+** → Opens new copy
- Click **×** → Closes existing card

---

## Copy Numbering System

Copies are numbered sequentially starting from 2:

| Card State | Card ID | Title |
|------------|---------|-------|
| Original | `debug-variables-1770011505644` | "Debug Variables" |
| Copy 2 | `debug-variables-copy-2` | "Debug Variables (Copy 2)" |
| Copy 3 | `debug-variables-copy-3` | "Debug Variables (Copy 3)" |
| Copy 4 | `debug-variables-copy-4` | "Debug Variables (Copy 4)" |

**Copy number determination:**
1. Scans all open cards for same `elementId`
2. Finds highest existing copy number
3. Creates new copy with `copyNumber + 1`
4. Handles gaps intelligently (if copy-2 is closed, next copy is still copy-4)

---

## API

### window.openCardCopy(url, title)

**Purpose:** Opens a new copy of a card, even if one is already open

**Parameters:**
- `url` (string) - Card endpoint URL (e.g., `/apps/WebHostDebugVariables/cards/debug-variables`)
- `title` (string) - Card display title (e.g., "Debug Variables")

**Returns:** void

**Example:**
```javascript
// Open a copy of the debug variables card
window.openCardCopy(
    '/apps/WebHostDebugVariables/cards/debug-variables',
    'Debug Variables'
);
```

**Behavior:**
1. Extracts `elementId` from URL
2. Finds all existing cards with same `elementId`
3. Determines next copy number
4. Creates card with ID: `${elementId}-copy-${copyNumber}`
5. Appends " (Copy N)" to title
6. Opens card at next available grid position
7. Updates URL with new layout

---

## Implementation Details

### Card ID Format

**Pattern:** `{elementId}-copy-{number}`

**Examples:**
```javascript
"debug-variables-copy-2"
"server-heatmap-copy-3"
"memory-explorer-copy-4"
"file-explorer-copy-2"
```

**Regex Match:**
```javascript
const copyMatch = cardId.match(/-copy-(\d+)$/);
if (copyMatch) {
    const copyNumber = parseInt(copyMatch[1]); // 2, 3, 4, etc.
}
```

---

### Copy Number Algorithm

```javascript
// Find all existing cards with this elementId
const existingCardIds = Object.keys(data.elements).filter(cardId => {
    const element = data.elements[cardId];
    return element.Element_Id === elementId || cardId.startsWith(elementId);
});

// Extract copy numbers from card IDs
const copyNumbers = existingCardIds
    .map(cardId => {
        const match = cardId.match(/-copy-(\d+)$/);
        return match ? parseInt(match[1]) : 1; // Original = copy-1
    })
    .filter(num => !isNaN(num));

// Next copy number = max + 1
const copyNumber = copyNumbers.length > 0
    ? Math.max(...copyNumbers) + 1
    : 2; // First copy is copy-2
```

**Why this works:**
- Original card (no suffix) is treated as copy-1
- First copy becomes copy-2
- If copy-2 exists but copy-3 is closed, next copy is copy-4
- Prevents ID collisions even with gaps in sequence

---

### Title Formatting

**Standard Cards:**
```javascript
`${title} (Copy ${copyNumber})`
// "Debug Variables (Copy 2)"
// "Server Metrics (Copy 3)"
```

**HTML Content Cards:**
```javascript
`HTML - ${htmlTitlePart} (Copy ${copyNumber})`
// "HTML - Documentation (Copy 2)"
```

---

## UI Component Changes

### Main Menu Component

**File:** `public/elements/main-menu/component.js`

**Changed:** CardStatusIndicator component

**Before:**
- Single icon: "+" when closed, "×" when open
- Click behavior: open or close (no copy option)

**After:**
- When closed: Single "+" icon → opens first instance
- When open: Two icons → "+" opens copy, "×" closes

**New Structure:**
```javascript
// Card closed
<span className="card-status-icon closed">+</span>

// Card open
<span className="card-status-icons open">
    <span className="card-status-icon copy">+</span>  // Opens copy
    <span className="card-status-icon close">×</span>  // Closes card
</span>
```

---

## Use Cases

### Use Case 1: Compare Different Data

**Scenario:** User wants to compare metrics from two time ranges

**Steps:**
1. Open "Server Metrics" card → shows CPU from last hour
2. Click "+" again → opens Copy 2
3. Configure Copy 2 to show CPU from last day
4. Compare charts side-by-side

**Result:** Two independent instances with different configurations

---

### Use Case 2: Multi-Monitor Workflow

**Scenario:** Developer monitors logs on second screen

**Steps:**
1. Open "Real-time Events" on main screen
2. Click "+" to open Copy 2
3. Drag Copy 2 to second monitor (fullscreen)
4. Filter each copy for different severity levels

**Result:** Simultaneous monitoring of different log streams

---

### Use Case 3: Reference While Editing

**Scenario:** User edits file while referencing another

**Steps:**
1. Open "File Explorer" → navigate to config.json
2. Click "+" to open Copy 2
3. Navigate Copy 2 to template.json
4. Copy values from template to config

**Result:** Two file explorers showing different files

---

## Differences from openCard

| Feature | openCard | openCardCopy |
|---------|----------|--------------|
| **Duplicate Prevention** | Yes | No |
| **Card Already Open** | Scrolls to existing | Creates new copy |
| **Card ID** | `{elementId}-{timestamp}` | `{elementId}-copy-{number}` |
| **Title** | Original | "+ (Copy N)" suffix |
| **Use Case** | First instance | Additional instances |

---

## Logging

**Console Output:**
```javascript
[openCardCopy] Creating copy #2 of 'debug-variables' with ID: debug-variables-copy-2
[openCardCopy] Fetched card settings: {...}
[openCardCopy] Adding temporary layout item: {...}
[openCardCopy] Final position found: {x: 0, y: 20}
[openCardCopy] Updated gridLayout with saved settings: [...]
[openCardCopy] Updating URL with cards: [...]
```

**Server Logs:**
```
Info  URLLayout  Card copy #2 opened and layout URL updated
Data: {"cardId":"debug-variables-copy-2"}
```

---

## Grid Positioning

**Copy Placement Strategy:**
1. Call `findNextFreePosition()` to locate empty grid space
2. Prefer positions below existing cards (increasing Y)
3. If no free space, place at bottom of grid
4. Avoid overlapping with existing cards

**Example Layout:**
```
[Original Card]  (y: 0)
[Copy 2]         (y: 10)
[Copy 3]         (y: 20)
[Copy 4]         (y: 30)
```

---

## URL Serialization

Copies are serialized to URL layout parameter same as regular cards:

```json
{
  "version": 2,
  "cards": [
    {
      "id": "debug-variables-1770011505644",
      "elementId": "debug-variables",
      "title": "Debug Variables",
      ...
    },
    {
      "id": "debug-variables-copy-2",
      "elementId": "debug-variables",
      "title": "Debug Variables (Copy 2)",
      ...
    }
  ]
}
```

**Important:** Both cards share the same `elementId` but have unique `id` fields.

---

## Testing

### Test Case 1: Sequential Copies

**Steps:**
1. Open "Debug Variables" card
2. Click "+" three times
3. Observe card IDs and titles

**Expected:**
- Original: `debug-variables-{timestamp}`, "Debug Variables"
- Copy 2: `debug-variables-copy-2`, "Debug Variables (Copy 2)"
- Copy 3: `debug-variables-copy-3`, "Debug Variables (Copy 3)"
- Copy 4: `debug-variables-copy-4`, "Debug Variables (Copy 4)"

---

### Test Case 2: Close Middle Copy

**Steps:**
1. Open original + 3 copies (copy-2, copy-3, copy-4)
2. Close copy-3
3. Click "+" to open another copy

**Expected:**
- New copy is `debug-variables-copy-5` (not copy-3)
- Copy numbering continues from highest, doesn't reuse gaps

---

### Test Case 3: URL Persistence

**Steps:**
1. Open original + 2 copies
2. Check URL in address bar
3. Copy URL
4. Open URL in new tab

**Expected:**
- ✅ All three cards reload correctly
- ✅ Each has correct ID and title
- ✅ Grid positions preserved
- ✅ No duplicate key warnings

---

## Known Limitations

1. **Copy number gaps not reused** - If copy-3 is closed, next copy is copy-5, not copy-3
2. **Timestamp cards treated as copy-1** - Original cards with timestamp IDs count as copy-1 in numbering
3. **No automatic renumbering** - Closing copies doesn't renumber remaining copies

These are **intentional design decisions** to maintain ID stability and prevent conflicts.

---

## Future Enhancements

**Potential Improvements:**
- [ ] Add "Duplicate" context menu option
- [ ] Keyboard shortcut (Shift+Click) for quick copy
- [ ] Visual indicator showing copy number in card header
- [ ] "Close all copies" batch action
- [ ] Copy-specific settings that don't affect original

---

## Security Considerations

**Authentication:**
- Copies use same authentication as original card
- Endpoint permissions checked for each copy
- No privilege escalation via copying

**Resource Usage:**
- Each copy is a full card instance (memory overhead)
- Monitor system resources with many copies
- Consider rate limiting for rapid copy creation

---

## Status

✅ **Implemented** - Feature complete and ready for use

**Components Updated:**
1. ✅ `public/psweb_spa.js` - Added `window.openCardCopy()` function
2. ✅ `public/elements/main-menu/component.js` - Updated CardStatusIndicator UI

---

## End of Report
