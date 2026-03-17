// ============================================================
// Databricks Workspace with VNet Injection
// Deploys a premium Databricks workspace injected into a
// customer-managed VNet with diagnostic logging enabled
// ============================================================

@description('Name of the Databricks workspace')
param workspaceName string

@description('Azure region')
param location string = resourceGroup().location

@allowed(['standard', 'premium'])
param sku string = 'premium'

@description('VNet resource ID for workspace injection')
param vnetId string

@description('Public subnet name for Databricks host')
param publicSubnetName string

@description('Private subnet name for Databricks container')
param privateSubnetName string

@description('Log Analytics workspace ID for diagnostics')
param logAnalyticsWorkspaceId string = ''

param tags object = {}

var managedRgName = '${workspaceName}-managed-rg'

resource databricksWorkspace 'Microsoft.Databricks/workspaces@2023-02-01' = {
  name: workspaceName
  location: location
  sku: {
    name: sku
  }
  properties: {
    managedResourceGroupId: subscriptionResourceId('Microsoft.Resources/resourceGroups', managedRgName)
    parameters: {
      customVirtualNetworkId: {
        value: vnetId
      }
      customPublicSubnetName: {
        value: publicSubnetName
      }
      customPrivateSubnetName: {
        value: privateSubnetName
      }
      enableNoPublicIp: {
        value: true
      }
    }
  }
  tags: union(tags, {
    ManagedBy: 'Bicep'
  })
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${workspaceName}-diag'
  scope: databricksWorkspace
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'accounts'; enabled: true }
      { category: 'clusters'; enabled: true }
      { category: 'jobs'; enabled: true }
      { category: 'notebook'; enabled: true }
    ]
  }
}

output workspaceId string = databricksWorkspace.id
output workspaceUrl string = databricksWorkspace.properties.workspaceUrl
