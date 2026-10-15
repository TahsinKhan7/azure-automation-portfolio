-- ============================================================================
-- Unity Catalog objects for the dataplatform lakehouse
-- Run once per environment with a metastore admin or catalog owner identity.
-- Replace the environment suffix (dev | ite | iqe | preprod | prod) and the
-- storage account; nothing else changes between environments.
-- ============================================================================

-- External location + storage credential (the managed identity of the
-- Databricks access connector must have Storage Blob Data Contributor).
CREATE STORAGE CREDENTIAL IF NOT EXISTS sc_dataplatform_dev
  WITH (AZURE_MANAGED_IDENTITY
        ACCESS_CONNECTOR_ID = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dataplatform-dev/providers/Microsoft.Databricks/accessConnectors/dbac-dataplatform-dev')
  COMMENT 'Managed identity used by Unity Catalog to reach the dataplatform lake';

CREATE EXTERNAL LOCATION IF NOT EXISTS el_dataplatform_dev_lake
  URL 'abfss://lake@stdataplatformdev.dfs.core.windows.net/'
  WITH (STORAGE CREDENTIAL sc_dataplatform_dev)
  COMMENT 'Root of the dataplatform lakehouse containers';

-- ---------------------------------------------------------------------------
-- Catalog and layer schemas (managed tables default to the catalog location)
-- ---------------------------------------------------------------------------
CREATE CATALOG IF NOT EXISTS dataplatform_dev
  MANAGED LOCATION 'abfss://lake@stdataplatformdev.dfs.core.windows.net/managed/'
  COMMENT 'dataplatform lakehouse - dev';

USE CATALOG dataplatform_dev;

CREATE SCHEMA IF NOT EXISTS bronze      COMMENT 'Raw, append-only, schema-enforced landings';
CREATE SCHEMA IF NOT EXISTS silver      COMMENT 'Conformed, de-duplicated, typed business entities';
CREATE SCHEMA IF NOT EXISTS gold        COMMENT 'Consumption-ready aggregates and dimensions';
CREATE SCHEMA IF NOT EXISTS quarantine  COMMENT 'Malformed and DQ-rejected rows awaiting triage';
CREATE SCHEMA IF NOT EXISTS ops         COMMENT 'Pipeline audit, DQ results and maintenance logs';

-- Volume for ad-hoc file drops that should not bypass governance.
CREATE VOLUME IF NOT EXISTS bronze.landing_files
  COMMENT 'Governed landing area for manual file uploads';

-- ---------------------------------------------------------------------------
-- Grants: least privilege by role, applied at catalog/schema level so new
-- tables inherit them.
-- ---------------------------------------------------------------------------
GRANT USE CATALOG ON CATALOG dataplatform_dev TO `dataplatform-engineers`;
GRANT USE CATALOG ON CATALOG dataplatform_dev TO `dataplatform-analysts`;
GRANT USE CATALOG ON CATALOG dataplatform_dev TO `dataplatform-scientists`;
GRANT USE CATALOG ON CATALOG dataplatform_dev TO `sp-dataplatform-dev-jobs`;

-- Engineers and the job service principal: full control of the pipeline layers.
GRANT USE SCHEMA, SELECT, MODIFY, CREATE TABLE, CREATE VOLUME
  ON SCHEMA bronze     TO `dataplatform-engineers`, `sp-dataplatform-dev-jobs`;
GRANT USE SCHEMA, SELECT, MODIFY, CREATE TABLE
  ON SCHEMA silver     TO `dataplatform-engineers`, `sp-dataplatform-dev-jobs`;
GRANT USE SCHEMA, SELECT, MODIFY, CREATE TABLE
  ON SCHEMA gold       TO `dataplatform-engineers`, `sp-dataplatform-dev-jobs`;
GRANT USE SCHEMA, SELECT, MODIFY, CREATE TABLE
  ON SCHEMA quarantine TO `dataplatform-engineers`, `sp-dataplatform-dev-jobs`;
GRANT USE SCHEMA, SELECT, MODIFY, CREATE TABLE
  ON SCHEMA ops        TO `dataplatform-engineers`, `sp-dataplatform-dev-jobs`;

-- Analysts: read gold and silver only; never bronze or quarantine (may hold raw PII).
GRANT USE SCHEMA, SELECT ON SCHEMA gold   TO `dataplatform-analysts`;
GRANT USE SCHEMA, SELECT ON SCHEMA silver TO `dataplatform-analysts`;

-- Data scientists: read silver/gold and create their own tables in a sandbox schema.
CREATE SCHEMA IF NOT EXISTS sandbox COMMENT 'Self-service experimentation';
GRANT USE SCHEMA, SELECT ON SCHEMA silver  TO `dataplatform-scientists`;
GRANT USE SCHEMA, SELECT ON SCHEMA gold    TO `dataplatform-scientists`;
GRANT USE SCHEMA, SELECT, MODIFY, CREATE TABLE ON SCHEMA sandbox TO `dataplatform-scientists`;

-- External location usage for the job identity only.
GRANT READ FILES, WRITE FILES ON EXTERNAL LOCATION el_dataplatform_dev_lake TO `sp-dataplatform-dev-jobs`;

-- Column-level protection example: mask claimant names for anyone outside the engineers group.
CREATE OR REPLACE FUNCTION silver.mask_name(name STRING)
  RETURNS STRING
  RETURN CASE WHEN is_account_group_member('dataplatform-engineers') THEN name
              ELSE CONCAT(LEFT(name, 1), '***') END;

-- Applied after silver.claims exists (see delta_table_ddl.sql):
-- ALTER TABLE silver.claims ALTER COLUMN claimant_name SET MASK silver.mask_name;

-- Verify
SHOW GRANTS ON CATALOG dataplatform_dev;
SHOW SCHEMAS IN dataplatform_dev;
