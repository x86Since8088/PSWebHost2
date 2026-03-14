# PSWebHost Project Organization
**Date**: 2026-02-24
**Status**: Reorganization Complete

---

## Directory Structure

```
PsWebHost/
├── apps/                    # Application modules (Docker, Linux, SQL, etc.)
├── config/                  # Configuration files
├── data/                    # Application data
├── docs/                    # Documentation
├── help/                    # NEW: Organized documentation
│   ├── architecture/        # System architecture docs
│   ├── auth/               # Authentication documentation
│   ├── cards/              # Card system documentation
│   ├── debug/              # Debug system docs
│   ├── duckdb/             # DuckDB implementation docs
│   ├── features/           # Feature documentation
│   ├── file-explorer/      # File explorer docs
│   ├── fixes/              # Bug fix reports
│   ├── metrics/            # Metrics system docs
│   ├── migration/          # Migration guides
│   ├── reference/          # Quick references and cheatsheets
│   ├── sessions/           # Session summaries (dated)
│   ├── system/             # System component docs
│   └── testing/            # Testing guides
├── logs/                    # NEW: Server and debug logs
├── modules/                 # PowerShell modules
├── ModuleDownload/         # Downloaded PS modules
├── public/                  # Frontend files
│   ├── elements/           # Core card components
│   ├── help/               # Help content for cards
│   └── lib/                # JavaScript libraries
├── routes/                  # API route handlers
├── system/                  # System initialization scripts
├── tests/                   # REORGANIZED: Test scripts
│   ├── auth/               # Authentication tests
│   ├── cards/              # Card component tests
│   ├── debug/              # Debug system tests
│   ├── deprecated/         # Deprecated tests (kept for reference)
│   ├── helpers/            # Test helper utilities
│   ├── integration/        # Integration tests
│   ├── memory/             # Memory analysis tests
│   ├── metrics/            # Metrics system tests
│   ├── modules/            # Module export tests
│   ├── pester/             # Pester test suites
│   ├── utilities/          # General utility tests
│   └── Run-Tests.ps1       # Test runner helper
└── _ImportFrom/            # Imported modules/configs
```

---

## Key Files

### Root Directory
- `WebHost.ps1` - Main entry point
- `README.md` - Project readme
- `COMPONENT_REFERENCE.csv` - RAG database for components
- `Get-ComponentTips.ps1` - Component query utility
- `Install.bat` / `install.sh` - Installation scripts

### Configuration
- `config/settings.json` - Server settings
- `config/menu*.yaml` - Menu configurations
- `config/apps-config.yaml` - Application configurations

### Core Modules
- `modules/PSWebHost_Support/` - Core support functions
- `modules/PSWebHost_Authentication/` - Authentication
- `modules/PSWebHost_Database/` - Database operations
- `modules/PSWebHost_Jobs/` - Job management

---

## File Counts After Reorganization

| Category | Before | After | Location |
|----------|--------|-------|----------|
| MD Docs in Root | 185 | 1 (README.md) | Moved to help/ |
| Test Scripts in Root | 104 | 0 | Moved to tests/ |
| Log Files in Root | 8 | 0 | Moved to logs/ |
| PS1 Utilities in Root | ~38 | ~38 | Kept (utilities) |

### Tests Organization
- **97 scripts** kept and categorized
- **4 scripts** deprecated (moved to tests/deprecated/)
- **3 scripts** disposed (empty/minimal)
- **38 scripts** had path references updated

---

## Help Directory Organization

| Subfolder | Files | Content |
|-----------|-------|---------|
| sessions/ | 18 | Dated session summaries |
| architecture/ | 20 | System design docs |
| features/ | 28 | Feature documentation |
| fixes/ | 41 | Bug fix reports |
| system/ | 25 | Component docs |
| migration/ | 12 | Migration guides |
| cards/ | 9 | Card system docs |
| debug/ | 6 | Debug system docs |
| testing/ | 6 | Test guides |
| file-explorer/ | 7 | File explorer docs |
| metrics/ | 4 | Metrics docs |
| duckdb/ | 4 | DuckDB docs |
| reference/ | 4+ | Quick references |
| auth/ | 0 | Auth docs (pending) |

---

## RAG CSV Reference System

### Usage
```powershell
# Query by component name
.\Get-ComponentTips.ps1 -ComponentName "main-menu"

# Search by keyword
.\Get-ComponentTips.ps1 -Keyword "docker"

# Filter by status
.\Get-ComponentTips.ps1 -Status Placeholder

# Show all app components
.\Get-ComponentTips.ps1 -Type App -ShowAll
```

### CSV Columns
- ComponentName, ElementId, Type, Path, Status
- Purpose, Props, CommonIssues, Tips, Keywords

---

## Test Categories

### tests/auth/ (Authentication)
- test_auth_quick.ps1, test_auth_curl.ps1, test_auth_debug.ps1
- test_cards_with_auth.ps1, test_poll_with_auth.ps1
- test_session_debug.ps1

### tests/cards/ (Card Components)
- test_all_cards_automated.ps1, test_card_endpoints.ps1
- test_card_operations.ps1, test_cards_continuous.ps1
- scan_card_patterns.ps1, diagnose_card_responses.ps1

### tests/debug/ (Debug System)
- test_debug_command_system.ps1, test_debug_commands.ps1
- test_debug_poll_service.ps1, test_debug_utilities.ps1

### tests/metrics/ (Metrics)
- test_metrics_collection.ps1, test_metrics_init.ps1
- Test-DuckDB-MetricsChart.ps1, verify_metrics_working.ps1

### tests/memory/ (Memory Analysis)
- diagnose_memory_leak.ps1, test_memory_consumption.ps1
- test_integration_memory_system.ps1, inspect_runspace_state.ps1

### tests/modules/ (Module Exports)
- Check-ModuleExports.ps1, check_loaded_module.ps1
- check_module.ps1, Check-ServerModuleState.ps1

---

## Running Tests

```powershell
# List test categories
.\tests\Run-Tests.ps1 -List

# Run tests by category
.\tests\Run-Tests.ps1 -Category auth

# Run specific test
.\tests\Run-Tests.ps1 -Name test_auth_quick
```

---

## Utility Scripts (Root)

### Server Management
- `restart_server.ps1` - Restart web server
- `start_and_verify_metrics.ps1` - Start with metrics
- `tail-logs.ps1` - Follow server logs

### Development
- `Get-ComponentTips.ps1` - Query component reference
- `run_all_diagnostics.ps1` - Run all diagnostic scripts
- `Validate-ModuleExports.ps1` - Verify module exports

### Migration
- `migrate_cards.ps1` - Card migration utility
- `convert-apps-to-yaml.ps1` - App config converter
- `update_card_url_references.ps1` - Update card URLs

---

## Recommendations

### For New Development
1. Check COMPONENT_REFERENCE.csv before creating components
2. Add tests to appropriate tests/ subfolder
3. Document new features in help/features/
4. Update RAG CSV with new component info

### For Maintenance
1. Run tests with `.\tests\Run-Tests.ps1 -Category all`
2. Check help/fixes/ for known issue solutions
3. Use help/reference/ for quick lookups

### For Agents
1. Query COMPONENT_REFERENCE.csv first
2. Check help/ for existing documentation
3. Use Get-ComponentTips.ps1 for component info
4. Tests are now in tests/<category>/ subdirectories
