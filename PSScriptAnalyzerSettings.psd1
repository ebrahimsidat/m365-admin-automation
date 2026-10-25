@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @()
    Rules        = @{
        PSUseCompatibleSyntax      = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.4')
        }
        PSPlaceOpenBrace           = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace          = @{
            Enable             = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }
        PSUseConsistentIndentation = @{
            Enable          = $true
            IndentationSize = 4
            Kind            = 'space'
        }
        PSUseConsistentWhitespace  = @{
            Enable          = $true
            CheckOpenBrace  = $true
            CheckOpenParen  = $true
            CheckOperator   = $false
            CheckSeparator  = $true
            CheckInnerBrace = $true
            CheckPipe       = $true
        }
    }
}
