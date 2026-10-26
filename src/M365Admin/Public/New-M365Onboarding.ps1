function New-M365Onboarding {
    <#
    .SYNOPSIS
        Creates Entra ID users for new hires, assigns licences and groups, and sets their manager.
    .DESCRIPTION
        Accepts records from a CSV file or the pipeline. For each new hire it:
          1. builds a unique UPN from the naming convention,
          2. creates the account with a random temporary password that must be changed at first sign-in,
          3. assigns the licence (by SKU part number, for example ENTERPRISEPACK),
          4. adds the user to the listed groups (separated by ';'),
          5. sets the manager.
        Each record is processed independently: one failure does not stop the batch. Every action is
        written to the audit log, and -WhatIf shows what would happen without changing the tenant.
        Temporary passwords are returned only when -PassThruPassword is used; deliver them through a
        secure channel.
    .PARAMETER CsvPath
        CSV with columns GivenName, Surname, Department, JobTitle, UsageLocation, LicenseSku, Groups, Manager.
    .PARAMETER InputObject
        Objects with the same properties as the CSV columns.
    .PARAMETER Domain
        Verified domain used for new UPNs.
    .PARAMETER AuditLogPath
        CSV audit log path. Defaults to ./logs/onboarding-<date>.csv.
    .EXAMPLE
        New-M365Onboarding -CsvPath .\examples\new-hires.csv -Domain contoso.com -WhatIf
    .EXAMPLE
        Import-Csv .\new-hires.csv | New-M365Onboarding -Domain contoso.com -PassThruPassword |
            Export-Csv .\onboarded.csv -NoTypeInformation
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Pipeline')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Csv')]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string]$CsvPath,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Pipeline')]
        [psobject[]]$InputObject,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}$')]
        [string]$Domain,

        [ValidateSet('FirstDotLast', 'FirstInitialLast', 'FirstLast')]
        [string]$NameFormat = 'FirstDotLast',

        [string]$AuditLogPath = (Join-Path -Path (Get-Location) -ChildPath ("logs/onboarding-{0:yyyyMMdd}.csv" -f (Get-Date))),

        [switch]$PassThruPassword
    )

    begin {
        $required = 'GivenName', 'Surname', 'UsageLocation'
        $skuCache = $null
        $issued = [System.Collections.Generic.List[string]]::new()
        $records = [System.Collections.Generic.List[psobject]]::new()
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Csv') {
            foreach ($row in (Import-Csv -Path $CsvPath)) { $records.Add($row) }
        }
        else {
            foreach ($row in $InputObject) { $records.Add($row) }
        }
    }

    end {
        foreach ($hire in $records) {
            $name = "$($hire.GivenName) $($hire.Surname)".Trim()
            $result = [pscustomobject]@{
                DisplayName       = $name
                UserPrincipalName = $null
                Status            = 'Failed'
                License           = $null
                GroupsAdded       = @()
                TemporaryPassword = $null
                Message           = ''
            }

            try {
                $missing = @($required | Where-Object { -not ($hire.PSObject.Properties[$_] -and "$($hire.$_)".Trim()) })
                if ($missing) {
                    throw "Missing required field(s): $($missing -join ', ')"
                }
                if ("$($hire.UsageLocation)" -notmatch '^[A-Za-z]{2}$') {
                    throw "UsageLocation must be a two-letter ISO country code, got '$($hire.UsageLocation)'"
                }

                $upn = New-M365UserPrincipalName -GivenName $hire.GivenName -Surname $hire.Surname -Domain $Domain `
                    -Format $NameFormat -ExistingName $issued.ToArray() `
                    -ExistsScript { param($candidate) Test-M365GraphUser -UserPrincipalName $candidate }
                $issued.Add($upn)
                $result.UserPrincipalName = $upn

                if (-not $PSCmdlet.ShouldProcess($upn, 'Onboard new hire')) {
                    $result.Status = 'WhatIf'
                    $result.Message = 'No changes made (-WhatIf).'
                    Write-M365AuditLog -Path $AuditLogPath -Action 'Onboard' -Target $upn -Result 'WhatIf'
                    $result
                    continue
                }

                $password = New-M365TemporaryPassword
                $body = @{
                    AccountEnabled    = $true
                    DisplayName       = $name
                    GivenName         = "$($hire.GivenName)".Trim()
                    Surname           = "$($hire.Surname)".Trim()
                    UserPrincipalName = $upn
                    MailNickname      = $upn.Split('@')[0]
                    UsageLocation     = "$($hire.UsageLocation)".ToUpperInvariant()
                    PasswordProfile   = @{
                        Password                      = $password
                        ForceChangePasswordNextSignIn = $true
                    }
                }
                foreach ($optional in 'Department', 'JobTitle') {
                    if ($hire.PSObject.Properties[$optional] -and "$($hire.$optional)".Trim()) {
                        $body[$optional] = "$($hire.$optional)".Trim()
                    }
                }

                $user = New-M365GraphUser -Body $body -Confirm:$false
                Write-M365AuditLog -Path $AuditLogPath -Action 'CreateUser' -Target $upn -Result 'Success'
                $notes = [System.Collections.Generic.List[string]]::new()

                if ($hire.PSObject.Properties['LicenseSku'] -and "$($hire.LicenseSku)".Trim()) {
                    $skuName = "$($hire.LicenseSku)".Trim()
                    if ($null -eq $skuCache) { $skuCache = @(Get-M365GraphSubscribedSku) }
                    $sku = $skuCache | Where-Object { $_.SkuPartNumber -eq $skuName } | Select-Object -First 1
                    if (-not $sku) {
                        $notes.Add("licence $skuName not found in tenant")
                        Write-M365AuditLog -Path $AuditLogPath -Action 'AssignLicense' -Target $upn -Result 'Failed' -Detail "SKU $skuName not found"
                    }
                    elseif (($sku.PrepaidUnits.Enabled - $sku.ConsumedUnits) -le 0) {
                        $notes.Add("no available $skuName licences")
                        Write-M365AuditLog -Path $AuditLogPath -Action 'AssignLicense' -Target $upn -Result 'Failed' -Detail "No available $skuName units"
                    }
                    else {
                        Set-M365GraphUserLicense -UserId $user.Id -AddSkuId $sku.SkuId -Confirm:$false
                        $sku.ConsumedUnits++
                        $result.License = $skuName
                        Write-M365AuditLog -Path $AuditLogPath -Action 'AssignLicense' -Target $upn -Result 'Success' -Detail $skuName
                    }
                }

                if ($hire.PSObject.Properties['Groups'] -and "$($hire.Groups)".Trim()) {
                    foreach ($groupName in ("$($hire.Groups)" -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
                        try {
                            $group = Get-M365GraphGroupByName -DisplayName $groupName
                            if (-not $group) { throw 'group not found' }
                            Add-M365GraphGroupMember -GroupId $group.Id -UserId $user.Id -Confirm:$false
                            $result.GroupsAdded += $groupName
                            Write-M365AuditLog -Path $AuditLogPath -Action 'AddGroup' -Target $upn -Result 'Success' -Detail $groupName
                        }
                        catch {
                            $notes.Add("group '$groupName': $($_.Exception.Message)")
                            Write-M365AuditLog -Path $AuditLogPath -Action 'AddGroup' -Target $upn -Result 'Failed' -Detail "$groupName - $($_.Exception.Message)"
                        }
                    }
                }

                if ($hire.PSObject.Properties['Manager'] -and "$($hire.Manager)".Trim()) {
                    $manager = Get-M365GraphUser -UserPrincipalName "$($hire.Manager)".Trim()
                    if ($manager) {
                        Set-M365GraphUserManager -UserId $user.Id -ManagerId $manager.Id -Confirm:$false
                        Write-M365AuditLog -Path $AuditLogPath -Action 'SetManager' -Target $upn -Result 'Success' -Detail $hire.Manager
                    }
                    else {
                        $notes.Add("manager $($hire.Manager) not found")
                        Write-M365AuditLog -Path $AuditLogPath -Action 'SetManager' -Target $upn -Result 'Failed' -Detail "$($hire.Manager) not found"
                    }
                }

                $result.Status = if ($notes.Count) { 'CompletedWithWarnings' } else { 'Completed' }
                $result.Message = $notes -join '; '
                if ($PassThruPassword) { $result.TemporaryPassword = $password }
            }
            catch {
                $result.Status = 'Failed'
                $result.Message = $_.Exception.Message
                $target = if ($result.UserPrincipalName) { $result.UserPrincipalName } else { $name }
                Write-M365AuditLog -Path $AuditLogPath -Action 'Onboard' -Target $target -Result 'Failed' -Detail $_.Exception.Message
                Write-Warning "Onboarding failed for '$name': $($_.Exception.Message)"
            }
            $result
        }
    }
}
