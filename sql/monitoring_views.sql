-- ============================================================
-- Monitoring Views
-- Database health, query performance, blocking analysis
-- and pipeline execution dashboards
-- ============================================================

-- Pipeline execution summary (last 7 days)
CREATE OR ALTER VIEW meta.vw_PipelineSummary
AS
SELECT
    CAST(StartTime AS DATE)         AS RunDate,
    PipelineName,
    TargetLayer,
    COUNT(*)                        AS TotalRuns,
    SUM(CASE WHEN Status = 'Succeeded' THEN 1 ELSE 0 END) AS Succeeded,
    SUM(CASE WHEN Status = 'Failed' THEN 1 ELSE 0 END)    AS Failed,
    ROUND(
        CAST(SUM(CASE WHEN Status = 'Succeeded' THEN 1 ELSE 0 END) AS FLOAT) /
        NULLIF(COUNT(*), 0) * 100, 1
    )                               AS SuccessRatePct,
    SUM(RowsWritten)                AS TotalRowsWritten,
    AVG(DATEDIFF(SECOND, StartTime, EndTime)) AS AvgDurationSec
FROM meta.PipelineRun
WHERE StartTime >= DATEADD(DAY, -7, SYSUTCDATETIME())
GROUP BY CAST(StartTime AS DATE), PipelineName, TargetLayer;
GO

-- Data quality dashboard
CREATE OR ALTER VIEW meta.vw_QualityDashboard
AS
SELECT
    pr.PipelineName,
    pr.TargetLayer,
    qc.CheckName,
    qc.CheckType,
    qc.Passed,
    qc.RecordsChecked,
    qc.RecordsFailed,
    qc.Details,
    qc.CheckedAt
FROM meta.QualityCheckResult qc
JOIN meta.PipelineRun pr ON qc.RunId = pr.RunId
WHERE qc.CheckedAt >= DATEADD(DAY, -7, SYSUTCDATETIME());
GO

-- Top queries by CPU (for performance tuning)
CREATE OR ALTER VIEW dbo.vw_TopQueriesByCPU
AS
SELECT TOP 20
    qs.total_worker_time / qs.execution_count   AS AvgCPUTime,
    qs.execution_count                           AS ExecutionCount,
    qs.total_worker_time                         AS TotalCPUTime,
    qs.total_logical_reads / qs.execution_count  AS AvgLogicalReads,
    SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset) / 2) + 1) AS QueryText,
    qs.last_execution_time                       AS LastExecuted,
    qp.query_plan                                AS ExecutionPlan
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
ORDER BY qs.total_worker_time DESC;
GO

-- Blocking sessions
CREATE OR ALTER VIEW dbo.vw_BlockingSessions
AS
SELECT
    r.session_id                 AS BlockedSessionId,
    r.blocking_session_id        AS BlockingSessionId,
    r.wait_type                  AS WaitType,
    r.wait_time / 1000.0         AS WaitTimeSec,
    r.status                     AS RequestStatus,
    t.text                       AS BlockedQuery,
    s.login_name                 AS BlockedLogin,
    s.host_name                  AS BlockedHost
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id > 0;
GO

-- Database size and growth
CREATE OR ALTER VIEW dbo.vw_DatabaseSize
AS
SELECT
    DB_NAME()                    AS DatabaseName,
    f.name                       AS FileName,
    f.type_desc                  AS FileType,
    CAST(f.size * 8.0 / 1024 AS DECIMAL(10,2))            AS SizeMB,
    CAST(FILEPROPERTY(f.name, 'SpaceUsed') * 8.0 / 1024 AS DECIMAL(10,2)) AS UsedMB,
    CAST((f.size - FILEPROPERTY(f.name, 'SpaceUsed')) * 8.0 / 1024 AS DECIMAL(10,2)) AS FreeMB,
    CAST(FILEPROPERTY(f.name, 'SpaceUsed') * 100.0 / f.size AS DECIMAL(5,1)) AS UsedPct
FROM sys.database_files f;
GO

PRINT 'Monitoring views created.';
