function Write-DpLog {
    <#
    .SYNOPSIS
        Writes a timestamped message to the Information stream (or Warning/Verbose).
    .DESCRIPTION
        Scripts in this repository use Write-DpLog instead of Write-Host so that
        output can be captured by pipelines and suppressed by callers through
        the standard preference variables.
    .EXAMPLE
        Write-DpLog -Message 'Rotation complete' -Level Success
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('Info', 'Success', 'Warning', 'Debug')]
        [string]$Level = 'Info'
    )

    $timestamp = (Get-Date).ToString('HH:mm:ss')
    $line = "[$timestamp] [$($Level.ToUpperInvariant())] $Message"

    switch ($Level) {
        'Warning' { Write-Warning -Message $Message }
        'Debug' { Write-Verbose -Message $line }
        default { Write-Information -MessageData $line -InformationAction Continue }
    }
}
