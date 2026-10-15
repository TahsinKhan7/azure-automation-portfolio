function Set-DpAdoVariableGroup {
    <#
    .SYNOPSIS
        Creates or updates an Azure DevOps variable group idempotently through the REST API.
    .DESCRIPTION
        Looks the group up by name, computes the change set with
        Compare-DpVariableGroup and issues a POST (create) or PUT (update) only
        when something differs. Supports -WhatIf.
    .EXAMPLE
        Set-DpAdoVariableGroup -Organisation contoso -Project dataplatform -Name vg-dataplatform-dev -Variable @{ Environment = 'dev' } -AccessToken $pat
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [string]$Organisation,

        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [hashtable]$Variable,

        [Parameter(Mandatory)]
        [securestring]$AccessToken,

        [string]$Description = 'Managed by Set-DpAdoVariableGroup. Edit in source control, not in the portal.',

        [switch]$RemoveUnmanaged,

        [switch]$ForceSecretUpdate,

        [string]$ApiVersion = '7.1'
    )

    $headers = Get-DpAdoBasicHeader -AccessToken $AccessToken
    $baseUri = "https://dev.azure.com/$Organisation"
    $lookupUri = "$baseUri/$Project/_apis/distributedtask/variablegroups?groupName=$([uri]::EscapeDataString($Name))&api-version=$ApiVersion"

    $lookup = Invoke-DpAdoApi -Uri $lookupUri -Method GET -Headers $headers
    $existingGroup = if ($lookup.count -gt 0) { $lookup.value[0] } else { $null }

    $existingVariables = $null
    if ($null -ne $existingGroup) {
        $existingVariables = @{}
        foreach ($property in $existingGroup.variables.PSObject.Properties) {
            $existingVariables[$property.Name] = @{ value = $property.Value.value; isSecret = [bool]$property.Value.isSecret }
        }
    }

    $plan = Compare-DpVariableGroup -Existing $existingVariables -Desired $Variable -RemoveUnmanaged:$RemoveUnmanaged -ForceSecretUpdate:$ForceSecretUpdate

    $body = @{
        name                           = $Name
        description                    = $Description
        type                           = 'Vsts'
        variables                      = $plan.Variables
        variableGroupProjectReferences = @(
            @{
                name             = $Name
                description      = $Description
                projectReference = @{ name = $Project }
            }
        )
    }

    $groupId = $existingGroup.id

    switch ($plan.Action) {
        'Create' {
            if ($PSCmdlet.ShouldProcess("$Organisation/$Project", "Create variable group '$Name' with $($plan.ToAdd.Count) variable(s)")) {
                $created = Invoke-DpAdoApi -Uri "$baseUri/_apis/distributedtask/variablegroups?api-version=$ApiVersion" -Method POST -Headers $headers -Body $body
                $groupId = $created.id
            }
        }
        'Update' {
            if ($PSCmdlet.ShouldProcess("$Organisation/$Project", "Update variable group '$Name' (add $($plan.ToAdd.Count), update $($plan.ToUpdate.Count), remove $($plan.ToRemove.Count))")) {
                Invoke-DpAdoApi -Uri "$baseUri/_apis/distributedtask/variablegroups/$($existingGroup.id)?api-version=$ApiVersion" -Method PUT -Headers $headers -Body $body | Out-Null
            }
        }
        default {
            Write-Verbose -Message "Variable group '$Name' already matches the desired state."
        }
    }

    return [pscustomobject]@{
        Name     = $Name
        Id       = $groupId
        Action   = $plan.Action
        ToAdd    = $plan.ToAdd
        ToUpdate = $plan.ToUpdate
        ToRemove = $plan.ToRemove
    }
}
