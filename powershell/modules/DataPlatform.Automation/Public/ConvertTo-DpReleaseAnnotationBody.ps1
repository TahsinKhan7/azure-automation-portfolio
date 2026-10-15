function ConvertTo-DpReleaseAnnotationBody {
    <#
    .SYNOPSIS
        Builds the request body for an Application Insights release annotation.
    .DESCRIPTION
        Shape required by PUT {appInsightsResourceId}/Annotations?api-version=2015-05-01:
        Id, AnnotationName, EventTime (UTC ISO 8601), Category and a Properties
        string containing JSON.
    .EXAMPLE
        ConvertTo-DpReleaseAnnotationBody -ReleaseName data-api -Version 1.4.0 -Environment prod -Repository azure-automation-portfolio -Commit abc1234 -RequestedBy pipeline
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
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

        [datetime]$EventTime = (Get-Date),

        [string]$Category = 'Deployment'
    )

    $properties = [ordered]@{
        ReleaseName = $ReleaseName
        Version     = $Version
        Environment = $Environment
        Repository  = $Repository
        Commit      = $Commit
        RequestedBy = $RequestedBy
    }

    return @{
        Id             = [guid]::NewGuid().ToString()
        AnnotationName = "$ReleaseName $Version ($Environment)"
        EventTime      = $EventTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        Category       = $Category
        Properties     = ($properties | ConvertTo-Json -Compress)
    }
}
