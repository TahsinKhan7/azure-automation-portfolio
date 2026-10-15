function New-DpReleaseAnnotation {
    <#
    .SYNOPSIS
        Posts a release annotation to an Application Insights component.
    .DESCRIPTION
        Uses the Azure Resource Manager token of the current Az context, so it
        works unchanged from a workload-identity pipeline and from a developer
        session. Supports -WhatIf.
    .EXAMPLE
        New-DpReleaseAnnotation -ApplicationInsightsResourceId $id -ReleaseName data-api -Version 1.4.0 -Environment prod
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [ValidatePattern('^/subscriptions/.+/providers/Microsoft\.Insights/components/.+$')]
        [string]$ApplicationInsightsResourceId,

        [Parameter(Mandatory)]
        [string]$ReleaseName,

        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [ValidateSet('dev', 'ite', 'iqe', 'preprod', 'prod')]
        [string]$Environment,

        [string]$Repository,

        [string]$Commit,

        [string]$RequestedBy,

        [datetime]$EventTime = (Get-Date)
    )

    $body = ConvertTo-DpReleaseAnnotationBody -ReleaseName $ReleaseName -Version $Version -Environment $Environment `
        -Repository $Repository -Commit $Commit -RequestedBy $RequestedBy -EventTime $EventTime

    if (-not $PSCmdlet.ShouldProcess($ApplicationInsightsResourceId, "Annotate '$($body.AnnotationName)'")) {
        return $null
    }

    $tokenResponse = Get-AzAccessToken -ResourceUrl 'https://management.azure.com/'
    $accessToken = if ($tokenResponse.Token -is [securestring]) { $tokenResponse.Token } else { ConvertTo-DpSecureString -Value $tokenResponse.Token }

    $uri = "https://management.azure.com$ApplicationInsightsResourceId/Annotations?api-version=2015-05-01"
    $response = Invoke-RestMethod -Uri $uri -Method PUT -Headers (Get-DpBearerHeader -AccessToken $accessToken) -Body ($body | ConvertTo-Json -Depth 5)

    return [pscustomobject]@{
        Id             = $body.Id
        AnnotationName = $body.AnnotationName
        EventTime      = $body.EventTime
        Response       = $response
    }
}
