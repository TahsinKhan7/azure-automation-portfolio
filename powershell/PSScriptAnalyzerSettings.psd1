@{
    # Invoke-ScriptAnalyzer -Path powershell -Recurse -Settings powershell/PSScriptAnalyzerSettings.psd1
    #
    # Default rules plus the formatting rules, so style drift is caught in CI
    # rather than in review. Nothing is excluded globally; the single
    # plain-text SecureString conversion is suppressed at its call site
    # (ConvertTo-DpSecureString) with a justification.

    Severity            = @('Error', 'Warning', 'Information')
    IncludeDefaultRules = $true
    ExcludeRules        = @()

    Rules               = @{
        PSUseCompatibleSyntax      = @{
            Enable         = $true
            TargetVersions = @('7.0')
        }
        PSPlaceOpenBrace           = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace          = @{
            Enable             = $true
            NewLineAfter       = $false
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }
        PSUseConsistentIndentation = @{
            Enable              = $true
            IndentationSize     = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind                = 'space'
        }
        PSUseConsistentWhitespace  = @{
            Enable                                  = $true
            CheckInnerBrace                         = $true
            CheckOpenBrace                          = $true
            CheckOpenParen                          = $true
            CheckOperator                           = $true
            CheckPipe                               = $true
            CheckPipeForRedundantWhitespace         = $false
            CheckSeparator                          = $true
            CheckParameter                          = $false
            IgnoreAssignmentOperatorInsideHashTable = $true
        }
        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $true
        }
        PSUseCorrectCasing         = @{
            Enable = $true
        }
        PSAvoidUsingCmdletAliases  = @{
            allowlist = @()
        }
    }
}
