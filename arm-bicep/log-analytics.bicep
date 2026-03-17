// ============================================================
// Log Analytics Workspace
// Central monitoring workspace with retention policies,
// data collection rules and solution configurations
// ============================================================

@description('Log Analytics workspace name')
param workspaceName string

param location string = resourceGroup().location

@description('Data retention in days')
@minValue(30)
@maxValue(730)
param retentionDays int = 90

@description('Daily data cap in GB (0 = unlimited)')
param dailyCapGb int = 0

@allowed(['PerGB2018', 'CapacityReservation'])
param sku string = 'PerGB2018'

param tags object = {}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
  location: location
  tags: union(tags, { ManagedBy: 'Bicep' })
  properties: {
    sku: {
      name: sku
    }
    retentionInDays: retentionDays
    workspaceCapping: dailyCapGb > 0 ? {
      dailyQuotaGb: dailyCapGb
    } : null
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Enable standard solutions
resource vmInsights 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'VMInsights(${workspaceName})'
  location: location
  properties: {
    workspaceResourceId: logAnalytics.id
  }
  plan: {
    name: 'VMInsights(${workspaceName})'
    product: 'OMSGallery/VMInsights'
    publisher: 'Microsoft'
    promotionCode: ''
  }
}

resource keyVaultAnalytics 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'KeyVaultAnalytics(${workspaceName})'
  location: location
  properties: {
    workspaceResourceId: logAnalytics.id
  }
  plan: {
    name: 'KeyVaultAnalytics(${workspaceName})'
    product: 'OMSGallery/KeyVaultAnalytics'
    publisher: 'Microsoft'
    promotionCode: ''
  }
}

// Data collection rule for Azure Activity logs
resource activityDcr 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: '${workspaceName}-activity-dcr'
  location: location
  tags: tags
  properties: {
    dataSources: {
      extensions: [
        {
          name: 'AzureActivityLogs'
          streams: ['Microsoft-AzureActivity']
          extensionName: 'AzureActivity'
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalytics.id
          name: 'centralWorkspace'
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-AzureActivity']
        destinations: ['centralWorkspace']
      }
    ]
  }
}

output workspaceId string = logAnalytics.id
output workspaceName string = logAnalytics.name
output customerId string = logAnalytics.properties.customerId
