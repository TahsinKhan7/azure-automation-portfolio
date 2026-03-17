-- ============================================================
-- Pipeline Metadata Tables
-- Track ETL pipeline execution, data lineage and row counts
-- across the medallion architecture layers
-- ============================================================

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'meta')
    EXEC('CREATE SCHEMA meta');
GO

-- Pipeline run tracking
CREATE TABLE meta.PipelineRun (
    RunId           UNIQUEIDENTIFIER DEFAULT NEWID() PRIMARY KEY,
    PipelineName    NVARCHAR(200)    NOT NULL,
    SourceSystem    NVARCHAR(100)    NOT NULL,
    TargetLayer     NVARCHAR(20)     NOT NULL CHECK (TargetLayer IN ('bronze', 'silver', 'gold')),
    StartTime       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    EndTime         DATETIME2        NULL,
    Status          NVARCHAR(20)     NOT NULL DEFAULT 'Running' CHECK (Status IN ('Running', 'Succeeded', 'Failed', 'Cancelled')),
    RowsRead        BIGINT           NULL,
    RowsWritten     BIGINT           NULL,
    RowsErrored     BIGINT           NULL DEFAULT 0,
    ErrorMessage    NVARCHAR(MAX)    NULL,
    TriggeredBy     NVARCHAR(100)    NULL,
    ADFRunId        NVARCHAR(100)    NULL,
    CreatedAt       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- Data quality check results
CREATE TABLE meta.QualityCheckResult (
    CheckId         BIGINT IDENTITY(1,1) PRIMARY KEY,
    RunId           UNIQUEIDENTIFIER NOT NULL REFERENCES meta.PipelineRun(RunId),
    CheckName       NVARCHAR(200)    NOT NULL,
    CheckType       NVARCHAR(50)     NOT NULL,  -- not_null, unique, accepted_values, freshness, row_count
    Passed          BIT              NOT NULL,
    RecordsChecked  BIGINT           NOT NULL,
    RecordsFailed   BIGINT           NOT NULL DEFAULT 0,
    Details         NVARCHAR(500)    NULL,
    CheckedAt       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- Data lineage tracking
CREATE TABLE meta.DataLineage (
    LineageId       BIGINT IDENTITY(1,1) PRIMARY KEY,
    RunId           UNIQUEIDENTIFIER NOT NULL REFERENCES meta.PipelineRun(RunId),
    SourcePath      NVARCHAR(500)    NOT NULL,
    TargetPath      NVARCHAR(500)    NOT NULL,
    TransformType   NVARCHAR(100)    NULL,  -- cleanse, aggregate, join, filter
    ColumnMapping   NVARCHAR(MAX)    NULL,  -- JSON mapping of source->target columns
    CreatedAt       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- Watermark table for incremental loads
CREATE TABLE meta.Watermark (
    WatermarkId     INT IDENTITY(1,1) PRIMARY KEY,
    TableName       NVARCHAR(200)    NOT NULL UNIQUE,
    WatermarkColumn NVARCHAR(100)    NOT NULL,
    WatermarkValue  NVARCHAR(100)    NOT NULL,
    LastUpdated     DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- Helper: Mark pipeline run as succeeded
CREATE OR ALTER PROCEDURE meta.usp_CompletePipelineRun
    @RunId          UNIQUEIDENTIFIER,
    @RowsRead       BIGINT = NULL,
    @RowsWritten    BIGINT = NULL,
    @RowsErrored    BIGINT = 0
AS
BEGIN
    UPDATE meta.PipelineRun
    SET EndTime      = SYSUTCDATETIME(),
        Status       = 'Succeeded',
        RowsRead     = @RowsRead,
        RowsWritten  = @RowsWritten,
        RowsErrored  = @RowsErrored
    WHERE RunId = @RunId;
END;
GO

-- Helper: Mark pipeline run as failed
CREATE OR ALTER PROCEDURE meta.usp_FailPipelineRun
    @RunId          UNIQUEIDENTIFIER,
    @ErrorMessage   NVARCHAR(MAX)
AS
BEGIN
    UPDATE meta.PipelineRun
    SET EndTime      = SYSUTCDATETIME(),
        Status       = 'Failed',
        ErrorMessage = @ErrorMessage
    WHERE RunId = @RunId;
END;
GO

-- Index for common queries
CREATE NONCLUSTERED INDEX IX_PipelineRun_Status_StartTime
    ON meta.PipelineRun (Status, StartTime DESC)
    INCLUDE (PipelineName, RowsWritten);
GO

CREATE NONCLUSTERED INDEX IX_QualityCheck_RunId
    ON meta.QualityCheckResult (RunId)
    INCLUDE (CheckName, Passed);
GO

PRINT 'Pipeline metadata tables created successfully.';
