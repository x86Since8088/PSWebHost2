# Database Migration: Add Shared Buckets Support
# This script adds the Shared_Buckets and Bucket_Access_Log tables
# and extends User_Groups with ownership tracking

param(
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# Determine project root
$projectRoot = if ($Global:PSWebServer.Project_Root.Path) {
    $Global:PSWebServer.Project_Root.Path
} else {
    # Running standalone - find project root
    $scriptPath = $PSScriptRoot
    $root = Split-Path (Split-Path (Split-Path $scriptPath))
    $root
}

# Get database path
$dbFile = Join-Path $projectRoot "PsWebHost_Data\pswebhost.db"

# Load required modules if not already loaded
if (-not (Get-Command Invoke-PSWebSQLiteNonQuery -ErrorAction SilentlyContinue)) {
    $dbModule = Join-Path $projectRoot "modules\PSWebHost_Database\PSWebHost_Database.psm1"
    if (Test-Path $dbModule) {
        Import-Module $dbModule -Force
    } else {
        Write-Host "Error: Could not find PSWebHost_Database module at: $dbModule" -ForegroundColor Red
        exit 1
    }
}

Write-Host "=== Database Migration: Add Shared Buckets Support ===" -ForegroundColor Cyan
Write-Host "Project Root: $projectRoot" -ForegroundColor Gray
Write-Host "Database: $dbFile" -ForegroundColor Gray

if ($WhatIf) {
    Write-Host "[WHATIF] Running in preview mode - no changes will be made" -ForegroundColor Yellow
}

# Function to execute SQL with WhatIf support
function Invoke-MigrationSQL {
    param(
        [string]$Query,
        [string]$Description
    )

    Write-Host "`n[STEP] $Description" -ForegroundColor Green
    Write-Host $Query -ForegroundColor DarkGray

    if (-not $WhatIf) {
        try {
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $Query
            Write-Host "  ✓ Success" -ForegroundColor Green
        } catch {
            Write-Host "  ✗ Error: $_" -ForegroundColor Red
            throw
        }
    } else {
        Write-Host "  [WHATIF] Would execute this SQL" -ForegroundColor Yellow
    }
}

# Check if migration has already been applied
$checkQuery = "SELECT name FROM sqlite_master WHERE type='table' AND name='Shared_Buckets';"
$bucketTableExists = Get-PSWebSQLiteData -File $dbFile -Query $checkQuery

if ($bucketTableExists) {
    Write-Host "`n[INFO] Shared_Buckets table already exists. Migration may have been applied." -ForegroundColor Yellow
    $continue = Read-Host "Continue anyway? (y/n)"
    if ($continue -ne 'y') {
        Write-Host "Migration aborted." -ForegroundColor Yellow
        return
    }
}

# Step 1: Create Shared_Buckets table
$createBucketsTable = @"
CREATE TABLE IF NOT EXISTS Shared_Buckets (
    BucketID TEXT PRIMARY KEY,
    Name TEXT UNIQUE NOT NULL,
    Description TEXT,
    OwnerUserID TEXT NOT NULL,
    OwnerGroupID TEXT NOT NULL,
    ReadGroupID TEXT NOT NULL,
    WriteGroupID TEXT NOT NULL,
    Created TEXT NOT NULL,
    Updated TEXT NOT NULL,
    FOREIGN KEY (OwnerUserID) REFERENCES Users(UserID) ON DELETE CASCADE,
    FOREIGN KEY (OwnerGroupID) REFERENCES User_Groups(GroupID) ON DELETE RESTRICT,
    FOREIGN KEY (ReadGroupID) REFERENCES User_Groups(GroupID) ON DELETE RESTRICT,
    FOREIGN KEY (WriteGroupID) REFERENCES User_Groups(GroupID) ON DELETE RESTRICT
);
"@

Invoke-MigrationSQL -Query $createBucketsTable -Description "Create Shared_Buckets table"

# Step 2: Create Bucket_Access_Log table
$createLogTable = @"
CREATE TABLE IF NOT EXISTS Bucket_Access_Log (
    LogID TEXT PRIMARY KEY,
    BucketID TEXT NOT NULL,
    UserID TEXT NOT NULL,
    Action TEXT NOT NULL,
    Path TEXT,
    Timestamp TEXT NOT NULL,
    Success INTEGER DEFAULT 1,
    ErrorMessage TEXT,
    FOREIGN KEY (BucketID) REFERENCES Shared_Buckets(BucketID) ON DELETE CASCADE
);
"@

Invoke-MigrationSQL -Query $createLogTable -Description "Create Bucket_Access_Log table"

# Step 3: Add OwnerUserID column to User_Groups (if not exists)
$checkOwnerColumn = "PRAGMA table_info(User_Groups);"
$columns = Get-PSWebSQLiteData -File $dbFile -Query $checkOwnerColumn
$hasOwnerUserID = $columns | Where-Object { $_.name -eq 'OwnerUserID' }

if (-not $hasOwnerUserID) {
    $addOwnerColumn = "ALTER TABLE User_Groups ADD COLUMN OwnerUserID TEXT;"
    Invoke-MigrationSQL -Query $addOwnerColumn -Description "Add OwnerUserID column to User_Groups"
} else {
    Write-Host "`n[SKIP] OwnerUserID column already exists in User_Groups" -ForegroundColor Yellow
}

# Step 4: Add GroupType column to User_Groups (if not exists)
$hasGroupType = $columns | Where-Object { $_.name -eq 'GroupType' }

if (-not $hasGroupType) {
    $addGroupTypeColumn = "ALTER TABLE User_Groups ADD COLUMN GroupType TEXT DEFAULT 'manual';"
    Invoke-MigrationSQL -Query $addGroupTypeColumn -Description "Add GroupType column to User_Groups"
} else {
    Write-Host "`n[SKIP] GroupType column already exists in User_Groups" -ForegroundColor Yellow
}

# Step 5: Create indexes for performance
$createIndexes = @"
CREATE INDEX IF NOT EXISTS idx_bucket_name ON Shared_Buckets(Name COLLATE NOCASE);
CREATE INDEX IF NOT EXISTS idx_bucket_owner ON Shared_Buckets(OwnerUserID);
CREATE INDEX IF NOT EXISTS idx_bucket_access_log_bucket ON Bucket_Access_Log(BucketID);
CREATE INDEX IF NOT EXISTS idx_bucket_access_log_user ON Bucket_Access_Log(UserID);
CREATE INDEX IF NOT EXISTS idx_group_owner ON User_Groups(OwnerUserID);
"@

Invoke-MigrationSQL -Query $createIndexes -Description "Create performance indexes"

# Step 6: Create SharedBuckets directory
$bucketStoragePath = Join-Path $projectRoot "PsWebHost_Data\SharedBuckets"
Write-Host "`n[STEP] Create SharedBuckets storage directory" -ForegroundColor Green
Write-Host "Path: $bucketStoragePath" -ForegroundColor DarkGray

if (-not $WhatIf) {
    if (-not (Test-Path $bucketStoragePath)) {
        New-Item -Path $bucketStoragePath -ItemType Directory -Force | Out-Null
        Write-Host "  ✓ Directory created" -ForegroundColor Green
    } else {
        Write-Host "  ✓ Directory already exists" -ForegroundColor Green
    }
} else {
    Write-Host "  [WHATIF] Would create directory: $bucketStoragePath" -ForegroundColor Yellow
}

# Step 7: Verify migration
Write-Host "`n=== Verification ===" -ForegroundColor Cyan

if (-not $WhatIf) {
    # Check Shared_Buckets table
    $verifyBuckets = "SELECT name FROM sqlite_master WHERE type='table' AND name='Shared_Buckets';"
    $bucketsExists = Get-PSWebSQLiteData -File $dbFile -Query $verifyBuckets

    if ($bucketsExists) {
        Write-Host "✓ Shared_Buckets table exists" -ForegroundColor Green
    } else {
        Write-Host "✗ Shared_Buckets table NOT found" -ForegroundColor Red
    }

    # Check Bucket_Access_Log table
    $verifyLog = "SELECT name FROM sqlite_master WHERE type='table' AND name='Bucket_Access_Log';"
    $logExists = Get-PSWebSQLiteData -File $dbFile -Query $verifyLog

    if ($logExists) {
        Write-Host "✓ Bucket_Access_Log table exists" -ForegroundColor Green
    } else {
        Write-Host "✗ Bucket_Access_Log table NOT found" -ForegroundColor Red
    }

    # Check User_Groups columns
    $verifyColumns = "PRAGMA table_info(User_Groups);"
    $ugColumns = Get-PSWebSQLiteData -File $dbFile -Query $verifyColumns

    $hasOwner = $ugColumns | Where-Object { $_.name -eq 'OwnerUserID' }
    $hasType = $ugColumns | Where-Object { $_.name -eq 'GroupType' }

    if ($hasOwner) {
        Write-Host "✓ User_Groups.OwnerUserID column exists" -ForegroundColor Green
    } else {
        Write-Host "✗ User_Groups.OwnerUserID column NOT found" -ForegroundColor Red
    }

    if ($hasType) {
        Write-Host "✓ User_Groups.GroupType column exists" -ForegroundColor Green
    } else {
        Write-Host "✗ User_Groups.GroupType column NOT found" -ForegroundColor Red
    }

    # Check indexes
    $verifyIndexes = "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%bucket%';"
    $indexes = Get-PSWebSQLiteData -File $dbFile -Query $verifyIndexes

    Write-Host "✓ Created $($indexes.Count) bucket-related indexes" -ForegroundColor Green

    # Check storage directory
    if (Test-Path $bucketStoragePath) {
        Write-Host "✓ SharedBuckets storage directory exists" -ForegroundColor Green
    } else {
        Write-Host "✗ SharedBuckets storage directory NOT found" -ForegroundColor Red
    }

    Write-Host "`n=== Migration Complete ===" -ForegroundColor Cyan
    Write-Host "Database schema has been updated to support shared buckets." -ForegroundColor Green
} else {
    Write-Host "[WHATIF] Migration would complete successfully (pending actual execution)" -ForegroundColor Yellow
}
