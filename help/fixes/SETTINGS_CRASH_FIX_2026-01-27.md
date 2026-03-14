# Settings Gear Crash Fix

**Date**: 2026-01-27
**Status**: ✅ **FIXED**

---

## Problem

**User Report**: "Clicking the gear in FileExplorer causes SPA to crash"

**Error**:
```
Uncaught ReferenceError: chunkSizeMB is not defined
    IconToolbar line 340
```

---

## Root Cause

When adding the chunk size slider to the settings UI, I referenced `chunkSizeMB` and `updateChunkSize` inside the `IconToolbar` component's JSX, but forgot to:
1. Add these to the component's props parameter list
2. Pass them when calling `<IconToolbar />` from the parent component

**Result**: JavaScript threw `ReferenceError` because `chunkSizeMB` was undefined in the component's scope.

---

## Fix

### 1. Added Props to IconToolbar Definition

**File**: `apps/WebhostFileExplorer/public/elements/file-explorer/component.js:240`

**Before**:
```javascript
const IconToolbar = ({ onAction, previewVisible, useWebSocket, onToggleWebSocket, usePipelining, onTogglePipelining, showSettings, onToggleSettings }) => {
```

**After**:
```javascript
const IconToolbar = ({ onAction, previewVisible, useWebSocket, onToggleWebSocket, usePipelining, onTogglePipelining, chunkSizeMB, updateChunkSize, showSettings, onToggleSettings }) => {
```

### 2. Passed Props to IconToolbar

**File**: `apps/WebhostFileExplorer/public/elements/file-explorer/component.js:3519-3528`

**Before**:
```javascript
<IconToolbar
    onAction={handleAction}
    previewVisible={previewVisible}
    useWebSocket={useWebSocket}
    onToggleWebSocket={toggleWebSocket}
    usePipelining={usePipelining}
    onTogglePipelining={togglePipelining}
    showSettings={showSettings}
    onToggleSettings={() => setShowSettings(!showSettings)}
/>
```

**After**:
```javascript
<IconToolbar
    onAction={handleAction}
    previewVisible={previewVisible}
    useWebSocket={useWebSocket}
    onToggleWebSocket={toggleWebSocket}
    usePipelining={usePipelining}
    onTogglePipelining={togglePipelining}
    chunkSizeMB={chunkSizeMB}
    updateChunkSize={updateChunkSize}
    showSettings={showSettings}
    onToggleSettings={() => setShowSettings(!showSettings)}
/>
```

---

## Testing

**Steps**:
1. Reload the SPA page
2. Open File Explorer
3. Click the settings gear (⚙️)
4. **Verify**: Settings dropdown appears with chunk size slider
5. **Verify**: No crash, no console errors

**Success Criteria**:
- ✅ Settings gear works
- ✅ Chunk size slider is visible
- ✅ No JavaScript errors

---

## Summary

**Root Cause**: Missing props in React component
**Fix**: Added `chunkSizeMB` and `updateChunkSize` to IconToolbar props
**Lines Changed**: 2
**Risk**: None (pure prop passing)

---

**Created**: 2026-01-27
**Type**: Bug Fix
**Impact**: Critical (SPA was crashing)
