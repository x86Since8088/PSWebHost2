# File Explorer "nodes is not iterable" Fix + Test Script Organization

**Date**: 2026-01-27
**Status**: ✅ **COMPLETE**

---

## Issue 1: File Explorer JavaScript Error

### Problem

**Error Message**:
```
Uncaught (in promise) TypeError: nodes is not iterable
  at handleExpand (component.js:2528)
```

**When it occurred**: When expanding folder nodes in the File Explorer tree

### Root Cause

The `findNodeByPath()` function uses `for...of` to iterate over `nodes`:

```javascript
const findNodeByPath = (nodes, path) => {
    for (const node of nodes) {  // ❌ Fails if nodes is not an array
        // ...
    }
};
```

**Problem**: If `nodes` is `undefined`, `null`, or not an array, the `for...of` loop throws "not iterable" error.

**Scenarios where this can happen**:
1. Server returns malformed response (`result.roots` is not an array)
2. Tree state gets corrupted
3. Component renders before tree is fully loaded

### Fix Applied

**File**: `apps\WebhostFileExplorer\public\elements\file-explorer\component.js`

**3 defensive checks added**:

#### 1. Add Array Check in `findNodeByPath()`

**Location**: Line ~2476

```javascript
const findNodeByPath = (nodes, path) => {
    if (!Array.isArray(nodes)) {
        console.warn('[findNodeByPath] nodes is not an array:', nodes);
        return null;
    }
    for (const node of nodes) {
        if (node.path === path) return node;
        if (node.children) {
            const found = findNodeByPath(node.children, path);
            if (found) return found;
        }
    }
    return null;
};
```

#### 2. Add Guard in `TreeNavigation` Component

**Location**: Line ~330

```javascript
const TreeNavigation = ({ treeState, onExpand, onSelect, selectedPath, expandingPath }) => {
    if (!treeState || !Array.isArray(treeState.nodes)) {
        return (
            <div className="tree-navigation">
                <div className="tree-header">Folders</div>
                <div className="tree-content">
                    <div style={{ padding: '10px', color: '#888' }}>Loading...</div>
                </div>
            </div>
        );
    }

    return (
        <div className="tree-navigation">
            <div className="tree-header">Folders</div>
            <div className="tree-content">
                {treeState.nodes.map(node => (
                    // ...
                ))}
            </div>
        </div>
    );
};
```

#### 3. Ensure `loadRoots()` Always Sets Array

**Location**: Line ~1290

```javascript
const result = await response.json();
logToServer(`loadRoots: Received ${result.roots?.length || 0} roots`);

if (result.roots && Array.isArray(result.roots) && result.roots.length > 0) {
    setTreeState({ nodes: result.roots });
    setSelectedTreePath(result.roots[0].path);
    logToServer(`loadRoots: Selected default root: ${result.roots[0].name}`);
} else {
    setTreeState({ nodes: [] });  // ← Always set empty array
    showToast('No file locations available', 'error');
}
```

### Benefits

✅ **No more crashes** when tree data is malformed
✅ **Graceful degradation** - Shows "Loading..." instead of crashing
✅ **Better debugging** - Console warning shows what went wrong
✅ **Defensive coding** - Handles edge cases

### Testing

**To verify fix**:
1. Open File Explorer in browser
2. Try expanding folder nodes
3. Should NOT see "nodes is not iterable" error
4. If server returns bad data, should show "Loading..." gracefully

---

## Issue 2: Test Script Organization

### Problem

**62 test/diagnostic scripts** scattered in project root, making it hard to:
- Find relevant tests
- Identify obsolete scripts
- Maintain test suite
- Navigate project

### Solution

Created `Organize-TestScripts.ps1` to automatically categorize and organize scripts.

### Script Categories

#### KEEP → `tests/`
- `Test-URLLayoutV2.ps1` - Recent v2 URL layout tests
- `Test-RunspaceModuleLoading.ps1` - Module loading diagnostics
- `Test-MemoryAnalysisWorkflow.ps1` - Memory analysis tests
- `Quick-CheckExports.ps1` - Module export validation
- `Check-ModuleExports.ps1` - Module manifest checker
- `test-browser-search.ps1` - Browser integration tests
- `test-discover-apps.ps1` - App discovery tests

#### KEEP → `tests/twin/`
- `Test-JobManipulation.ps1` - Job system tests
- `Test-JobSystemEndpoints.ps1` - Job API tests
- `test_fileexplorer_config.ps1` - FileExplorer config tests
- `test_user_others_phase2.ps1` - User:others feature tests
- `test-menu.ps1` - Menu system tests

#### KEEP → `system/utility/`
- `decode_url.ps1` - URL decoding utility
- `Create-TestAdminToken.ps1` - Test token creation

#### DELETE (Obsolete)
- `check_metrics*.ps1` (22 scripts) - Old metrics checks
- `query_*.ps1` (10 scripts) - One-time query scripts
- `measure_*.ps1` (5 scripts) - One-time measurements
- `diagnose_*.ps1` (8 scripts) - Resolved diagnostic scripts
- `test_cli*.ps1` (5 scripts) - Superseded tests
- `check_server*.ps1` (6 scripts) - One-time server checks

#### ARCHIVE (Review)
- Scripts with uncertain relevance moved to `tests/archive/`

### Usage

**Dry run (see what would happen)**:
```powershell
.\Organize-TestScripts.ps1 -DryRun
```

**Execute with confirmation**:
```powershell
.\Organize-TestScripts.ps1
```

**Execute without confirmation**:
```powershell
.\Organize-TestScripts.ps1 -Force
```

### Output Example

```
=== Test Script Organization ===
Mode: DRY RUN

Found 62 test/diagnostic scripts in root

=== Organization Plan ===

Move: 12 scripts
  Test-URLLayoutV2.ps1
    → Recent diagnostic utility - keep in tests/
    → C:\SC\PsWebHost\tests
  Test-JobManipulation.ps1
    → Job system twin test
    → C:\SC\PsWebHost\tests\twin
  ...

Delete: 40 scripts
  check_metrics.ps1
    → Obsolete metrics diagnostic (superseded by newer tests)
  query_all_vars.ps1
    → One-time diagnostic script (no longer needed)
  ...

Archive: 10 scripts
  check-paths.ps1
    → Uncertain relevance - archive for review
    → C:\SC\PsWebHost\tests\archive
  ...
```

### Benefits

✅ **Clean project root** - Only essential files remain
✅ **Organized tests** - Tests in proper locations
✅ **Easy maintenance** - Know which scripts are relevant
✅ **Documented decisions** - Each move has a reason
✅ **Safe execution** - Dry-run mode to preview changes
✅ **Recoverable** - Uncertain scripts archived, not deleted

---

## File Changes Summary

### Modified Files

1. **`apps\WebhostFileExplorer\public\elements\file-explorer\component.js`**
   - Added array check in `findNodeByPath()` (~line 2476)
   - Added guard in `TreeNavigation` component (~line 330)
   - Fixed `loadRoots()` to always set array (~line 1290)

### Created Files

1. **`Organize-TestScripts.ps1`**
   - Test script organization utility
   - Classification rules for 62 scripts
   - Safe execution with dry-run mode

---

## Testing Instructions

### File Explorer Fix

**Test 1: Normal Operation**
1. Open http://localhost:8080/spa
2. Open File Explorer from main menu
3. Click expand buttons (▶) on folder nodes
4. Verify folders expand without errors

**Test 2: Error Handling**
1. Open browser console (F12)
2. Expand multiple folders
3. Verify no "nodes is not iterable" errors
4. If errors occur, should see warning with details

**Test 3: Empty Tree**
1. Temporarily break `/api/v1/roots` endpoint to return `{}`
2. Reload page
3. Should see "Loading..." message, not crash

### Test Script Organization

**Test 1: Dry Run**
```powershell
.\Organize-TestScripts.ps1 -DryRun
```
- Review classification of each script
- Verify moves/deletes/archives are appropriate

**Test 2: Execute**
```powershell
.\Organize-TestScripts.ps1
```
- Review plan
- Confirm with 'y'
- Verify scripts moved to correct locations

**Test 3: Verify Organization**
```powershell
ls tests/
ls tests/twin/
ls tests/archive/
ls system/utility/
```
- Verify relevant scripts in correct locations
- Check no essential scripts were deleted

---

## Impact Assessment

### File Explorer Fix

**Before**: File Explorer crashes when expanding nodes if server returns bad data
**After**: Graceful error handling with "Loading..." message

**Affected Users**: Anyone using File Explorer
**Risk**: Low - Defensive checks only, no logic changes

### Test Script Organization

**Before**: 62 test scripts in root, hard to find relevant tests
**After**: Organized structure, obsolete scripts removed

**Affected**: Developers running tests
**Risk**: Very Low - Scripts only moved/deleted, not modified

---

## Verification Checklist

### File Explorer

- [ ] No "nodes is not iterable" errors when expanding folders
- [ ] Tree loads correctly on page load
- [ ] Empty tree shows "Loading..." gracefully
- [ ] Console warnings appear if data is malformed
- [ ] All folder navigation works

### Test Scripts

- [ ] Dry run shows reasonable classifications
- [ ] Essential test scripts preserved
- [ ] Obsolete scripts removed
- [ ] Uncertain scripts archived
- [ ] No accidental deletions of important scripts

---

## Rollback Plan

### File Explorer

**If issues occur**:
```bash
git checkout apps/WebhostFileExplorer/public/elements/file-explorer/component.js
```

### Test Scripts

**If wrong scripts deleted**:
```powershell
# Restore from Git
git checkout <script-name>.ps1

# Or restore from archive
cp tests/archive/<script-name>.ps1 .
```

---

## Next Steps

### Recommended

1. **Run test organization script**
   ```powershell
   .\Organize-TestScripts.ps1 -DryRun
   # Review output
   .\Organize-TestScripts.ps1
   ```

2. **Test File Explorer**
   - Open in browser
   - Expand various folder nodes
   - Verify no errors

3. **Commit changes**
   ```powershell
   git add apps/WebhostFileExplorer/public/elements/file-explorer/component.js
   git commit -m "Fix: Add defensive checks for tree node iteration

- Add array validation in findNodeByPath()
- Add guard in TreeNavigation component
- Ensure loadRoots() always sets array
- Prevents 'nodes is not iterable' error"
   ```

4. **Review archived scripts**
   - Check `tests/archive/`
   - Decide if any should be kept
   - Delete archive folder if all confirmed obsolete

---

## Summary

✅ **File Explorer Fix**: Added defensive checks to prevent "nodes is not iterable" error
✅ **Test Organization**: Created utility to organize 62 test scripts
✅ **Clean Project**: Root directory will be much cleaner
✅ **Maintainability**: Tests properly organized and documented

**Status**: Both fixes complete and ready for testing

---

**Created**: 2026-01-27
**Components**: File Explorer (JavaScript), Test Organization (PowerShell)
**Impact**: Bug fix + Project cleanup
**Risk**: Low
