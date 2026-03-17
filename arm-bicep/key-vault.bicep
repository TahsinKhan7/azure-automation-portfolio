// ============================================================
// Azure Key Vault
// Secure secret store with access policies, soft delete,
// purge protection and diagnostic logging
// ============================================================

@description('Key Vault name')
param keyVaultName string

param location string = resourceGroup().location

@description('Object IDs of users/groups/SPs needing secret access')
param secretReaderObjectIds array = []

@description('Object ID of the deploying principal (full access)')
param adminObjectId string

@description('Log Analytics workspace ID for audit logging')
param logAnalyticsWorkspaceId string = ''

param allowedIpRanges array = []
param tags object = {}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: { family: 'A'; name: 'standard' }
    tenantId: subscription().tenantId
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    enableRbacAuthorization: false
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: [for ip in allowedIpRanges: { value: ip }]
    }
    accessPolicies: concat(
      [
        {
          tenantId: subscription().tenantId
          objectId: adminObjectId
          permissions: {
            secrets: ['Get', 'List', 'Set', 'Delete', 'Recover', 'Backup', 'Restore']
            keys: ['Get', 'List', 'Create', 'Delete', 'Update', 'Recover']
            certificates: ['Get', 'List', 'Create', 'Delete', 'Update']
          }
        }
      ],
      [for objectId in secretReaderObjectIds: {
        tenantId: subscription().tenantId
        objectId: objectId
        permissions: {
          secrets: ['Get', 'List']
          keys: []
          certificates: []
        }
      }]
    )
  }
  tags: union(tags, { ManagedBy: 'Bicep' })
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${keyVaultName}-diag'
  scope: keyVault
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'AuditEvent'; enabled: true; retentionPolicy: { enabled: true; days: 365 } }
    ]
    metrics: [
      { category: 'AllMetrics'; enabled: true }
    ]
  }
}

output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
