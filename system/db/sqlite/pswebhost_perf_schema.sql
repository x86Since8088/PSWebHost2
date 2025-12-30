-- Performance Monitoring Database Schema
-- pswebhost_perf.db

-- Web Request Performance Table
CREATE TABLE IF NOT EXISTS WebRequestPerformance (
    RequestID TEXT PRIMARY KEY,
    StartTime TEXT NOT NULL,
    EndTime TEXT,
    FilePath TEXT NOT NULL,
    HttpMethod TEXT NOT NULL,
    UserID TEXT,
    AuthenticationProvider TEXT,
    ExecutionTimeMicroseconds INTEGER,
    LogFileSizeBefore INTEGER,
    LogFileSizeAfter INTEGER,
    LogFileSizeDelta INTEGER,
    StatusCode INTEGER,
    StatusText TEXT,
    IPAddress TEXT,
    UserAgent TEXT,
    SessionID TEXT,
    Completed INTEGER DEFAULT 0,
    CreatedAt TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_webrequest_starttime ON WebRequestPerformance(StartTime);
CREATE INDEX IF NOT EXISTS idx_webrequest_filepath ON WebRequestPerformance(FilePath);
CREATE INDEX IF NOT EXISTS idx_webrequest_userid ON WebRequestPerformance(UserID);
CREATE INDEX IF NOT EXISTS idx_webrequest_completed ON WebRequestPerformance(Completed);
CREATE INDEX IF NOT EXISTS idx_webrequest_exectime ON WebRequestPerformance(ExecutionTimeMicroseconds);

-- System Performance Metrics Table
CREATE TABLE IF NOT EXISTS SystemPerformance (
    MetricID INTEGER PRIMARY KEY AUTOINCREMENT,
    Timestamp TEXT NOT NULL,
    CPUPercent REAL,
    MemoryUsedGB REAL,
    MemoryPercentUsed REAL,
    ProcessCount INTEGER,
    ThreadCount INTEGER,
    HandleCount INTEGER,
    CreatedAt TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_sysperf_timestamp ON SystemPerformance(Timestamp);

-- Performance Summary View
CREATE VIEW IF NOT EXISTS vw_RequestPerformanceSummary AS
SELECT
    FilePath,
    COUNT(*) as RequestCount,
    AVG(ExecutionTimeMicroseconds) as AvgExecutionMicroseconds,
    MIN(ExecutionTimeMicroseconds) as MinExecutionMicroseconds,
    MAX(ExecutionTimeMicroseconds) as MaxExecutionMicroseconds,
    SUM(LogFileSizeDelta) as TotalLogGrowth,
    COUNT(DISTINCT UserID) as UniqueUsers
FROM WebRequestPerformance
WHERE Completed = 1
GROUP BY FilePath;

-- User Performance View
CREATE VIEW IF NOT EXISTS vw_UserPerformance AS
SELECT
    UserID,
    COUNT(*) as RequestCount,
    AVG(ExecutionTimeMicroseconds) as AvgExecutionMicroseconds,
    SUM(LogFileSizeDelta) as TotalLogGrowth
FROM WebRequestPerformance
WHERE Completed = 1 AND UserID IS NOT NULL
GROUP BY UserID;

-- Slow Requests View (> 1 second)
CREATE VIEW IF NOT EXISTS vw_SlowRequests AS
SELECT
    RequestID,
    StartTime,
    FilePath,
    UserID,
    ExecutionTimeMicroseconds,
    ExecutionTimeMicroseconds / 1000000.0 as ExecutionTimeSeconds
FROM WebRequestPerformance
WHERE Completed = 1 AND ExecutionTimeMicroseconds > 1000000
ORDER BY ExecutionTimeMicroseconds DESC;
