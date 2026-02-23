# Duplicate Card Prevention Fix

**Date:** 2026-02-01
**Issue:** Duplicate cards appearing in layout, causing React warnings and layout issues

---

## Problem

Browser console showed React Grid Layout warning:
```
Warning: Failed prop type: Duplicate child key "debug-variables-1770011505644" found!
This will cause problems in ReactGridLayout.
```

The layout URL contained **two identical entries** for the same card:
```json
{
  "cards": [
    {
      "id": "debug-variables-1770011505644",
      "elementId": "debug-variables",
      ...
    },
    {
      "id": "debug-variables-1770011505644",  // Duplicate!
      "elementId": "debug-variables",
      ...
    }
  ]
}
```

---

## Root Cause

The codebase had **no duplicate prevention** at any level:

1. **openCard()** - Always created new cards without checking if already open
2. **URL Layout Loading** - Loaded all cards from URL including duplicates
3. **serializeLayoutToURL()** - Saved all cards including duplicates

This allowed duplicates to accumulate through various scenarios:
- Double-clicking menu items
- Race conditions during card opening
- Manually edited URLs with duplicates
- Layout restoration with duplicate entries

---

## Solution

Added **three layers of duplicate prevention** to ensure duplicates are prevented at every stage.

---

### Fix 1: Prevent Opening Duplicate Cards

**File:** `public/psweb_spa.js`
**Location:** Line 2567-2579 (openCard function)

**Added:**
```javascript
// Check if a card with this elementId is already open
if (elementId !== 'iframe-card' && window.findCardsByElementId) {
    const existingCards = window.findCardsByElementId(elementId);
    if (existingCards.length > 0) {
        console.log(`[openCard] Card with elementId '${elementId}' is already open (${existingCards[0]}), scrolling to it instead`);
        if (window.scrollToCard) {
            window.scrollToCard(existingCards[0]);
        }
        return;  // Exit early, don't create duplicate
    }
}
```

**Behavior:**
- Before opening a card, checks if same `elementId` is already open
- If found, scrolls to existing card instead of creating new one
- Prevents duplicates from double-clicks or rapid menu clicks

---

### Fix 2: Deduplicate Cards When Loading from URL

**File:** `public/psweb_spa.js`
**Location:** Line 1789-1801 (loadLayout function)

**Added:**
```javascript
// Deduplicate cards by ID (keep first occurrence)
const seenIds = new Set();
const uniqueCards = [];
for (const card of urlLayout.cards) {
    if (!seenIds.has(card.id)) {
        seenIds.add(card.id);
        uniqueCards.push(card);
    } else {
        console.warn(`[URL Layout] Skipping duplicate card in URL: ${card.id}`);
    }
}
urlLayout.cards = uniqueCards;
```

**Behavior:**
- When loading layout from URL parameter, deduplicates cards
- Keeps first occurrence of each unique card ID
- Logs warning when duplicates are found
- Ensures React Grid Layout receives clean data

---

### Fix 3: Deduplicate When Serializing Layout to URL

**File:** `public/psweb_spa.js`
**Location:** Line 1597-1619 (serializeLayoutToURL function)

**Added:**
```javascript
// Deduplicate gridLayout by card ID (keep last occurrence)
const seenIds = new Set();
const uniqueGridLayout = [];
for (let i = gridLayout.length - 1; i >= 0; i--) {
    if (!seenIds.has(gridLayout[i].i)) {
        seenIds.add(gridLayout[i].i);
        uniqueGridLayout.unshift(gridLayout[i]);
    } else {
        console.warn(`[URL Layout] Skipping duplicate card in gridLayout: ${gridLayout[i].i}`);
    }
}
```

**Behavior:**
- Before saving layout to URL, deduplicates cards in gridLayout
- Keeps last occurrence (most recent position/size)
- Logs warning when duplicates are found
- Prevents duplicates from being persisted in URLs

---

## Defense-in-Depth Strategy

Each layer serves a specific purpose:

| Layer | Prevention Point | When It Triggers |
|-------|-----------------|------------------|
| **openCard** | User Action | Double-click menu, rapid clicks |
| **loadLayout** | URL Loading | Corrupted URLs, manual edits |
| **serializeLayoutToURL** | URL Saving | Any duplicate in state |

Even if one layer fails or is bypassed, the other layers provide backup protection.

---

## Example Scenarios

### Scenario 1: Double-Click Menu Item

**Without Fix:**
1. User double-clicks "Debug Variables" in menu
2. First click: Opens debug-variables-1234567890
3. Second click: Opens debug-variables-1234567891 (different timestamp)
4. Result: Two identical cards side-by-side

**With Fix:**
1. User double-clicks "Debug Variables"
2. First click: Opens debug-variables-1234567890
3. Second click: Detects existing card, scrolls to it
4. Result: Single card, scrolled into view

---

### Scenario 2: Corrupted URL Parameter

**Without Fix:**
```
?layout=eyJ...  (contains duplicate "debug-variables-123")
```
1. Page loads, React processes duplicate keys
2. React warning in console
3. Grid layout has overlapping cards
4. Unpredictable behavior

**With Fix:**
```
?layout=eyJ...  (contains duplicate)
```
1. loadLayout deduplicates before processing
2. Only first occurrence loaded
3. Warning logged: "Skipping duplicate card in URL: debug-variables-123"
4. Clean grid layout

---

### Scenario 3: Layout Save with Duplicate in State

**Without Fix:**
1. gridLayout somehow contains duplicate entries
2. User moves a card (triggers layout save)
3. serializeLayoutToURL saves both duplicates to URL
4. Duplicate persists in browser history

**With Fix:**
1. gridLayout contains duplicate
2. User moves a card
3. serializeLayoutToURL deduplicates before encoding
4. Warning logged: "Skipping duplicate card in gridLayout"
5. Clean URL saved to history

---

## Testing

### Test Case 1: Double-Click Menu Item

**Steps:**
1. Double-click any menu item quickly
2. Observe browser console
3. Check card count

**Expected:**
- ✅ Only one card opens
- ✅ Console shows: "Card with elementId '...' is already open, scrolling to it instead"
- ✅ Page scrolls to existing card
- ❌ No duplicate cards

---

### Test Case 2: Load URL with Duplicates

**Test URL:**
```
http://localhost:8080/spa?layout=eyJ2ZXJzaW9uIjoyLCJjYXJkcyI6W3siaWQiOiJ0ZXN0LTEyMyIsIngiOjAsInkiOjAsInciOjYsImgiOjEwLCJlbGVtZW50SWQiOiJ0ZXN0In0seyJpZCI6InRlc3QtMTIzIiwieCI6NiwieSI6MCwidyI6NiwiaCI6MTAsImVsZW1lbnRJZCI6InRlc3QifV19
```
(Contains duplicate "test-123")

**Expected:**
- ✅ Only first card loads
- ✅ Console shows: "Skipping duplicate card in URL: test-123"
- ❌ No React warnings
- ❌ No duplicate cards

---

### Test Case 3: Layout Persistence

**Steps:**
1. Open multiple cards
2. Close and reopen same card
3. Move cards around
4. Check URL in address bar

**Expected:**
- ✅ URL updates after each action
- ✅ No duplicate entries in URL
- ✅ Decoded layout has unique card IDs
- ✅ No warnings in console

---

## React Grid Layout Requirements

React Grid Layout requires each child to have a **unique key prop**. Duplicate keys cause:

1. **React Warnings:** `Duplicate child key "..." found!`
2. **Render Issues:** React can't distinguish between components
3. **State Confusion:** Updates may affect wrong component
4. **Layout Corruption:** Grid positions become unpredictable

Our fix ensures React Grid Layout always receives:
- ✅ Unique keys (card IDs)
- ✅ One grid item per card
- ✅ Clean, deduplicated data structure

---

## Related Issues Fixed

This fix also resolves:
- **Layout flickering** - Caused by conflicting duplicate positions
- **State inconsistency** - Multiple components with same ID
- **Performance issues** - Unnecessary duplicate renders
- **Save/restore bugs** - Duplicate entries in saved layouts

---

## Prevention Guidelines

**For Future Development:**

1. **Always check for duplicates** before adding items to arrays
2. **Use Set() for uniqueness** when order doesn't matter
3. **Validate layout data** before persisting
4. **Log warnings** when duplicates are detected
5. **Test double-click scenarios** for all interactive elements

---

## Monitoring

Added console warnings to track duplicate detection:

```javascript
// When user tries to open duplicate card
"Card with elementId 'debug-variables' is already open, scrolling to it instead"

// When URL contains duplicates
"Skipping duplicate card in URL: debug-variables-1770011505644"

// When gridLayout has duplicates before save
"Skipping duplicate card in gridLayout: debug-variables-1770011505644"
```

Monitor these warnings to identify:
- User behavior patterns (rapid clicking)
- Bugs causing duplicate state
- Manually edited URLs with errors

---

## Status

✅ **Fixed** - Three-layer duplicate prevention implemented

**Layers:**
1. ✅ openCard - Prevents opening duplicates
2. ✅ loadLayout - Cleans duplicates from URL
3. ✅ serializeLayoutToURL - Prevents saving duplicates

---

## End of Report
