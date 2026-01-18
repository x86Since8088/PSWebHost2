#Requires -Version 7

# WebHostTaskManagement App Initialization Script
# This script runs during PSWebHost startup when the WebHostTaskManagement app is loaded

param(
    [hashtable]$PSWebServer,
    [string]$AppRoot
)

$MyTag = '[WebHostTaskManagement:Init]'

Write-Host "$MyTag Initializing task management system..." -ForegroundColor Cyan

try {
    # 1. Import app module
    $modulePath = Join-Path $AppRoot "modules\PSWebHost_TaskManagement\PSWebHost_TaskManagement.psm1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
        Write-Verbose "$MyTag Loaded PSWebHost_TaskManagement module" -Verbose
    }

    # 2. Initialize app namespace
    $PSWebServer['WebHostTaskManagement'] = [hashtable]::Synchronized(@{
        AppRoot = $AppRoot
        DataPath = Join-Path $PSWebServer['DataRoot'] "apps\WebHostTaskManagement"
        Initialized = Get-Date

        # Task management settings
        Settings = @{
            TaskHistoryRetention = 30  # days
            MaxConcurrentTasks = 10
            EnableNotifications = $true
            DefaultTaskTimeout = 600   # seconds
        }

        # Statistics
        Stats = [hashtable]::Synchronized(@{
            TasksManaged = 0
            OperationsPerformed = 0
            LastOperation = $null
        })

        # Task database path
        TaskDatabasePath = Join-Path $PSWebServer['DataRoot'] "tasks.db"
    })

    # 3. Ensure data directories exist
    $DataPath = Join-Path $PSWebServer['DataRoot'] "apps\WebHostTaskManagement"
    if (-not (Test-Path $DataPath)) {
        New-Item -Path $DataPath -ItemType Directory -Force | Out-Null
        Write-Verbose "$MyTag Created data directory: $DataPath" -Verbose
    }

    # Create subdirectories
    @('exports', 'backups', 'logs') | ForEach-Object {
        $subDir = Join-Path $DataPath $_
        if (-not (Test-Path $subDir)) {
            New-Item -Path $subDir -ItemType Directory -Force | Out-Null
        }
    }

    # 4. Initialize runtime task configuration storage
    $runtimeConfigPath = Join-Path $PSWebServer['DataRoot'] "config\tasks.json"
    $configDir = Split-Path $runtimeConfigPath -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path $runtimeConfigPath)) {
        # Create initial empty configuration
        $initialConfig = @{
            version = "1.0"
            lastModified = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            tasks = @()
        }
        $initialConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $runtimeConfigPath
        Write-Verbose "$MyTag Created runtime task configuration: $runtimeConfigPath" -Verbose
    }

    # 5. Initialize task execution history database with multi-node support
    $taskDbPath = $PSWebServer['WebHostTaskManagement'].TaskDatabasePath
    if (-not (Test-Path $taskDbPath)) {
        # Create comprehensive task database schema with multi-node support
        $createSchema = @"
-- ============================================================================
-- Nodes Table - Registry of WebHost nodes in the cluster
-- ============================================================================
CREATE TABLE IF NOT EXISTS Nodes (
    NodeID TEXT PRIMARY KEY,           -- Unique identifier for this node
    NodeName TEXT NOT NULL,             -- Human-readable node name
    NodeGroup TEXT,                     -- Logical group (e.g., 'production', 'staging')
    NodeRole TEXT,                      -- Role (e.g., 'worker', 'coordinator', 'api')
    Hostname TEXT,                      -- Network hostname
    IPAddress TEXT,                     -- IP address
    Port INTEGER,                       -- HTTP listener port
    Status TEXT DEFAULT 'Active',       -- Active, Inactive, Offline
    Version TEXT,                       -- PSWebHost version
    Capabilities TEXT,                  -- JSON array of capabilities
    LastHeartbeat TEXT,                 -- Last heartbeat timestamp
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedAt TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_node_status ON Nodes(Status);
CREATE INDEX IF NOT EXISTS idx_node_group ON Nodes(NodeGroup);
CREATE INDEX IF NOT EXISTS idx_node_role ON Nodes(NodeRole);

-- ============================================================================
-- Tasks Table - Task definitions with node assignment
-- ============================================================================
CREATE TABLE IF NOT EXISTS Tasks (
    TaskID INTEGER PRIMARY KEY AUTOINCREMENT,
    TaskName TEXT NOT NULL,             -- Unique task name
    AppName TEXT,                       -- App that owns this task
    Source TEXT DEFAULT 'custom',       -- global, app, custom
    ScriptPath TEXT NOT NULL,           -- Path to task script
    Description TEXT,                   -- Human-readable description

    -- Scheduling
    Schedule TEXT,                      -- Cron expression
    Enabled INTEGER DEFAULT 1,          -- 1=enabled, 0=disabled

    -- Node Assignment (multi-node support)
    AssignedNodeID TEXT,                -- Specific node to run on (NULL = any)
    AssignedNodeGroup TEXT,             -- Node group to run on (NULL = any)
    AssignedNodeRole TEXT,              -- Node role required (NULL = any)

    -- Execution Control
    MaxRuntime INTEGER,                 -- Max runtime in seconds (NULL = no limit)
    MaxFailures INTEGER,                -- Max consecutive failures before disable
    KillOnTimeout INTEGER DEFAULT 1,    -- Force kill if max runtime exceeded

    -- Configuration
    Environment TEXT,                   -- JSON object of environment variables
    Configuration TEXT,                 -- JSON object of task-specific config

    -- Metadata
    CreatedBy TEXT,                     -- User who created task
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    DeletedAt TEXT,                     -- Soft delete timestamp

    -- Constraints
    UNIQUE(TaskName, AppName)
);

CREATE INDEX IF NOT EXISTS idx_task_name ON Tasks(TaskName);
CREATE INDEX IF NOT EXISTS idx_task_app ON Tasks(AppName);
CREATE INDEX IF NOT EXISTS idx_task_enabled ON Tasks(Enabled);
CREATE INDEX IF NOT EXISTS idx_task_node_id ON Tasks(AssignedNodeID);
CREATE INDEX IF NOT EXISTS idx_task_node_group ON Tasks(AssignedNodeGroup);
CREATE INDEX IF NOT EXISTS idx_task_node_role ON Tasks(AssignedNodeRole);
CREATE INDEX IF NOT EXISTS idx_task_deleted ON Tasks(DeletedAt);

-- ============================================================================
-- Task_Schedule Table - Task execution schedule and claims
-- ============================================================================
CREATE TABLE IF NOT EXISTS Task_Schedule (
    ScheduleID INTEGER PRIMARY KEY AUTOINCREMENT,
    TaskID INTEGER NOT NULL,
    TaskName TEXT NOT NULL,

    -- Scheduling
    NextRun TEXT,                       -- ISO 8601 timestamp of next scheduled run
    LastRun TEXT,                       -- ISO 8601 timestamp of last run

    -- Claiming (for distributed execution)
    ClaimedBy TEXT,                     -- NodeID that claimed this task
    ClaimedAt TEXT,                     -- When the claim was made
    ClaimExpiry TEXT,                   -- When the claim expires

    -- Status
    Status TEXT DEFAULT 'Pending',      -- Pending, Running, Completed, Failed
    CurrentJobID INTEGER,               -- Current job ID (if running)

    -- Metadata
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedAt TEXT DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (TaskID) REFERENCES Tasks(TaskID)
);

CREATE INDEX IF NOT EXISTS idx_schedule_next_run ON Task_Schedule(NextRun);
CREATE INDEX IF NOT EXISTS idx_schedule_claimed ON Task_Schedule(ClaimedBy);
CREATE INDEX IF NOT EXISTS idx_schedule_status ON Task_Schedule(Status);
CREATE INDEX IF NOT EXISTS idx_schedule_task ON Task_Schedule(TaskID);

-- ============================================================================
-- Task_History Table - Task execution history (renamed from TaskExecutions)
-- ============================================================================
CREATE TABLE IF NOT EXISTS Task_History (
    HistoryID INTEGER PRIMARY KEY AUTOINCREMENT,
    TaskID INTEGER,                     -- Reference to Tasks table (NULL for legacy)
    TaskName TEXT NOT NULL,
    AppName TEXT,

    -- Execution Details
    ExecutedBy TEXT NOT NULL,           -- NodeID that executed the task
    StartTime TEXT NOT NULL,
    EndTime TEXT,
    Duration INTEGER,                   -- Duration in seconds
    Status TEXT NOT NULL,               -- Running, Success, Failed, Terminated
    ExitCode INTEGER,

    -- Output and Errors
    Output TEXT,                        -- Task output (compressed JSON)
    ErrorMessage TEXT,                  -- Error message if failed

    -- Trigger Information
    TriggeredBy TEXT,                   -- Scheduled, Manual, API
    TriggeredByUser TEXT,               -- User ID if manually triggered

    -- Metadata
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (TaskID) REFERENCES Tasks(TaskID)
);

CREATE INDEX IF NOT EXISTS idx_history_task_name ON Task_History(TaskName);
CREATE INDEX IF NOT EXISTS idx_history_start_time ON Task_History(StartTime DESC);
CREATE INDEX IF NOT EXISTS idx_history_status ON Task_History(Status);
CREATE INDEX IF NOT EXISTS idx_history_executed_by ON Task_History(ExecutedBy);
CREATE INDEX IF NOT EXISTS idx_history_task_id ON Task_History(TaskID);

-- ============================================================================
-- Data_Change Table - Change tracking for table synchronization
-- ============================================================================
CREATE TABLE IF NOT EXISTS Data_Change (
    ChangeID INTEGER PRIMARY KEY AUTOINCREMENT,
    TableName TEXT NOT NULL,            -- Table that changed
    RecordID TEXT NOT NULL,             -- Primary key of changed record
    Action TEXT NOT NULL,               -- INSERT, UPDATE, DELETE

    -- Change Data (compressed JSON)
    OldData TEXT,                       -- Previous state (gzip compressed)
    NewData TEXT,                       -- New state (gzip compressed)

    -- Metadata
    ChangedBy TEXT,                     -- NodeID that made the change
    ChangedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    SyncedNodes TEXT                    -- JSON array of NodeIDs that synced
);

CREATE INDEX IF NOT EXISTS idx_change_table ON Data_Change(TableName);
CREATE INDEX IF NOT EXISTS idx_change_time ON Data_Change(ChangedAt DESC);
CREATE INDEX IF NOT EXISTS idx_change_action ON Data_Change(Action);
CREATE INDEX IF NOT EXISTS idx_change_synced ON Data_Change(SyncedNodes);

-- ============================================================================
-- Legacy Tables (for backwards compatibility)
-- ============================================================================
CREATE TABLE IF NOT EXISTS TaskExecutions (
    ID INTEGER PRIMARY KEY AUTOINCREMENT,
    TaskName TEXT NOT NULL,
    AppName TEXT,
    StartTime TEXT NOT NULL,
    EndTime TEXT,
    Duration INTEGER,
    Status TEXT NOT NULL,
    ExitCode INTEGER,
    Output TEXT,
    ErrorMessage TEXT,
    TriggeredBy TEXT,
    TriggeredByUser TEXT,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_task_exec_name ON TaskExecutions(TaskName);
CREATE INDEX IF NOT EXISTS idx_task_exec_start ON TaskExecutions(StartTime DESC);
CREATE INDEX IF NOT EXISTS idx_task_exec_status ON TaskExecutions(Status);
CREATE INDEX IF NOT EXISTS idx_task_exec_app ON TaskExecutions(AppName);

CREATE TABLE IF NOT EXISTS TaskConfigurations (
    ID INTEGER PRIMARY KEY AUTOINCREMENT,
    TaskName TEXT NOT NULL UNIQUE,
    AppName TEXT,
    Configuration TEXT NOT NULL,
    IsCustom INTEGER DEFAULT 0,
    IsDeleted INTEGER DEFAULT 0,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_config_task_name ON TaskConfigurations(TaskName);
CREATE INDEX IF NOT EXISTS idx_config_app_name ON TaskConfigurations(AppName);
"@

        try {
            Invoke-PSWebSQLiteNonQuery -File $taskDbPath -Query $createSchema
            Write-Verbose "$MyTag Created multi-node task database: $taskDbPath" -Verbose

            # Register this node in the Nodes table
            $currentNodeID = $PSWebServer['Config'].WebServer.NodeID ?? (New-Guid).ToString()
            $hostname = [System.Net.Dns]::GetHostName()
            $port = $PSWebServer['Config'].WebServer.Port ?? 8080

            $registerNode = @"
INSERT OR REPLACE INTO Nodes (
    NodeID, NodeName, NodeGroup, NodeRole, Hostname, Port,
    Status, Version, LastHeartbeat, ModifiedAt
) VALUES (
    '$currentNodeID',
    '$hostname',
    'default',
    'standalone',
    '$hostname',
    $port,
    'Active',
    '1.0.0',
    datetime('now'),
    datetime('now')
);
"@

            Invoke-PSWebSQLiteNonQuery -File $taskDbPath -Query $registerNode
            Write-Verbose "$MyTag Registered node: $currentNodeID ($hostname)" -Verbose

        } catch {
            Write-Warning "$MyTag Failed to create task database: $_"
        }
    }

    # 6. Load initial task inventory (for dashboard)
    if (Get-Command Get-AllTasks -ErrorAction SilentlyContinue) {
        try {
            $taskInventory = Get-AllTasks
            $PSWebServer['WebHostTaskManagement'].Stats.TasksManaged = $taskInventory.Count
            Write-Verbose "$MyTag Loaded $($taskInventory.Count) tasks" -Verbose
        } catch {
            Write-Verbose "$MyTag Could not load initial task inventory: $_" -Verbose
        }
    }

    Write-Host "$MyTag Task management system initialized" -ForegroundColor Green
    Write-Verbose "$MyTag Data path: $DataPath"
    Write-Verbose "$MyTag Task database: $taskDbPath"
    Write-Verbose "$MyTag Runtime config: $runtimeConfigPath"

} catch {
    Write-Warning "$MyTag Failed to initialize: $($_.Exception.Message)"
    Write-Warning "$MyTag Server will continue without task management UI"
}
