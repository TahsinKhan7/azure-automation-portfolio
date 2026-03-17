// ============================================================
// Azure Monitor Alert Rules
// Configures alerts for pipeline failures, resource health,
// cost thresholds and performance degradation
// ============================================================

@description('Name prefix for alert rules')
param alertPrefix string = 'alert'

param location string = resourceGroup().location

@description('Log Analytics workspace ID for log-based alerts')
param logAnalyticsWorkspaceId string

@description('Action group ID for alert notifications')
param actionGroupId string

@description('Data Factory resource ID to monitor')
param dataFactoryId string = ''

@description('Databricks workspace resource ID to monitor')
param databricksWorkspaceId string = ''

param tags object = {}

// --- ADF Pipeline Failure Alert ---
resource adfFailureAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (!empty(dataFactoryId)) {
  name: '${alertPrefix}-adf-pipeline-failure'
  location: location
  properties: {
    displayName: 'ADF Pipeline Failure'
    description: 'Fires when any ADF pipeline fails'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [logAnalyticsWorkspaceId]
    criteria: {
      allOf: [
        {
          query: '''
            ADFPipelineRun
            | where Status == "Failed"
            | summarize FailureCount = count() by PipelineName
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: { numberOfEvaluationPeriods: 1; minFailingPeriodsToAlert: 1 }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupId]
    }
  }
  tags: tags
}

// --- High Error Rate Alert ---
resource errorRateAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${alertPrefix}-high-error-rate'
  location: location
  properties: {
    displayName: 'High Error Rate Detected'
    description: 'Fires when error rate exceeds 5% across monitored resources'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT10M'
    windowSize: 'PT30M'
    scopes: [logAnalyticsWorkspaceId]
    criteria: {
      allOf: [
        {
          query: '''
            AzureDiagnostics
            | where TimeGenerated > ago(30m)
            | summarize
                Total = count(),
                Errors = countif(ResultType != "Success")
            | extend ErrorRate = round(toreal(Errors) / Total * 100, 1)
            | where ErrorRate > 5
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: { numberOfEvaluationPeriods: 1; minFailingPeriodsToAlert: 1 }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupId]
    }
  }
  tags: tags
}

// --- Key Vault Access Denied Alert ---
resource kvAccessAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${alertPrefix}-keyvault-access-denied'
  location: location
  properties: {
    displayName: 'Key Vault Access Denied'
    description: 'Fires on repeated Key Vault authentication failures'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [logAnalyticsWorkspaceId]
    criteria: {
      allOf: [
        {
          query: '''
            AzureDiagnostics
            | where ResourceProvider == "MICROSOFT.KEYVAULT"
            | where ResultType == "Forbidden" or ResultType == "Unauthorized"
            | summarize DeniedCount = count() by CallerIPAddress, OperationName
            | where DeniedCount > 5
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: { numberOfEvaluationPeriods: 1; minFailingPeriodsToAlert: 1 }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupId]
    }
  }
  tags: tags
}

// --- Storage Throttling Alert ---
resource storageThrottleAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${alertPrefix}-storage-throttling'
  location: location
  properties: {
    displayName: 'Storage Account Throttling'
    description: 'Fires when storage requests are being throttled (HTTP 429/503)'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [logAnalyticsWorkspaceId]
    criteria: {
      allOf: [
        {
          query: '''
            StorageBlobLogs
            | where StatusCode == 429 or StatusCode == 503
            | summarize ThrottledCount = count() by AccountName
            | where ThrottledCount > 10
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: { numberOfEvaluationPeriods: 1; minFailingPeriodsToAlert: 1 }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupId]
    }
  }
  tags: tags
}
