-- ============================================================
-- Staging Schema
-- Landing zone for Azure Data Factory pipelines with
-- upsert/merge procedures for incremental data loading
-- ============================================================

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'staging')
    EXEC('CREATE SCHEMA staging');
GO

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'dbo')
    EXEC('CREATE SCHEMA dbo');
GO

-- Staging table: Claims (ADF lands raw data here)
CREATE TABLE staging.Claims (
    ClaimId         NVARCHAR(50)     NOT NULL,
    PolicyNumber    NVARCHAR(50)     NOT NULL,
    ClaimDate       DATE             NOT NULL,
    ClaimType       NVARCHAR(50)     NULL,
    ClaimAmount     DECIMAL(18,2)    NULL,
    BusinessUnit    NVARCHAR(100)    NULL,
    Status          NVARCHAR(30)     NULL,
    ClaimantName    NVARCHAR(200)    NULL,
    SourceSystem    NVARCHAR(50)     NULL,
    LoadedAt        DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- Production table: Claims (final destination)
CREATE TABLE dbo.Claims (
    ClaimId         NVARCHAR(50)     NOT NULL PRIMARY KEY,
    PolicyNumber    NVARCHAR(50)     NOT NULL,
    ClaimDate       DATE             NOT NULL,
    ClaimType       NVARCHAR(50)     NULL,
    ClaimAmount     DECIMAL(18,2)    NULL,
    BusinessUnit    NVARCHAR(100)    NULL,
    Status          NVARCHAR(30)     NULL,
    ClaimantName    NVARCHAR(200)    NULL,
    SourceSystem    NVARCHAR(50)     NULL,
    CreatedAt       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- Merge procedure: Upsert from staging to production
CREATE OR ALTER PROCEDURE dbo.usp_MergeClaims
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @inserted INT, @updated INT;

    MERGE dbo.Claims AS target
    USING (
        -- Deduplicate staging: keep latest row per ClaimId
        SELECT *
        FROM (
            SELECT *,
                ROW_NUMBER() OVER (PARTITION BY ClaimId ORDER BY LoadedAt DESC) AS rn
            FROM staging.Claims
        ) ranked
        WHERE rn = 1
    ) AS source
    ON target.ClaimId = source.ClaimId

    WHEN MATCHED AND (
        target.Status       <> source.Status OR
        target.ClaimAmount  <> source.ClaimAmount OR
        target.ClaimType    <> source.ClaimType
    )
    THEN UPDATE SET
        target.PolicyNumber = source.PolicyNumber,
        target.ClaimDate    = source.ClaimDate,
        target.ClaimType    = source.ClaimType,
        target.ClaimAmount  = source.ClaimAmount,
        target.BusinessUnit = source.BusinessUnit,
        target.Status       = source.Status,
        target.ClaimantName = source.ClaimantName,
        target.SourceSystem = source.SourceSystem,
        target.UpdatedAt    = SYSUTCDATETIME()

    WHEN NOT MATCHED BY TARGET
    THEN INSERT (ClaimId, PolicyNumber, ClaimDate, ClaimType, ClaimAmount,
                 BusinessUnit, Status, ClaimantName, SourceSystem)
    VALUES (source.ClaimId, source.PolicyNumber, source.ClaimDate, source.ClaimType,
            source.ClaimAmount, source.BusinessUnit, source.Status,
            source.ClaimantName, source.SourceSystem);

    SET @inserted = @@ROWCOUNT;

    -- Clear staging after successful merge
    TRUNCATE TABLE staging.Claims;

    PRINT 'Merge complete: ' + CAST(@inserted AS NVARCHAR) + ' rows processed.';
END;
GO

-- Watermark update for incremental loads
CREATE OR ALTER PROCEDURE dbo.usp_UpdateWatermark
    @TableName      NVARCHAR(200),
    @NewValue       NVARCHAR(100)
AS
BEGIN
    MERGE meta.Watermark AS target
    USING (SELECT @TableName AS TableName) AS source
    ON target.TableName = source.TableName
    WHEN MATCHED THEN
        UPDATE SET WatermarkValue = @NewValue, LastUpdated = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (TableName, WatermarkColumn, WatermarkValue)
        VALUES (@TableName, 'UpdatedAt', @NewValue);
END;
GO

PRINT 'Staging schema and merge procedures created.';
