// ============================================================
// Azure SQL Database
// SQL Server with database, firewall rules, auditing
// and diagnostic settings for the data platform
// ============================================================

@description('SQL Server name (globally unique)')
param serverName string

@description('Database name')
param databaseName string

param location string = resourceGroup().location

@description('SQL admin username')
param adminLogin string

@secure()
@description('SQL admin password')
param adminPassword string

@description('Database SKU')
@allowed(['Basic', 'S0', 'S1', 'S2', 'P1', 'P2'])
param skuName string = 'S1'

@description('Enable Azure AD admin')
param aadAdminObjectId string = ''
param aadAdminDisplayName string = ''

@description('Log Analytics workspace ID for auditing')
param logAnalyticsWorkspaceId string = ''

@description('Allow Azure services to access')
param allowAzureServices bool = true

param tags object = {}

// SQL Server
resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: serverName
  location: location
  tags: union(tags, { ManagedBy: 'Bicep' })
  properties: {
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// Azure AD admin (conditional)
resource aadAdmin 'Microsoft.Sql/servers/administrators@2023-05-01-preview' = if (!empty(aadAdminObjectId)) {
  parent: sqlServer
  name: 'ActiveDirectory'
  properties: {
    administratorType: 'ActiveDirectory'
    login: aadAdminDisplayName
    sid: aadAdminObjectId
    tenantId: tenant().tenantId
  }
}

// Database
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 268435456000  // 250 GB
    zoneRedundant: false
  }
}

// Allow Azure services firewall rule
resource allowAzure 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = if (allowAzureServices) {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Auditing to Log Analytics
resource auditSettings 'Microsoft.Sql/servers/auditingSettings@2023-05-01-preview' = {
  parent: sqlServer
  name: 'default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
    retentionDays: 90
    auditActionsAndGroups: [
      'SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP'
      'FAILED_DATABASE_AUTHENTICATION_GROUP'
      'BATCH_COMPLETED_GROUP'
    ]
  }
}

// Diagnostic settings
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${databaseName}-diag'
  scope: sqlDatabase
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'SQLInsights'; enabled: true }
      { category: 'QueryStoreRuntimeStatistics'; enabled: true }
      { category: 'Errors'; enabled: true }
      { category: 'Timeouts'; enabled: true }
    ]
    metrics: [
      { category: 'Basic'; enabled: true }
    ]
  }
}

output serverId string = sqlServer.id
output serverFqdn string = sqlServer.properties.fullyQualifiedDomainName
output databaseId string = sqlDatabase.id
