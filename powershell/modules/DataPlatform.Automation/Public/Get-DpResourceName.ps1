function Get-DpResourceName {
    <#
    .SYNOPSIS
        Returns the standard name for a resource, matching the Terraform naming module.
    .DESCRIPTION
        Convention: <type>-<prefix>-<workload>-<environment>-<location>-<instance>
        Storage accounts use the compact alphanumeric form, Key Vaults omit the
        location to stay within 24 characters and Unity Catalog names use
        underscores. Azure length limits are enforced here so that a bad name
        fails before any Azure call is made.
    .EXAMPLE
        Get-DpResourceName -ResourceType StorageAccount -Environment prod
        # stdpdataprod01
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('ResourceGroup', 'VirtualNetwork', 'NetworkSecurityGroup', 'LogAnalytics', 'KeyVault',
            'StorageAccount', 'DataFactory', 'DatabricksWorkspace', 'DatabricksAccessConnector', 'UnityCatalog', 'Budget')]
        [string]$ResourceType,

        [Parameter(Mandatory)]
        [ValidateSet('dev', 'ite', 'iqe', 'preprod', 'prod')]
        [string]$Environment,

        [ValidatePattern('^[a-z]{2,4}$')]
        [string]$Prefix = 'dp',

        [ValidatePattern('^[a-z0-9]{2,10}$')]
        [string]$Workload = 'data',

        [ValidatePattern('^[a-z0-9]+$')]
        [string]$Location = 'uksouth',

        [ValidatePattern('^[0-9]{2}$')]
        [string]$Instance = '01'
    )

    $shortCodes = @{
        uksouth     = 'uks'
        ukwest      = 'ukw'
        northeurope = 'neu'
        westeurope  = 'weu'
    }

    $locationShort = if ($shortCodes.ContainsKey($Location)) { $shortCodes[$Location] } else { $Location.Substring(0, 3) }
    $base = "$Prefix-$Workload-$Environment"
    $baseLocation = "$base-$locationShort-$Instance"

    $name = switch ($ResourceType) {
        'ResourceGroup' { "rg-$baseLocation" }
        'VirtualNetwork' { "vnet-$baseLocation" }
        'NetworkSecurityGroup' { "nsg-$baseLocation" }
        'LogAnalytics' { "log-$baseLocation" }
        'DataFactory' { "adf-$baseLocation" }
        'DatabricksWorkspace' { "dbw-$baseLocation" }
        'DatabricksAccessConnector' { "dbac-$baseLocation" }
        'Budget' { "bud-$baseLocation" }
        'KeyVault' { "kv-$base-$Instance" }
        'StorageAccount' { "st$Prefix$Workload$Environment$Instance" }
        'UnityCatalog' { $base.Replace('-', '_') }
    }

    if ($ResourceType -in @('KeyVault', 'StorageAccount') -and $name.Length -gt 24) {
        throw "Generated $ResourceType name '$name' is $($name.Length) characters; the Azure limit is 24. Shorten Prefix or Workload."
    }

    return $name
}
