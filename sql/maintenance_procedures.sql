-- ============================================================
-- Maintenance Procedures
-- Index rebuilds, statistics updates, partition management
-- and data retention cleanup
-- ============================================================

-- Rebuild fragmented indexes (>30% fragmentation)
CREATE OR ALTER PROCEDURE dbo.usp_RebuildFragmentedIndexes
    @FragmentationThreshold FLOAT = 30.0,
    @DryRun BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @indexName NVARCHAR(256);
    DECLARE @tableName NVARCHAR(256);
    DECLARE @fragPct FLOAT;
    
    DECLARE idx_cursor CURSOR FOR
        SELECT
            OBJECT_NAME(ips.object_id)  AS TableName,
            i.name                       AS IndexName,
            ips.avg_fragmentation_in_percent AS FragPct
        FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
        JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
        WHERE ips.avg_fragmentation_in_percent > @FragmentationThreshold
          AND ips.page_count > 1000
          AND i.name IS NOT NULL
        ORDER BY ips.avg_fragmentation_in_percent DESC;
    
    OPEN idx_cursor;
    FETCH NEXT FROM idx_cursor INTO @tableName, @indexName, @fragPct;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = 'ALTER INDEX [' + @indexName + '] ON [' + @tableName + '] REBUILD WITH (ONLINE = ON)';
        
        IF @DryRun = 1
            PRINT 'Would rebuild: ' + @indexName + ' on ' + @tableName + ' (' + CAST(@fragPct AS NVARCHAR) + '% fragmented)';
        ELSE
        BEGIN
            PRINT 'Rebuilding: ' + @indexName + ' on ' + @tableName;
            EXEC sp_executesql @sql;
        END
        
        FETCH NEXT FROM idx_cursor INTO @tableName, @indexName, @fragPct;
    END;
    
    CLOSE idx_cursor;
    DEALLOCATE idx_cursor;
END;
GO

-- Update all statistics
CREATE OR ALTER PROCEDURE dbo.usp_UpdateAllStatistics
    @SamplePercent INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @tableName NVARCHAR(256);
    
    DECLARE tbl_cursor CURSOR FOR
        SELECT SCHEMA_NAME(schema_id) + '.' + name
        FROM sys.tables
        WHERE is_ms_shipped = 0;
    
    OPEN tbl_cursor;
    FETCH NEXT FROM tbl_cursor INTO @tableName;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = 'UPDATE STATISTICS ' + @tableName + ' WITH SAMPLE ' + CAST(@SamplePercent AS NVARCHAR) + ' PERCENT';
        PRINT 'Updating: ' + @tableName;
        EXEC sp_executesql @sql;
        FETCH NEXT FROM tbl_cursor INTO @tableName;
    END;
    
    CLOSE tbl_cursor;
    DEALLOCATE tbl_cursor;
    
    PRINT 'All statistics updated.';
END;
GO

-- Data retention cleanup for pipeline metadata
CREATE OR ALTER PROCEDURE meta.usp_CleanupOldRuns
    @RetentionDays INT = 90
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @cutoff DATETIME2 = DATEADD(DAY, -@RetentionDays, SYSUTCDATETIME());
    DECLARE @deletedLineage INT, @deletedQuality INT, @deletedRuns INT;
    
    -- Delete in dependency order
    DELETE FROM meta.DataLineage
    WHERE RunId IN (SELECT RunId FROM meta.PipelineRun WHERE StartTime < @cutoff);
    SET @deletedLineage = @@ROWCOUNT;
    
    DELETE FROM meta.QualityCheckResult
    WHERE RunId IN (SELECT RunId FROM meta.PipelineRun WHERE StartTime < @cutoff);
    SET @deletedQuality = @@ROWCOUNT;
    
    DELETE FROM meta.PipelineRun WHERE StartTime < @cutoff;
    SET @deletedRuns = @@ROWCOUNT;
    
    PRINT 'Cleanup complete (>' + CAST(@RetentionDays AS NVARCHAR) + ' days):';
    PRINT '  Pipeline runs:    ' + CAST(@deletedRuns AS NVARCHAR);
    PRINT '  Quality checks:   ' + CAST(@deletedQuality AS NVARCHAR);
    PRINT '  Lineage records:  ' + CAST(@deletedLineage AS NVARCHAR);
END;
GO

-- Staging table truncation (run after successful merge)
CREATE OR ALTER PROCEDURE staging.usp_TruncateAllStaging
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @table NVARCHAR(256);
    
    DECLARE stg_cursor CURSOR FOR
        SELECT SCHEMA_NAME(schema_id) + '.' + name
        FROM sys.tables
        WHERE SCHEMA_NAME(schema_id) = 'staging';
    
    OPEN stg_cursor;
    FETCH NEXT FROM stg_cursor INTO @table;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = 'TRUNCATE TABLE ' + @table;
        PRINT 'Truncating: ' + @table;
        EXEC sp_executesql @sql;
        FETCH NEXT FROM stg_cursor INTO @table;
    END;
    
    CLOSE stg_cursor;
    DEALLOCATE stg_cursor;
END;
GO

PRINT 'Maintenance procedures created.';
