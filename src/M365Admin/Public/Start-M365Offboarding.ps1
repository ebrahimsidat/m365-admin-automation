function Start-M365Offboarding {
    <#
    .SYNOPSIS
        Secures and offboards a departing user's Microsoft 365 account.
    .DESCRIPTION
        Runs the offboarding steps in a safe order:
          1. block sign-in (immediately stops new sign-ins),
          2. revoke refresh tokens and sessions (signs the user out everywhere),
          3. optionally convert the mailbox to a shared mailbox (needs Exchange Online),
          4. remove assigned group memberships (dynamic groups are skipped),
          5. remove licences (done last so mailbox data is retained while it is converted).
        The account is not deleted, so it can be restored or retained for legal hold. Each step is
        audited, and a failed step is reported without hiding the results of the others.
        ConfirmImpact is High: PowerShell asks for confirmation unless -Confirm:$false is used.
    .PARAMETER UserPrincipalName
        One or more users to offboard. Accepts pipeline input.
    .PARAMETER ConvertToSharedMailbox
        Convert the mailbox to a shared mailbox before licences are removed.
    .PARAMETER KeepLicenses
        Leave licences assigned (for example while data is exported).
    .EXAMPLE
        Start-M365Offboarding -UserPrincipalName jane.doe@contoso.com -ConvertToSharedMailbox -WhatIf
    .EXAMPLE
        Get-Content .\leavers.txt | Start-M365Offboarding -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$')]
        [string[]]$UserPrincipalName,

        [switch]$ConvertToSharedMailbox,

        [switch]$KeepLicenses,

        [string]$AuditLogPath = (Join-Path -Path (Get-Location) -ChildPath ("logs/offboarding-{0:yyyyMMdd}.csv" -f (Get-Date)))
    )

    process {
        foreach ($upn in $UserPrincipalName) {
            $steps = [ordered]@{}
            $result = [pscustomobject]@{
                UserPrincipalName = $upn
                Status            = 'Failed'
                Steps             = $steps
                GroupsRemoved     = @()
                LicensesRemoved   = @()
                Message           = ''
            }

            try {
                $user = Get-M365GraphUser -UserPrincipalName $upn
                if (-not $user) {
                    throw "User $upn not found."
                }

                if (-not $PSCmdlet.ShouldProcess($upn, 'Offboard user (block sign-in, revoke sessions, remove groups and licences)')) {
                    $result.Status = 'WhatIf'
                    $result.Message = 'No changes made (-WhatIf or declined).'
                    Write-M365AuditLog -Path $AuditLogPath -Action 'Offboard' -Target $upn -Result 'WhatIf'
                    $result
                    continue
                }

                $run = {
                    param([string]$Step, [scriptblock]$Action)
                    try {
                        & $Action
                        $steps[$Step] = 'Success'
                        Write-M365AuditLog -Path $AuditLogPath -Action $Step -Target $upn -Result 'Success'
                    }
                    catch {
                        $steps[$Step] = "Failed: $($_.Exception.Message)"
                        Write-M365AuditLog -Path $AuditLogPath -Action $Step -Target $upn -Result 'Failed' -Detail $_.Exception.Message
                    }
                }

                & $run 'BlockSignIn' { Disable-M365GraphUser -UserId $user.Id -Confirm:$false }
                & $run 'RevokeSessions' { Revoke-M365GraphUserSession -UserId $user.Id -Confirm:$false }

                if ($ConvertToSharedMailbox) {
                    & $run 'ConvertToSharedMailbox' { Set-M365ExoMailboxType -Identity $upn -Type Shared -Confirm:$false }
                }

                & $run 'RemoveGroups' {
                    foreach ($group in @(Get-M365GraphUserGroup -UserId $user.Id)) {
                        if ($group.Dynamic) {
                            Write-Verbose "Skipping dynamic group $($group.DisplayName)"
                            continue
                        }
                        Remove-M365GraphGroupMember -GroupId $group.Id -UserId $user.Id -Confirm:$false
                        $result.GroupsRemoved += $group.DisplayName
                    }
                }

                if ($KeepLicenses) {
                    $steps['RemoveLicenses'] = 'Skipped'
                    Write-M365AuditLog -Path $AuditLogPath -Action 'RemoveLicenses' -Target $upn -Result 'Skipped' -Detail '-KeepLicenses'
                }
                else {
                    & $run 'RemoveLicenses' {
                        $skuIds = @($user.AssignedLicenses | ForEach-Object { $_.SkuId })
                        if ($skuIds.Count) {
                            Set-M365GraphUserLicense -UserId $user.Id -RemoveSkuId $skuIds -Confirm:$false
                            $result.LicensesRemoved = $skuIds
                        }
                    }
                }

                $failed = @($steps.Keys | Where-Object { "$($steps[$_])" -like 'Failed*' })
                if ($failed.Count -eq 0) {
                    $result.Status = 'Completed'
                }
                elseif ($steps['BlockSignIn'] -eq 'Success') {
                    $result.Status = 'CompletedWithWarnings'
                    $result.Message = "Failed steps: $($failed -join ', ')"
                }
                else {
                    $result.Status = 'Failed'
                    $result.Message = "Sign-in could not be blocked. Failed steps: $($failed -join ', ')"
                }
            }
            catch {
                $result.Message = $_.Exception.Message
                Write-M365AuditLog -Path $AuditLogPath -Action 'Offboard' -Target $upn -Result 'Failed' -Detail $_.Exception.Message
                Write-Warning "Offboarding failed for ${upn}: $($_.Exception.Message)"
            }
            $result
        }
    }
}
