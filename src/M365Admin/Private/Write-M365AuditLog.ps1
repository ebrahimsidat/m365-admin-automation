function Write-M365AuditLog {
    <#
    .SYNOPSIS
        Appends one structured record to a CSV audit log.
    .DESCRIPTION
        Every change made by the module is recorded with a UTC timestamp, the operator, the action,
        the target and the outcome, so administrators can evidence what was changed and by whom.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$Target,

        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Failed', 'Skipped', 'WhatIf')]
        [string]$Result,

        [string]$Detail = ''
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    $operator = if ($env:USERNAME) { $env:USERNAME } elseif ($env:USER) { $env:USER } else { 'unknown' }
    $record = [pscustomobject]@{
        TimestampUtc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        Operator     = $operator
        Action       = $Action
        Target       = $Target
        Result       = $Result
        Detail       = $Detail
    }

    $directory = Split-Path -Path $Path -Parent
    if ($directory -and -not (Test-Path -Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force -WhatIf:$false | Out-Null
    }
    # The audit trail is written even under -WhatIf, so dry runs are recorded too.
    $record | Export-Csv -Path $Path -Append -NoTypeInformation -Encoding utf8 -WhatIf:$false
}
