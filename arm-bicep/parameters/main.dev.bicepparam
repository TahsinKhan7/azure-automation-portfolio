using '../main.bicep'

// dev parameters. Object IDs and subscription IDs are placeholders.
param environment = 'dev'
param adminObjectId = '00000000-0000-0000-0000-000000000000'
param secretReaderObjectIds = [
  '00000000-0000-0000-0000-000000000001'
]
param allowedIpRanges = [
    '203.0.113.10'
  '198.51.100.0/24'
]
param actionGroupId = ''
param deploySql = false
param tags = {
  Owner: 'data-platform-team'
  CostCentre: 'CC-DATA-DEV'
}
