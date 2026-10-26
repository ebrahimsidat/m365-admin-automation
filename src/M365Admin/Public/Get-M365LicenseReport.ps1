function Get-M365LicenseReport {
    <#
    .SYNOPSIS
        Reports licence utilisation and reclaimable licences.
    .DESCRIPTION
        Summary view (default): one row per subscribed SKU with purchased, assigned and available
        units and the utilisation percentage.
        Detail view (-IncludeInactiveUsers): licensed users whose account is disabled or who have
        not signed in for -InactiveDays days. These are candidates for licence reclamation.
        Last sign-in data requires AuditLog.Read.All and Entra ID P1 or P2.
    .PARAMETER InactiveDays
        Days without a sign-in after which a licensed user is reported (default 90).
    .PARAMETER Path
        Optional CSV path for the output.
    .EXAMPLE
        Get-M365LicenseReport | Format-Table
    .EXAMPLE
        Get-M365LicenseReport -IncludeInactiveUsers -InactiveDays 60 -Path .\reclaim.csv
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [switch]$IncludeInactiveUsers,

        [ValidateRange(1, 3650)]
        [int]$InactiveDays = 90,

        [string]$Path
    )

    $skus = @(Get-M365GraphSubscribedSku)
    $skuNames = @{}
    foreach ($sku in $skus) { $skuNames["$($sku.SkuId)"] = $sku.SkuPartNumber }

    if (-not $IncludeInactiveUsers) {
        $report = foreach ($sku in $skus) {
            $purchased = [int]$sku.PrepaidUnits.Enabled
            $assigned = [int]$sku.ConsumedUnits
            [pscustomobject]@{
                Sku            = $sku.SkuPartNumber
                Purchased      = $purchased
                Assigned       = $assigned
                Available      = $purchased - $assigned
                UtilizationPct = if ($purchased -gt 0) { [math]::Round(100 * $assigned / $purchased, 1) } else { 0 }
                Suspended      = [int]$sku.PrepaidUnits.Suspended
                Warning        = [int]$sku.PrepaidUnits.Warning
            }
        }
        $report = @($report | Sort-Object -Property @{ Expression = 'UtilizationPct'; Descending = $true }, @{ Expression = 'Sku'; Descending = $false })
    }
    else {
        $cutoff = [DateTime]::UtcNow.AddDays(-$InactiveDays)
        $report = foreach ($user in @(Get-M365GraphLicensedUser)) {
            $lastSignIn = $null
            if ($user.PSObject.Properties['SignInActivity'] -and $user.SignInActivity) {
                $lastSignIn = $user.SignInActivity.LastSignInDateTime
            }

            $reason = if (-not $user.AccountEnabled) {
                'AccountDisabled'
            }
            elseif (-not $lastSignIn) {
                'NeverSignedIn'
            }
            elseif ([DateTime]$lastSignIn -lt $cutoff) {
                'Inactive'
            }

            if ($reason) {
                [pscustomobject]@{
                    UserPrincipalName = $user.UserPrincipalName
                    DisplayName       = $user.DisplayName
                    AccountEnabled    = [bool]$user.AccountEnabled
                    LastSignInUtc     = $lastSignIn
                    DaysSinceSignIn   = if ($lastSignIn) { [int]([DateTime]::UtcNow - [DateTime]$lastSignIn).TotalDays } else { $null }
                    Reason            = $reason
                    Licenses          = (@($user.AssignedLicenses | ForEach-Object {
                                $id = "$($_.SkuId)"
                                if ($skuNames.ContainsKey($id)) { $skuNames[$id] } else { $id }
                            }) -join ';')
                }
            }
        }
        $report = @($report | Sort-Object -Property Reason, UserPrincipalName)
    }

    if ($Path) {
        $report | Export-Csv -Path $Path -NoTypeInformation -Encoding utf8
        Write-Verbose "Report written to $Path"
    }
    $report
}
