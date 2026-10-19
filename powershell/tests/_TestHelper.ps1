# Shared test set-up: imports the module under test and defines stand-ins for
# Az cmdlets so that Pester can mock them without the Az modules installed.
#
# The stubs are created in the global scope only when the real cmdlet is
# absent; they take the parameters the module calls them with and do nothing
# beyond a verbose trace. Every test that touches them replaces the behaviour
# with Mock, so a stub being reached unmocked shows up as a missing result.

$script:ModuleRoot = Join-Path -Path $PSScriptRoot -ChildPath '../modules/DataPlatform.Automation'
$script:ModuleManifest = Join-Path -Path $script:ModuleRoot -ChildPath 'DataPlatform.Automation.psd1'
$script:ModuleName = 'DataPlatform.Automation'

Import-Module -Name $script:ModuleManifest -Force

$script:AzStubs = @{
    'Get-AzKeyVaultSecret' = { param ($VaultName, $Name, [switch]$AsPlainText) Write-Verbose -Message "Stub Get-AzKeyVaultSecret: $($PSBoundParameters.Keys -join ', ')" }
    'Set-AzKeyVaultSecret' = { param ($VaultName, $Name, $SecretValue, $ContentType, $Expires) Write-Verbose -Message "Stub Set-AzKeyVaultSecret: $($PSBoundParameters.Keys -join ', ')" }
    'Get-AzStorageAccount' = { param ($ResourceGroupName, $Name) Write-Verbose -Message "Stub Get-AzStorageAccount: $($PSBoundParameters.Keys -join ', ')" }
    'Set-AzContext'        = { param ($SubscriptionId) Write-Verbose -Message "Stub Set-AzContext: $($PSBoundParameters.Keys -join ', ')" }
    'Get-AzAccessToken'    = { param ($ResourceUrl, [switch]$AsSecureString) Write-Verbose -Message "Stub Get-AzAccessToken: $($PSBoundParameters.Keys -join ', ')" }
}

foreach ($name in $script:AzStubs.Keys) {
    if (-not (Get-Command -Name $name -ErrorAction SilentlyContinue)) {
        Set-Item -Path "function:global:$name" -Value $script:AzStubs[$name]
    }
}
