#Requires -Version 7

<#
.SYNOPSIS
    WebHostTaskManagement App Initialization Script

.DESCRIPTION
    Initializes the task management system with granular error handling.
    Each step has its own try-catch for better fault isolation.

.NOTES
    This script runs during PSWebHost startup when WebHostTaskManagement app is loaded.
    Uses Write-PSWebHostLog for centralized logging.
#>

param(
    [hashtable]$PSWebServer,
    [string]$AppRoot
)

$MyTag = '[WebHostTaskManagement:Init]'
$Category = 'AppInit'

Write-PSWebHostLog -Severity 'Info' -Category $Category -Message "========== Initializing Task Management System =========="

# ============================================================================
# Step 1: Import App Module
# ============================================================================
try {
    $modulePath = Join-Path $AppRoot "modules\PSWebHost_TaskManagement"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force -ErrorAction Stop
        Write-PSWebHostLog -Severity 'Info' -Category $Category -Message "Loaded PSWebHost_TaskManagement module from: $modulePath"
    } else {
        Write-PSWebHostLog -Severity 'Warning' -Category $Category -Message "PSWebHost_TaskManagement module not found at: $modulePath"
    }
} catch {
    Write-PSWebHostLog -Severity 'Error' -Category $Category -Message "Failed to load PSWebHost_TaskManagement module: $($_.Exception.Message)" -Data @{
        ModulePath = $modulePath
        Error = $_.Exception.ToString()
    }
}

# ============================================================================
# Step 2: Verify PSWebHost_Jobs Module (New System)
# ============================================================================
try {
    if (-not (Get-Module PSWebHost_Jobs -ErrorAction SilentlyContinue)) {
        Write-PSWebHostLog -Severity 'Warning' -Category $Category -Message "PSWebHost_Jobs module not loaded - job catalog features will be limited"
    } else {
        $jobsModule = Get-Module PSWebHost_Jobs
        Write-PSWebHostLog -Severity 'Info' -Category $Category -Message "PSWebHost_Jobs module available (v$($jobsModule.Version))"
    }
} catch {
    Write-PSWebHostLog -Severity 'Error' -Category $Category -Message "Error checking PSWebHost_Jobs module: $($_.Exception.Message)"
}

# ============================================================================
# Step 3: Initialize App Namespace
# ============================================================================
try {
    $dataRoot = if ($PSWebServer['DataPath']) { $PSWebServer['DataPath'] } else { $PSWebServer['DataRoot'] }

    $PSWebServer['WebHostTaskManagement'] = [hashtable]::Synchronized(@{
        AppRoot = $AppRoot
        DataPath = Join-Path $dataRoot "apps\WebHostTaskManagement"
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
        TaskDatabasePath = Join-Path $dataRoot "tasks.db"
    })

    Write-PSWebHostLog -Severity 'Info' -Category $Category -Message "Initialized app namespace"
} catch {
    Write-PSWebHostLog -Severity 'Error' -Category $Category -Message "Failed to initialize app namespace: $($_.Exception.Message)" -Data @{
        Error = $_.Exception.ToString()
    }
    # Continue even if this fails - might be able to recover
}

# ============================================================================
# Step 4: Create Data Directories
# ============================================================================
try {
    $dataPath = $PSWebServer['WebHostTaskManagement'].DataPath

    if (-not (Test-Path $dataPath)) {
        New-Item -Path $dataPath -ItemType Directory -Force | Out-Null
        Write-PSWebHostLog -Severity 'Info' -Category $Category -Message "Created data directory: $dataPath"
    } else {
        Write-PSWebHostLog -Severity 'Verbose' -Category $Category -Message "Data directory exists: $dataPath"
    }

    # Create subdirectories
    $subDirs = @('exports', 'backups', 'logs')
    foreach ($subDir in $subDirs) {
        $subDirPath = Join-Path $dataPath $subDir
        if (-not (Test-Path $subDirPath)) {
            New-Item -Path $subDirPath -ItemType Directory -Force | Out-Null
            Write-PSWebHostLog -Severity 'Verbose' -Category $Category -Message "Created subdirectory: $subDir"
        }
    }

    Write-PSWebHostLog -Severity 'Info' -Category $Category -Message "Data directories verified"
} catch {
    Write-PSWebHostLog -Severity 'Error' -Category $Category -Message "Failed to create data directories: $($_.Exception.Message)" -Data @{
        DataPath = $dataPath
        Error = $_.Exception.ToString()
    }
}

# ============================================================================
# Step 5: Initialize Runtime Task Configuration
# ============================================================================
try {
    $dataRoot = if ($PSWebServer['DataPath']) { $PSWebServer['DataPath'] } else { $PSWebServer['DataRoot'] }
    $runtimeConfigPath = Join-Path $dataRoot "config\tasks.json"
    $configDir = Split-Path $runtimeConfigPath -Parent

    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
        Write-PSWebHostLog -Severity 'Verbose' -Category $Category -Message "Created config directory: $configDir"
    }

    if (-not (Test-Path $runtimeConfigPath)) {
        # Create initial empty configuration
        $initialConfig = @{
            version = "1.0"
            lastModified = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            tasks = @()
        }
        $initialConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $runtimeConfigPath -ErrorAction Stop
        Write-PSWebHostLog -Severity 'Info' -Category $Category -Message "Created runtime task configuration: $runtimeConfigPath"
    } else {
        Write-PSWebHostLog -Severity 'Verbose' -Category $Category -Message "Runtime task configuration exists: $runtimeConfigPath"
    }
} catch {
    Write-PSWebHostLog -Severity 'Error' -Category $Category -Message "Failed to initialize runtime task configuration: $($_.Exception.Message)" -Data @{
        ConfigPath = $runtimeConfigPath
        Error = $_.Exception.ToString()
    }
}

# ============================================================================
# Step 6: Initialize Task Database
# ============================================================================
try {
    $taskDbPath = $PSWebServer['WebHostTaskManagement'].TaskDatabasePath

    if (-not (Test-Path $taskDbPath)) {
        Write-PSWebHostLog -Severity 'Info' -Category $Category -Message "Creating task database schema..."

        # Create comprehensive task database schema with multi-node support
        $createSchema = @"
-- ============================================================================
-- Nodes Table - Registry of WebHost nodes in the cluster
-- ============================================================================
CREATE TABLE IF NOT EXISTS Nodes (
    NodeID TEXT PRIMARY KEY,
    NodeName TEXT NOT NULL,
    NodeGroup TEXT,
    NodeRole TEXT,
    Hostname TEXT,
    IPAddress TEXT,
    Port INTEGER,
    Status TEXT DEFAULT 'Active',
    Version TEXT,
    Capabilities TEXT,
    LastHeartbeat TEXT,
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
    TaskName TEXT NOT NULL,
    AppName TEXT,
    Source TEXT DEFAULT 'custom',
    ScriptPath TEXT NOT NULL,
    Description TEXT,
    Schedule TEXT,
    Enabled INTEGER DEFAULT 1,
    AssignedNodeID TEXT,
    AssignedNodeGroup TEXT,
    AssignedNodeRole TEXT,
    MaxRuntime INTEGER,
    MaxFailures INTEGER,
    KillOnTimeout INTEGER DEFAULT 1,
    Environment TEXT,
    Configuration TEXT,
    CreatedBy TEXT,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    DeletedAt TEXT,
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
    NextRun TEXT,
    LastRun TEXT,
    ClaimedBy TEXT,
    ClaimedAt TEXT,
    ClaimExpiry TEXT,
    Status TEXT DEFAULT 'Pending',
    CurrentJobID INTEGER,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (TaskID) REFERENCES Tasks(TaskID)
);

CREATE INDEX IF NOT EXISTS idx_schedule_next_run ON Task_Schedule(NextRun);
CREATE INDEX IF NOT EXISTS idx_schedule_claimed ON Task_Schedule(ClaimedBy);
CREATE INDEX IF NOT EXISTS idx_schedule_status ON Task_Schedule(Status);
CREATE INDEX IF NOT EXISTS idx_schedule_task ON Task_Schedule(TaskID);

-- ============================================================================
-- Task_History Table - Task execution history
-- ============================================================================
CREATE TABLE IF NOT EXISTS Task_History (
    HistoryID INTEGER PRIMARY KEY AUTOINCREMENT,
    TaskID INTEGER,
    TaskName TEXT NOT NULL,
    AppName TEXT,
    ExecutedBy TEXT NOT NULL,
    StartTime TEXT NOT NULL,
    EndTime TEXT,
    Duration INTEGER,
    Status TEXT NOT NULL,
    ExitCode INTEGER,
    Output TEXT,
    ErrorMessage TEXT,
    TriggeredBy TEXT,
    TriggeredByUser TEXT,
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
    TableName TEXT NOT NULL,
    RecordID TEXT NOT NULL,
    Action TEXT NOT NULL,
    OldData TEXT,
    NewData TEXT,
    ChangedBy TEXT,
    ChangedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    SyncedNodes TEXT
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
            Write-PSWebHostLog -Severity 'Info' -Category $Category -Message "Created multi-node task database: $taskDbPath"

            # Register this node in the Nodes table
            $currentNodeID = if ($PSWebServer['Config'].WebServer.NodeID) {
                $PSWebServer['Config'].WebServer.NodeID
            } else {
                (New-Guid).ToString()
            }

            $hostname = [System.Net.Dns]::GetHostName()
            $port = if ($PSWebServer['Config'].WebServer.Port) {
                $PSWebServer['Config'].WebServer.Port
            } else {
                8080
            }

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
            Write-PSWebHostLog -Severity 'Info' -Category $Category -Message "Registered node in database" -Data @{
                NodeID = $currentNodeID
                Hostname = $hostname
                Port = $port
            }

        } catch {
            Write-PSWebHostLog -Severity 'Error' -Category $Category -Message "Failed to create task database: $($_.Exception.Message)" -Data @{
                DatabasePath = $taskDbPath
                Error = $_.Exception.ToString()
            }
        }
    } else {
        Write-PSWebHostLog -Severity 'Verbose' -Category $Category -Message "Task database exists: $taskDbPath"
    }
} catch {
    Write-PSWebHostLog -Severity 'Error' -Category $Category -Message "Database initialization failed: $($_.Exception.Message)" -Data @{
        Error = $_.Exception.ToString()
    }
}

# ============================================================================
# Step 7: Load Initial Task Inventory
# ============================================================================
try {
    if (Get-Command Get-AllTasks -ErrorAction SilentlyContinue) {
        $taskInventory = Get-AllTasks
        $PSWebServer['WebHostTaskManagement'].Stats.TasksManaged = $taskInventory.Count
        Write-PSWebHostLog -Severity 'Info' -Category $Category -Message "Loaded task inventory: $($taskInventory.Count) tasks"
    } else {
        Write-PSWebHostLog -Severity 'Verbose' -Category $Category -Message "Get-AllTasks command not available (PSWebHostTasks module may not be loaded)"
    }
} catch {
    Write-PSWebHostLog -Severity 'Warning' -Category $Category -Message "Could not load initial task inventory: $($_.Exception.Message)"
}

# ============================================================================
# Initialization Complete
# ============================================================================
Write-PSWebHostLog -Severity 'Info' -Category $Category -Message "========== Task Management System Initialized =========="
Write-PSWebHostLog -Severity 'Info' -Category $Category -Message "Configuration summary:" -Data @{
    DataPath = $PSWebServer['WebHostTaskManagement'].DataPath
    DatabasePath = $PSWebServer['WebHostTaskManagement'].TaskDatabasePath
    TasksManaged = $PSWebServer['WebHostTaskManagement'].Stats.TasksManaged
}
