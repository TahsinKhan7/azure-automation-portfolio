// ============================================================
// Data platform - environment composition
//
// Deploys the templates in this folder as one resource-group
// deployment for a single environment. Environment-specific
// sizing lives in the envConfig map below; identity and network
// allow-lists come from parameters/main.<env>.bicepparam.
//
//   az deployment group create \
//     --resource-group rg-dp-data-dev-uks-01 \
//     --parameters parameters/main.dev.bicepparam
// ============================================================

targetScope = 'resourceGroup'

@description('Deployment environment. Drives naming and the sizing profile.')
@allowed(['dev', 'ite', 'iqe', 'preprod', 'prod'])
param environment string

@description('Azure region for every resource.')
param location string = resourceGroup().location

@description('Platform prefix embedded in resource names.')
@minLength(2)
@maxLength(4)
param prefix string = 'dp'

@description('Workload identifier embedded in resource names.')
@minLength(2)
@maxLength(10)
param workload string = 'data'

@description('Two-digit instance number.')
@minLength(2)
@maxLength(2)
param instance string = '01'

@description('Object ID of the principal that administers the Key Vault.')
param adminObjectId string

@description('Object IDs granted read access to Key Vault secrets (workload identities).')
param secretReaderObjectIds array = []

@description('Public IP addresses or CIDR ranges allowed through the Key Vault and storage firewalls.')
param allowedIpRanges array = []

@description('Action group resource ID for alert notifications. Empty skips alert rules.')
param actionGroupId string = ''

@description('Deploy the Azure SQL metadata database.')
param deploySql bool = false

@description('SQL administrator login. Only used when deploySql is true.')
param sqlAdminLogin string = 'dpsqladmin'

@secure()
@description('SQL administrator password. Only used when deploySql is true; supply from Key Vault via getSecret() in the parameter file.')
param sqlAdminPassword string = ''

@description('Additional tags merged with the standard set.')
param tags object = {}

// ---- Naming (mirrors terraform/modules/naming) ---------------------------------

var shortCodes = {
  uksouth: 'uks'
  ukwest: 'ukw'
  northeurope: 'neu'
  westeurope: 'weu'
}
var locationShort = shortCodes[?location] ?? take(location, 3)
var base = '${prefix}-${workload}-${environment}'
var baseLocation = '${base}-${locationShort}-${instance}'

var names = {
  logAnalytics: 'log-${baseLocation}'
  vnet: 'vnet-${baseLocation}'
  keyVault: 'kv-${base}-${instance}'
  storage: 'st${prefix}${workload}${environment}${instance}'
  databricks: 'dbw-${baseLocation}'
  dataFactory: 'adf-${baseLocation}'
  sqlServer: 'sql-${baseLocation}'
  sqlDatabase: 'sqldb-${base}-metadata'
  alertPrefix: 'alert-${base}'
}

// ---- Environment sizing profiles --------------------------------------------------

var envConfig = {
  dev: {
    retentionDays: 30
    dailyCapGb: 2
    storageSku: 'Standard_LRS'
    softDeleteDays: 7
    bronzeCoolTierDays: 30
    sqlSku: 'Basic'
    addressPrefix: '10.10.0.0/16'
    dbxPublicCidr: '10.10.1.0/24'
    dbxPrivateCidr: '10.10.2.0/24'
    privateEndpointCidr: '10.10.3.0/24'
  }
  ite: {
    retentionDays: 30
    dailyCapGb: 2
    storageSku: 'Standard_LRS'
    softDeleteDays: 7
    bronzeCoolTierDays: 30
    sqlSku: 'Basic'
    addressPrefix: '10.11.0.0/16'
    dbxPublicCidr: '10.11.1.0/24'
    dbxPrivateCidr: '10.11.2.0/24'
    privateEndpointCidr: '10.11.3.0/24'
  }
  iqe: {
    retentionDays: 30
    dailyCapGb: 5
    storageSku: 'Standard_ZRS'
    softDeleteDays: 14
    bronzeCoolTierDays: 60
    sqlSku: 'S0'
    addressPrefix: '10.12.0.0/16'
    dbxPublicCidr: '10.12.1.0/24'
    dbxPrivateCidr: '10.12.2.0/24'
    privateEndpointCidr: '10.12.3.0/24'
  }
  preprod: {
    retentionDays: 90
    dailyCapGb: 0
    storageSku: 'Standard_ZRS'
    softDeleteDays: 30
    bronzeCoolTierDays: 90
    sqlSku: 'S1'
    addressPrefix: '10.13.0.0/16'
    dbxPublicCidr: '10.13.1.0/24'
    dbxPrivateCidr: '10.13.2.0/24'
    privateEndpointCidr: '10.13.3.0/24'
  }
  prod: {
    retentionDays: 365
    dailyCapGb: 0
    storageSku: 'Standard_GRS'
    softDeleteDays: 30
    bronzeCoolTierDays: 90
    sqlSku: 'S2'
    addressPrefix: '10.14.0.0/16'
    dbxPublicCidr: '10.14.1.0/24'
    dbxPrivateCidr: '10.14.2.0/24'
    privateEndpointCidr: '10.14.3.0/24'
  }
}
var cfg = envConfig[environment]

var commonTags = union(tags, {
  Environment: environment
  Platform: 'dataplatform'
  Workload: workload
})

// ---- Modules ----------------------------------------------------------------------------

module logAnalytics 'log-analytics.bicep' = {
  name: 'law-${environment}'
  params: {
    workspaceName: names.logAnalytics
    location: location
    retentionDays: cfg.retentionDays
    dailyCapGb: cfg.dailyCapGb
    tags: commonTags
  }
}

module networking 'networking.bicep' = {
  name: 'net-${environment}'
  params: {
    vnetName: names.vnet
    location: location
    addressPrefix: cfg.addressPrefix
    dbxPublicCidr: cfg.dbxPublicCidr
    dbxPrivateCidr: cfg.dbxPrivateCidr
    privateEndpointCidr: cfg.privateEndpointCidr
    tags: commonTags
  }
}

module keyVault 'key-vault.bicep' = {
  name: 'kv-${environment}'
  params: {
    keyVaultName: names.keyVault
    location: location
    adminObjectId: adminObjectId
    secretReaderObjectIds: secretReaderObjectIds
    allowedIpRanges: allowedIpRanges
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: commonTags
  }
}

module storage 'storage-account.bicep' = {
  name: 'st-${environment}'
  params: {
    storageAccountName: names.storage
    location: location
    skuName: cfg.storageSku
    allowedIpRanges: allowedIpRanges
    allowedSubnetIds: []
    softDeleteDays: cfg.softDeleteDays
    bronzeCoolTierDays: cfg.bronzeCoolTierDays
    tags: commonTags
  }
}

module databricks 'databricks-workspace.bicep' = {
  name: 'dbw-${environment}'
  params: {
    workspaceName: names.databricks
    location: location
    sku: 'premium'
    vnetId: networking.outputs.vnetId
    publicSubnetName: networking.outputs.publicSubnetName
    privateSubnetName: networking.outputs.privateSubnetName
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: commonTags
  }
}

module sql 'sql-database.bicep' = if (deploySql) {
  name: 'sql-${environment}'
  params: {
    serverName: names.sqlServer
    databaseName: names.sqlDatabase
    location: location
    adminLogin: sqlAdminLogin
    adminPassword: sqlAdminPassword
    skuName: cfg.sqlSku
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    allowAzureServices: true
    tags: commonTags
  }
}

module dataFactory 'data-factory.bicep' = {
  name: 'adf-${environment}'
  params: {
    factoryName: names.dataFactory
    location: location
    dataLakeAccountName: storage.outputs.storageAccountName
    databricksWorkspaceUrl: 'https://${databricks.outputs.workspaceUrl}'
    keyVaultName: keyVault.outputs.keyVaultName
    sqlServerFqdn: deploySql ? sql.outputs.serverFqdn : ''
    tags: commonTags
  }
}

module alerts 'monitoring-alerts.bicep' = if (!empty(actionGroupId)) {
  name: 'alerts-${environment}'
  params: {
    alertPrefix: names.alertPrefix
    location: location
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    actionGroupId: actionGroupId
    dataFactoryId: dataFactory.outputs.factoryId
    databricksWorkspaceId: databricks.outputs.workspaceId
    tags: commonTags
  }
}

// ---- Outputs ------------------------------------------------------------------------------

output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output storageAccountName string = storage.outputs.storageAccountName
output databricksWorkspaceUrl string = databricks.outputs.workspaceUrl
output dataFactoryName string = dataFactory.outputs.factoryName
output dataFactoryPrincipalId string = dataFactory.outputs.principalId
