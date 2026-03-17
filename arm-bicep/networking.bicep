// ============================================================
// Networking - VNet with Databricks subnets, NSGs, Private Endpoints
// Provides secure network foundation for the data platform
// ============================================================

@description('VNet name')
param vnetName string

param location string = resourceGroup().location

@description('VNet address space')
param addressPrefix string = '10.0.0.0/16'

@description('Databricks public (host) subnet CIDR')
param dbxPublicCidr string = '10.0.1.0/24'

@description('Databricks private (container) subnet CIDR')
param dbxPrivateCidr string = '10.0.2.0/24'

@description('Private endpoint subnet CIDR')
param privateEndpointCidr string = '10.0.3.0/24'

param tags object = {}

// NSG for Databricks subnets
resource databricksNsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: '${vnetName}-dbx-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowDatabricksWorkerToWorker'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'AllowDatabricksControlPlane'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureDatabricks'
          destinationAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// VNet
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  tags: union(tags, { ManagedBy: 'Bicep' })
  properties: {
    addressSpace: {
      addressPrefixes: [addressPrefix]
    }
    subnets: [
      {
        name: '${vnetName}-dbx-public'
        properties: {
          addressPrefix: dbxPublicCidr
          networkSecurityGroup: { id: databricksNsg.id }
          delegations: [
            {
              name: 'databricks'
              properties: {
                serviceName: 'Microsoft.Databricks/workspaces'
              }
            }
          ]
        }
      }
      {
        name: '${vnetName}-dbx-private'
        properties: {
          addressPrefix: dbxPrivateCidr
          networkSecurityGroup: { id: databricksNsg.id }
          delegations: [
            {
              name: 'databricks'
              properties: {
                serviceName: 'Microsoft.Databricks/workspaces'
              }
            }
          ]
        }
      }
      {
        name: '${vnetName}-pe-subnet'
        properties: {
          addressPrefix: privateEndpointCidr
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output publicSubnetName string = vnet.properties.subnets[0].name
output privateSubnetName string = vnet.properties.subnets[1].name
output peSubnetId string = vnet.properties.subnets[2].id
output nsgId string = databricksNsg.id
