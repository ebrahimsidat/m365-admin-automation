<#
    Thin wrappers around Microsoft Graph PowerShell SDK (v2) cmdlets.
    Business logic calls only these functions, which keeps it independent of the SDK surface
    and lets the Pester suite mock every tenant interaction.
#>

function Get-M365GraphUser {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$UserPrincipalName)

    $escaped = $UserPrincipalName.Replace("'", "''")
    Get-MgUser -Filter "userPrincipalName eq '$escaped'" -Property 'id,userPrincipalName,displayName,accountEnabled,assignedLicenses' -ErrorAction Stop |
        Select-Object -First 1
}

function Test-M365GraphUser {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$UserPrincipalName)

    [bool](Get-M365GraphUser -UserPrincipalName $UserPrincipalName)
}

function New-M365GraphUser {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][hashtable]$Body)

    if ($PSCmdlet.ShouldProcess($Body.UserPrincipalName, 'Create Entra ID user')) {
        New-MgUser -BodyParameter $Body -ErrorAction Stop
    }
}

function Set-M365GraphUserLicense {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$UserId,
        [guid[]]$AddSkuId = @(),
        [guid[]]$RemoveSkuId = @()
    )

    $add = @($AddSkuId | ForEach-Object { @{ SkuId = $_ } })
    if ($PSCmdlet.ShouldProcess($UserId, 'Change licence assignment')) {
        Set-MgUserLicense -UserId $UserId -AddLicenses $add -RemoveLicenses @($RemoveSkuId) -ErrorAction Stop
    }
}

function Get-M365GraphSubscribedSku {
    [CmdletBinding()]
    param()

    Get-MgSubscribedSku -All -ErrorAction Stop
}

function Get-M365GraphGroupByName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DisplayName)

    $escaped = $DisplayName.Replace("'", "''")
    Get-MgGroup -Filter "displayName eq '$escaped'" -Property 'id,displayName' -ErrorAction Stop | Select-Object -First 1
}

function Add-M365GraphGroupMember {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][string]$UserId
    )

    if ($PSCmdlet.ShouldProcess($GroupId, "Add member $UserId")) {
        New-MgGroupMember -GroupId $GroupId -DirectoryObjectId $UserId -ErrorAction Stop
    }
}

function Remove-M365GraphGroupMember {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][string]$UserId
    )

    if ($PSCmdlet.ShouldProcess($GroupId, "Remove member $UserId")) {
        Remove-MgGroupMemberByRef -GroupId $GroupId -DirectoryObjectId $UserId -ErrorAction Stop
    }
}

function Get-M365GraphUserGroup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$UserId)

    Get-MgUserMemberOf -UserId $UserId -All -ErrorAction Stop |
        Where-Object { $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.group' } |
        ForEach-Object {
            [pscustomobject]@{
                Id          = $_.Id
                DisplayName = $_.AdditionalProperties['displayName']
                Dynamic     = @($_.AdditionalProperties['groupTypes']) -contains 'DynamicMembership'
            }
        }
}

function Set-M365GraphUserManager {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$UserId,
        [Parameter(Mandatory)][string]$ManagerId
    )

    $body = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/users/$ManagerId" }
    if ($PSCmdlet.ShouldProcess($UserId, "Set manager $ManagerId")) {
        Set-MgUserManagerByRef -UserId $UserId -BodyParameter $body -ErrorAction Stop
    }
}

function Disable-M365GraphUser {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$UserId)

    if ($PSCmdlet.ShouldProcess($UserId, 'Block sign-in')) {
        Update-MgUser -UserId $UserId -AccountEnabled:$false -ErrorAction Stop
    }
}

function Revoke-M365GraphUserSession {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$UserId)

    if ($PSCmdlet.ShouldProcess($UserId, 'Revoke refresh tokens and sessions')) {
        Revoke-MgUserSignInSession -UserId $UserId -ErrorAction Stop | Out-Null
    }
}

function Get-M365GraphLicensedUser {
    [CmdletBinding()]
    param()

    # signInActivity requires AuditLog.Read.All and an Entra ID P1 or P2 licence.
    Get-MgUser -All -Filter 'assignedLicenses/$count ne 0' -ConsistencyLevel eventual -CountVariable licensedCount `
        -Property 'id,userPrincipalName,displayName,accountEnabled,assignedLicenses,signInActivity' -ErrorAction Stop
}

function Set-M365ExoMailboxType {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Identity,
        [ValidateSet('Shared')][string]$Type = 'Shared'
    )

    if (-not (Get-Command -Name Set-Mailbox -ErrorAction SilentlyContinue)) {
        throw 'Set-Mailbox is not available. Run Connect-ExchangeOnline (ExchangeOnlineManagement module) first.'
    }
    if ($PSCmdlet.ShouldProcess($Identity, "Convert mailbox to $Type")) {
        Set-Mailbox -Identity $Identity -Type $Type -ErrorAction Stop
    }
}
