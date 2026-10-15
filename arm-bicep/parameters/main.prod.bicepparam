using '../main.bicep'

// prod parameters. Object IDs and subscription IDs are placeholders.
param environment = 'prod'
param adminObjectId = '00000000-0000-0000-0000-000000000000'
param secretReaderObjectIds = [
  '00000000-0000-0000-0000-000000000001'
]
param allowedIpRanges = [
    '203.0.113.10'
]
param actionGroupId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dp-monitoring-uks-01/providers/Microsoft.Insights/actionGroups/ag-dp-prod'
param deploySql = true

// Resolved at deployment time from the platform vault; never stored in Git.
param sqlAdminPassword = getSecret('00000000-0000-0000-0000-000000000000', 'rg-dp-platform-uks-01', 'kv-dp-platform-01', 'sql-admin-password-prod')
param tags = {
  Owner: 'data-platform-team'
  CostCentre: 'CC-DATA-PROD'
}
