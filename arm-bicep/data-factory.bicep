// ============================================================
// Azure Data Factory with Linked Services
// Deploys ADF with connections to ADLS, Databricks, Azure SQL
// and Key Vault for secret management
// ============================================================

@description('Data Factory name')
param factoryName string

param location string = resourceGroup().location

@description('ADLS Gen2 storage account name for data lake')
param dataLakeAccountName string

@description('Databricks workspace URL')
param databricksWorkspaceUrl string

@description('Key Vault name for storing connection secrets')
param keyVaultName string

@description('Azure SQL Server FQDN')
param sqlServerFqdn string = ''

param tags object = {}

resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: factoryName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Disabled'
  }
  tags: union(tags, { ManagedBy: 'Bicep' })
}

// Linked Service: Azure Key Vault
resource lsKeyVault 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory
  name: 'ls_keyvault'
  properties: {
    type: 'AzureKeyVault'
    typeProperties: {
      baseUrl: 'https://${keyVaultName}${environment().suffixes.keyvaultDns}'
    }
  }
}

// Linked Service: ADLS Gen2 Data Lake
resource lsDataLake 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory
  name: 'ls_datalake'
  properties: {
    type: 'AzureBlobFS'
    typeProperties: {
      url: 'https://${dataLakeAccountName}.dfs.${environment().suffixes.storage}'
    }
  }
}

// Linked Service: Databricks
resource lsDatabricks 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory
  name: 'ls_databricks'
  properties: {
    type: 'AzureDatabricks'
    typeProperties: {
      domain: databricksWorkspaceUrl
      accessToken: {
        type: 'AzureKeyVaultSecret'
        store: {
          referenceName: lsKeyVault.name
          type: 'LinkedServiceReference'
        }
        secretName: 'databricks-token'
      }
      newClusterNodeType: 'Standard_DS3_v2'
      newClusterNumOfWorker: '2'
      newClusterSparkEnvVars: {
        PYSPARK_PYTHON: '/databricks/python3/bin/python3'
      }
    }
  }
}

// Linked Service: Azure SQL (conditional)
resource lsSql 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = if (!empty(sqlServerFqdn)) {
  parent: dataFactory
  name: 'ls_azuresql'
  properties: {
    type: 'AzureSqlDatabase'
    typeProperties: {
      connectionString: {
        type: 'AzureKeyVaultSecret'
        store: {
          referenceName: lsKeyVault.name
          type: 'LinkedServiceReference'
        }
        secretName: 'sql-connection-string'
      }
    }
  }
}

output factoryId string = dataFactory.id
output factoryName string = dataFactory.name
output principalId string = dataFactory.identity.principalId
