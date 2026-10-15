-- ============================================================================
-- Metadata-driven ingestion control tables for Azure Data Factory
--
-- One generic ADF pipeline (Lookup -> ForEach -> Copy -> Stored Procedure)
-- reads these tables to decide WHAT to copy, HOW (full vs incremental via
-- watermark), WHERE to land it and whether the run succeeded. Adding a new
-- source table is an INSERT, not a new pipeline.
--
-- Schema: ctl   (control)
-- ============================================================================
SET NOCOUNT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'ctl')
    EXEC('CREATE SCHEMA ctl');
GO

-- ---------------------------------------------------------------------------
-- Source systems and their linked service names
-- ---------------------------------------------------------------------------
IF OBJECT_ID('ctl.SourceSystem') IS NULL
CREATE TABLE ctl.SourceSystem (
    SourceSystemId      INT IDENTITY(1,1)   NOT NULL CONSTRAINT PK_SourceSystem PRIMARY KEY,
    SourceSystemCode    NVARCHAR(50)        NOT NULL CONSTRAINT UQ_SourceSystem_Code UNIQUE,
    Description         NVARCHAR(200)       NULL,
    SourceType          NVARCHAR(30)        NOT NULL CONSTRAINT CK_SourceSystem_Type
                                                 CHECK (SourceType IN ('AzureSql', 'SqlServer', 'Oracle', 'Blob', 'Adls', 'RestApi', 'Sftp')),
    LinkedServiceName   NVARCHAR(100)       NOT NULL,   -- ADF linked service (parameterised)
    KeyVaultSecretName  NVARCHAR(100)       NULL,       -- connection secret; never the value
    IsActive            BIT                 NOT NULL CONSTRAINT DF_SourceSystem_IsActive DEFAULT (1),
    CreatedAt           DATETIME2(3)        NOT NULL CONSTRAINT DF_SourceSystem_CreatedAt DEFAULT SYSUTCDATETIME(),
    ModifiedAt          DATETIME2(3)        NULL
);
GO

-- ---------------------------------------------------------------------------
-- Per-table ingestion configuration
-- ---------------------------------------------------------------------------
IF OBJECT_ID('ctl.IngestionConfig') IS NULL
CREATE TABLE ctl.IngestionConfig (
    ConfigId            INT IDENTITY(1,1)   NOT NULL CONSTRAINT PK_IngestionConfig PRIMARY KEY,
    SourceSystemId      INT                 NOT NULL CONSTRAINT FK_IngestionConfig_SourceSystem
                                                 REFERENCES ctl.SourceSystem(SourceSystemId),
    DatasetName         NVARCHAR(100)       NOT NULL,   -- logical name, e.g. claims (matches datasets.yml)
    SourceSchema        NVARCHAR(128)       NULL,
    SourceObject        NVARCHAR(256)       NOT NULL,   -- table/view name, folder path or API route
    SourceQuery         NVARCHAR(MAX)       NULL,       -- optional override; may contain @{watermark}
    LoadType            NVARCHAR(20)        NOT NULL CONSTRAINT CK_IngestionConfig_LoadType
                                                 CHECK (LoadType IN ('Full', 'Incremental', 'CDC')),
    WatermarkColumn     NVARCHAR(128)       NULL,       -- required for Incremental
    WatermarkDataType   NVARCHAR(20)        NULL CONSTRAINT CK_IngestionConfig_WmType
                                                 CHECK (WatermarkDataType IN ('datetime2', 'bigint', 'rowversion') OR WatermarkDataType IS NULL),
    PrimaryKeyColumns   NVARCHAR(400)       NULL,       -- comma separated; used downstream for dedup/merge
    TargetContainer     NVARCHAR(63)        NOT NULL CONSTRAINT DF_IngestionConfig_Container DEFAULT ('landing'),
    TargetFolderPattern NVARCHAR(400)       NOT NULL    -- e.g. claims/{yyyy}/{MM}/{dd}/
                                                 CONSTRAINT DF_IngestionConfig_Folder DEFAULT ('{dataset}/{yyyy}/{MM}/{dd}/'),
    TargetFileFormat    NVARCHAR(20)        NOT NULL CONSTRAINT CK_IngestionConfig_Format
                                                 CHECK (TargetFileFormat IN ('parquet', 'csv', 'json'))
                                                 CONSTRAINT DF_IngestionConfig_Format DEFAULT ('parquet'),
    PartitionColumn     NVARCHAR(128)       NULL,       -- enables parallel copy ranges in ADF
    ParallelCopies      TINYINT             NOT NULL CONSTRAINT DF_IngestionConfig_Parallel DEFAULT (4),
    DataIntegrationUnits SMALLINT           NOT NULL CONSTRAINT DF_IngestionConfig_DIU DEFAULT (4),
    ScheduleGroup       NVARCHAR(50)        NOT NULL CONSTRAINT DF_IngestionConfig_Group DEFAULT ('nightly'),
    Priority            SMALLINT            NOT NULL CONSTRAINT DF_IngestionConfig_Priority DEFAULT (100),
    MaxRetries          TINYINT             NOT NULL CONSTRAINT DF_IngestionConfig_Retries DEFAULT (2),
    IsActive            BIT                 NOT NULL CONSTRAINT DF_IngestionConfig_IsActive DEFAULT (1),
    Owner               NVARCHAR(100)       NULL,
    CreatedAt           DATETIME2(3)        NOT NULL CONSTRAINT DF_IngestionConfig_CreatedAt DEFAULT SYSUTCDATETIME(),
    ModifiedAt          DATETIME2(3)        NULL,
    CONSTRAINT UQ_IngestionConfig_Dataset UNIQUE (SourceSystemId, DatasetName),
    CONSTRAINT CK_IngestionConfig_Watermark CHECK (LoadType <> 'Incremental' OR WatermarkColumn IS NOT NULL)
);
GO

-- ---------------------------------------------------------------------------
-- Watermarks: one row per config, advanced only on success
-- ---------------------------------------------------------------------------
IF OBJECT_ID('ctl.Watermark') IS NULL
CREATE TABLE ctl.Watermark (
    ConfigId            INT                 NOT NULL CONSTRAINT PK_Watermark PRIMARY KEY
                                                 CONSTRAINT FK_Watermark_Config REFERENCES ctl.IngestionConfig(ConfigId),
    WatermarkValue      NVARCHAR(50)        NOT NULL CONSTRAINT DF_Watermark_Value DEFAULT ('1900-01-01T00:00:00'),
    PreviousValue       NVARCHAR(50)        NULL,
    UpdatedAt           DATETIME2(3)        NOT NULL CONSTRAINT DF_Watermark_UpdatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedByRunId      NVARCHAR(100)       NULL
);
GO

-- ---------------------------------------------------------------------------
-- Run log: one row per dataset per pipeline run
-- ---------------------------------------------------------------------------
IF OBJECT_ID('ctl.IngestionRunLog') IS NULL
CREATE TABLE ctl.IngestionRunLog (
    RunLogId            BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_IngestionRunLog PRIMARY KEY,
    ConfigId            INT                 NOT NULL CONSTRAINT FK_RunLog_Config REFERENCES ctl.IngestionConfig(ConfigId),
    AdfPipelineRunId    NVARCHAR(100)       NOT NULL,
    AdfActivityRunId    NVARCHAR(100)       NULL,
    TriggerName         NVARCHAR(100)       NULL,
    Status              NVARCHAR(20)        NOT NULL CONSTRAINT CK_RunLog_Status
                                                 CHECK (Status IN ('Running', 'Succeeded', 'Failed', 'Skipped')),
    WatermarkFrom       NVARCHAR(50)        NULL,
    WatermarkTo         NVARCHAR(50)        NULL,
    RowsRead            BIGINT              NULL,
    RowsCopied          BIGINT              NULL,
    RowsSkipped         BIGINT              NULL,
    BytesCopied         BIGINT              NULL,
    TargetPath          NVARCHAR(500)       NULL,
    DurationSeconds     INT                 NULL,
    ErrorMessage        NVARCHAR(MAX)       NULL,
    StartedAt           DATETIME2(3)        NOT NULL CONSTRAINT DF_RunLog_StartedAt DEFAULT SYSUTCDATETIME(),
    FinishedAt          DATETIME2(3)        NULL,
    INDEX IX_RunLog_Config_Started NONCLUSTERED (ConfigId, StartedAt DESC),
    INDEX IX_RunLog_PipelineRun    NONCLUSTERED (AdfPipelineRunId)
);
GO

-- ============================================================================
-- Stored procedures called by the generic ADF pipeline
-- ============================================================================

-- 1. Lookup activity: which datasets to run for a schedule group, with their
--    current watermark and a fully rendered source query.
CREATE OR ALTER PROCEDURE ctl.usp_GetIngestionWorkload
    @ScheduleGroup  NVARCHAR(50),
    @SourceSystemCode NVARCHAR(50) = NULL,     -- optional filter for targeted re-runs
    @DatasetName    NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        c.ConfigId,
        s.SourceSystemCode,
        s.SourceType,
        s.LinkedServiceName,
        s.KeyVaultSecretName,
        c.DatasetName,
        c.SourceSchema,
        c.SourceObject,
        c.LoadType,
        c.WatermarkColumn,
        c.WatermarkDataType,
        c.PrimaryKeyColumns,
        c.TargetContainer,
        c.TargetFolderPattern,
        c.TargetFileFormat,
        c.PartitionColumn,
        c.ParallelCopies,
        c.DataIntegrationUnits,
        c.MaxRetries,
        c.Priority,
        ISNULL(w.WatermarkValue, '1900-01-01T00:00:00')     AS WatermarkFrom,
        -- Render the extraction query once so ADF only has to pass it to the Copy source.
        CASE
            WHEN c.SourceQuery IS NOT NULL THEN
                REPLACE(c.SourceQuery, '@{watermark}', ISNULL(w.WatermarkValue, '1900-01-01T00:00:00'))
            WHEN c.LoadType = 'Incremental' THEN
                CONCAT('SELECT * FROM ', QUOTENAME(c.SourceSchema), '.', QUOTENAME(c.SourceObject),
                       ' WHERE ', QUOTENAME(c.WatermarkColumn), ' > ''', ISNULL(w.WatermarkValue, '1900-01-01T00:00:00'), '''')
            ELSE
                CONCAT('SELECT * FROM ', QUOTENAME(c.SourceSchema), '.', QUOTENAME(c.SourceObject))
        END                                                 AS SourceQueryRendered
    FROM ctl.IngestionConfig c
    JOIN ctl.SourceSystem s   ON s.SourceSystemId = c.SourceSystemId
    LEFT JOIN ctl.Watermark w ON w.ConfigId = c.ConfigId
    WHERE c.IsActive = 1
      AND s.IsActive = 1
      AND c.ScheduleGroup = @ScheduleGroup
      AND (@SourceSystemCode IS NULL OR s.SourceSystemCode = @SourceSystemCode)
      AND (@DatasetName IS NULL OR c.DatasetName = @DatasetName)
    ORDER BY c.Priority, c.DatasetName;
END;
GO

-- 2. Called before the Copy: records the attempt and computes the new
--    watermark upper bound from the source (passed in by a Lookup on the source).
CREATE OR ALTER PROCEDURE ctl.usp_StartIngestionRun
    @ConfigId           INT,
    @AdfPipelineRunId   NVARCHAR(100),
    @AdfActivityRunId   NVARCHAR(100) = NULL,
    @TriggerName        NVARCHAR(100) = NULL,
    @WatermarkTo        NVARCHAR(50)  = NULL,
    @RunLogId           BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @WatermarkFrom NVARCHAR(50);
    SELECT @WatermarkFrom = WatermarkValue FROM ctl.Watermark WHERE ConfigId = @ConfigId;

    INSERT INTO ctl.IngestionRunLog (ConfigId, AdfPipelineRunId, AdfActivityRunId, TriggerName, Status, WatermarkFrom, WatermarkTo)
    VALUES (@ConfigId, @AdfPipelineRunId, @AdfActivityRunId, @TriggerName, 'Running', @WatermarkFrom, @WatermarkTo);

    SET @RunLogId = SCOPE_IDENTITY();
END;
GO

-- 3. Called after the Copy (success or failure path). On success the watermark
--    is advanced atomically with the log update; on failure it is left alone so
--    the next run re-reads the same window.
CREATE OR ALTER PROCEDURE ctl.usp_CompleteIngestionRun
    @RunLogId       BIGINT,
    @Status         NVARCHAR(20),          -- Succeeded | Failed | Skipped
    @RowsRead       BIGINT        = NULL,
    @RowsCopied     BIGINT        = NULL,
    @RowsSkipped    BIGINT        = NULL,
    @BytesCopied    BIGINT        = NULL,
    @TargetPath     NVARCHAR(500) = NULL,
    @ErrorMessage   NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Status NOT IN ('Succeeded', 'Failed', 'Skipped')
        THROW 50001, 'Status must be Succeeded, Failed or Skipped', 1;

    BEGIN TRANSACTION;

    DECLARE @ConfigId INT, @WatermarkTo NVARCHAR(50), @StartedAt DATETIME2(3);
    SELECT @ConfigId = ConfigId, @WatermarkTo = WatermarkTo, @StartedAt = StartedAt
    FROM ctl.IngestionRunLog WITH (UPDLOCK)
    WHERE RunLogId = @RunLogId;

    IF @ConfigId IS NULL
        THROW 50002, 'Unknown RunLogId', 1;

    UPDATE ctl.IngestionRunLog
       SET Status          = @Status,
           RowsRead        = @RowsRead,
           RowsCopied      = @RowsCopied,
           RowsSkipped     = @RowsSkipped,
           BytesCopied     = @BytesCopied,
           TargetPath      = @TargetPath,
           ErrorMessage    = @ErrorMessage,
           FinishedAt      = SYSUTCDATETIME(),
           DurationSeconds = DATEDIFF(SECOND, @StartedAt, SYSUTCDATETIME())
     WHERE RunLogId = @RunLogId;

    IF @Status = 'Succeeded' AND @WatermarkTo IS NOT NULL
    BEGIN
        MERGE ctl.Watermark AS tgt
        USING (SELECT @ConfigId AS ConfigId) AS src ON tgt.ConfigId = src.ConfigId
        WHEN MATCHED THEN
            UPDATE SET PreviousValue  = tgt.WatermarkValue,
                       WatermarkValue = @WatermarkTo,
                       UpdatedAt      = SYSUTCDATETIME(),
                       UpdatedByRunId = CAST(@RunLogId AS NVARCHAR(100))
        WHEN NOT MATCHED THEN
            INSERT (ConfigId, WatermarkValue, UpdatedAt, UpdatedByRunId)
            VALUES (@ConfigId, @WatermarkTo, SYSUTCDATETIME(), CAST(@RunLogId AS NVARCHAR(100)));
    END;

    COMMIT TRANSACTION;
END;
GO

-- 4. Operational helper: reset a watermark to force a re-load window.
CREATE OR ALTER PROCEDURE ctl.usp_ResetWatermark
    @DatasetName    NVARCHAR(100),
    @SourceSystemCode NVARCHAR(50),
    @NewValue       NVARCHAR(50) = '1900-01-01T00:00:00'
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE w
       SET PreviousValue  = w.WatermarkValue,
           WatermarkValue = @NewValue,
           UpdatedAt      = SYSUTCDATETIME(),
           UpdatedByRunId = 'manual-reset'
    FROM ctl.Watermark w
    JOIN ctl.IngestionConfig c ON c.ConfigId = w.ConfigId
    JOIN ctl.SourceSystem s    ON s.SourceSystemId = c.SourceSystemId
    WHERE c.DatasetName = @DatasetName AND s.SourceSystemCode = @SourceSystemCode;

    IF @@ROWCOUNT = 0
        THROW 50003, 'No watermark found for that dataset/source', 1;
END;
GO

-- ---------------------------------------------------------------------------
-- Monitoring view used by the ADF monitor and alerting
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW ctl.vw_IngestionHealth
AS
WITH last_run AS (
    SELECT ConfigId, Status, StartedAt, FinishedAt, RowsCopied, ErrorMessage,
           ROW_NUMBER() OVER (PARTITION BY ConfigId ORDER BY StartedAt DESC) AS rn
    FROM ctl.IngestionRunLog
),
stats_7d AS (
    SELECT ConfigId,
           COUNT(*)                                                       AS Runs7d,
           SUM(CASE WHEN Status = 'Failed' THEN 1 ELSE 0 END)             AS Failures7d,
           AVG(CAST(DurationSeconds AS FLOAT))                            AS AvgDurationSec7d,
           AVG(CAST(RowsCopied AS FLOAT))                                 AS AvgRows7d
    FROM ctl.IngestionRunLog
    WHERE StartedAt >= DATEADD(DAY, -7, SYSUTCDATETIME())
    GROUP BY ConfigId
)
SELECT
    s.SourceSystemCode,
    c.DatasetName,
    c.LoadType,
    c.ScheduleGroup,
    c.IsActive,
    w.WatermarkValue,
    lr.Status                       AS LastStatus,
    lr.StartedAt                    AS LastStartedAt,
    lr.RowsCopied                   AS LastRowsCopied,
    DATEDIFF(HOUR, lr.FinishedAt, SYSUTCDATETIME()) AS HoursSinceLastSuccessOrFailure,
    st.Runs7d,
    st.Failures7d,
    CAST(ROUND(st.AvgDurationSec7d, 0) AS INT) AS AvgDurationSec7d,
    CASE
        WHEN lr.RowsCopied IS NOT NULL AND st.AvgRows7d > 0 AND lr.RowsCopied < st.AvgRows7d * 0.5 THEN 'LOW_VOLUME'
        WHEN lr.Status = 'Failed' THEN 'FAILED'
        WHEN c.ScheduleGroup = 'nightly' AND DATEDIFF(HOUR, lr.FinishedAt, SYSUTCDATETIME()) > 30 THEN 'STALE'
        ELSE 'OK'
    END                             AS HealthFlag,
    lr.ErrorMessage
FROM ctl.IngestionConfig c
JOIN ctl.SourceSystem s    ON s.SourceSystemId = c.SourceSystemId
LEFT JOIN ctl.Watermark w  ON w.ConfigId = c.ConfigId
LEFT JOIN last_run lr      ON lr.ConfigId = c.ConfigId AND lr.rn = 1
LEFT JOIN stats_7d st      ON st.ConfigId = c.ConfigId;
GO

-- ---------------------------------------------------------------------------
-- Seed data (idempotent) - the three datasets used across this portfolio
-- ---------------------------------------------------------------------------
MERGE ctl.SourceSystem AS tgt
USING (VALUES
    ('CLAIMS_OPS', 'Claims operations database', 'AzureSql', 'ls_azuresql_claims_ops', 'sql-claims-ops-connection'),
    ('POLICY_ADMIN', 'Policy administration JSON feed', 'Adls', 'ls_adls_policy_admin', NULL),
    ('CRM', 'Customer master extracts (parquet)', 'Adls', 'ls_adls_crm', NULL)
) AS src (SourceSystemCode, Description, SourceType, LinkedServiceName, KeyVaultSecretName)
ON tgt.SourceSystemCode = src.SourceSystemCode
WHEN NOT MATCHED THEN
    INSERT (SourceSystemCode, Description, SourceType, LinkedServiceName, KeyVaultSecretName)
    VALUES (src.SourceSystemCode, src.Description, src.SourceType, src.LinkedServiceName, src.KeyVaultSecretName);
GO

MERGE ctl.IngestionConfig AS tgt
USING (
    SELECT s.SourceSystemId, v.*
    FROM (VALUES
        ('CLAIMS_OPS',   'claims',    'dbo', 'Claims',      'Incremental', 'ModifiedAt', 'datetime2', 'ClaimId',      'landing', 'claims/{yyyy}/{MM}/{dd}/',    'parquet', 'ClaimId', 8, 8, 'nightly', 10),
        ('POLICY_ADMIN', 'policies',  NULL,  'policies/',   'Full',        NULL,         NULL,        'PolicyNumber', 'landing', 'policies/{yyyy}/{MM}/{dd}/',  'json',    NULL,      4, 4, 'nightly', 20),
        ('CRM',          'customers', NULL,  'customers/',  'Full',        NULL,         NULL,        'CustomerId',   'landing', 'customers/{yyyy}/{MM}/{dd}/', 'parquet', NULL,      4, 4, 'nightly', 30)
    ) AS v (SourceSystemCode, DatasetName, SourceSchema, SourceObject, LoadType, WatermarkColumn, WatermarkDataType,
            PrimaryKeyColumns, TargetContainer, TargetFolderPattern, TargetFileFormat, PartitionColumn,
            ParallelCopies, DataIntegrationUnits, ScheduleGroup, Priority)
    JOIN ctl.SourceSystem s ON s.SourceSystemCode = v.SourceSystemCode
) AS src
ON tgt.SourceSystemId = src.SourceSystemId AND tgt.DatasetName = src.DatasetName
WHEN NOT MATCHED THEN
    INSERT (SourceSystemId, DatasetName, SourceSchema, SourceObject, LoadType, WatermarkColumn, WatermarkDataType,
            PrimaryKeyColumns, TargetContainer, TargetFolderPattern, TargetFileFormat, PartitionColumn,
            ParallelCopies, DataIntegrationUnits, ScheduleGroup, Priority)
    VALUES (src.SourceSystemId, src.DatasetName, src.SourceSchema, src.SourceObject, src.LoadType, src.WatermarkColumn,
            src.WatermarkDataType, src.PrimaryKeyColumns, src.TargetContainer, src.TargetFolderPattern,
            src.TargetFileFormat, src.PartitionColumn, src.ParallelCopies, src.DataIntegrationUnits,
            src.ScheduleGroup, src.Priority);
GO

INSERT INTO ctl.Watermark (ConfigId)
SELECT c.ConfigId
FROM ctl.IngestionConfig c
WHERE c.LoadType = 'Incremental'
  AND NOT EXISTS (SELECT 1 FROM ctl.Watermark w WHERE w.ConfigId = c.ConfigId);
GO

-- Smoke test
EXEC ctl.usp_GetIngestionWorkload @ScheduleGroup = 'nightly';
SELECT * FROM ctl.vw_IngestionHealth;
GO
