function Get-DpMedallionFolderLayout {
    <#
    .SYNOPSIS
        Returns the standard folder hierarchy for a medallion-architecture container.
    .DESCRIPTION
        Parents are listed before children so the list can be created in order.
    .EXAMPLE
        Get-DpMedallionFolderLayout
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [string[]]$Layer = @('bronze', 'silver', 'gold'),

        # Defaults to the standard raw/landing, cleansed/standardised and
        # aggregated/reporting sub-folders when not supplied.
        [hashtable]$SubFolder,

        [string[]]$SystemFolder = @('_checkpoints', '_schemas', '_logs')
    )

    if (-not $PSBoundParameters.ContainsKey('SubFolder')) {
        $SubFolder = @{
            bronze = @('raw', 'landing')
            silver = @('cleansed', 'standardised')
            gold   = @('aggregated', 'reporting')
        }
    }

    $folders = [System.Collections.Generic.List[string]]::new()

    # Loop variables deliberately differ from the parameter names: PowerShell
    # variable names are case-insensitive, so "foreach ($layer in $Layer)" would
    # overwrite the [string[]] parameter on each iteration.
    foreach ($layerName in $Layer) {
        $folders.Add($layerName)
        foreach ($child in @($SubFolder[$layerName])) {
            if ($child) {
                $folders.Add("$layerName/$child")
            }
        }
    }

    foreach ($systemName in $SystemFolder) {
        $folders.Add($systemName)
    }

    return $folders.ToArray()
}
