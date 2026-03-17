// ============================================================
// ADLS Gen2 Storage Account
// Data lake storage with medallion architecture containers,
// lifecycle management and network security
// ============================================================

@description('Storage account name (3-24 chars, lowercase, no hyphens)')
param storageAccountName string

param location string = resourceGroup().location

@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param skuName string = 'Standard_GRS'

@description('IP ranges allowed through the firewall')
param allowedIpRanges array = []

@description('VNet subnet IDs for service endpoints')
param allowedSubnetIds array = []

@description('Days to retain soft-deleted blobs')
param softDeleteDays int = 30

@description('Days before moving bronze data to cool tier')
param bronzeCoolTierDays int = 90

param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: { name: skuName }
  properties: {
    isHnsEnabled: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: [for ip in allowedIpRanges: { value: ip; action: 'Allow' }]
      virtualNetworkRules: [for subnetId in allowedSubnetIds: { id: subnetId; action: 'Allow' }]
    }
    encryption: {
      services: {
        blob: { enabled: true; keyType: 'Account' }
        file: { enabled: true; keyType: 'Account' }
      }
      keySource: 'Microsoft.Storage'
    }
  }
  tags: union(tags, { ManagedBy: 'Bicep' })
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: { enabled: true; days: softDeleteDays }
    containerDeleteRetentionPolicy: { enabled: true; days: softDeleteDays }
  }
}

// Medallion architecture containers
var containers = ['bronze', 'silver', 'gold', 'landing', 'archive']

resource medallionContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for name in containers: {
  parent: blobService
  name: name
  properties: { publicAccess: 'None' }
}]

// Lifecycle management - tier bronze data to cool after N days
resource lifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          name: 'bronze-to-cool'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['bronze/']
            }
            actions: {
              baseBlob: {
                tierToCool: { daysAfterModificationGreaterThan: bronzeCoolTierDays }
                tierToArchive: { daysAfterModificationGreaterThan: 365 }
              }
            }
          }
        }
        {
          name: 'delete-old-snapshots'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: { blobTypes: ['blockBlob'] }
            actions: {
              snapshot: {
                delete: { daysAfterCreationGreaterThan: 90 }
              }
            }
          }
        }
      ]
    }
  }
}

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output primaryDfsEndpoint string = storageAccount.properties.primaryEndpoints.dfs
output primaryBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob
