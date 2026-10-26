function Connect-M365Admin {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph with the least-privileged scopes for the chosen task.
    .DESCRIPTION
        Interactive (delegated) sign-in requests only the permissions the task needs. For unattended
        automation, use an app registration with a certificate (-ClientId, -TenantId,
        -CertificateThumbprint); application permissions are then granted on the app registration.
    .PARAMETER Task
        Onboarding, Offboarding, Reporting or All.
    .EXAMPLE
        Connect-M365Admin -Task Reporting
    .EXAMPLE
        Connect-M365Admin -ClientId $appId -TenantId contoso.onmicrosoft.com -CertificateThumbprint $thumb
    #>
    [CmdletBinding(DefaultParameterSetName = 'Delegated')]
    param(
        [Parameter(ParameterSetName = 'Delegated')]
        [ValidateSet('Onboarding', 'Offboarding', 'Reporting', 'All')]
        [string]$Task = 'All',

        [Parameter(Mandatory, ParameterSetName = 'AppOnly')]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [Parameter(Mandatory, ParameterSetName = 'AppOnly')]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter(Mandatory, ParameterSetName = 'AppOnly')]
        [ValidatePattern('^[0-9A-Fa-f]{40}$')]
        [string]$CertificateThumbprint
    )

    if (-not (Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue)) {
        throw 'Microsoft Graph PowerShell SDK not found. Install it with: Install-Module Microsoft.Graph -Scope CurrentUser'
    }

    if ($PSCmdlet.ParameterSetName -eq 'AppOnly') {
        Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -CertificateThumbprint $CertificateThumbprint -NoWelcome -ErrorAction Stop
    }
    else {
        $scopes = Get-M365RequiredScope -Task $Task
        Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop
    }
    Get-MgContext
}

function Get-M365RequiredScope {
    # Internal helper (not exported): least-privileged delegated scopes per task.
    [CmdletBinding()]
    [OutputType([string[]])]
    param([ValidateSet('Onboarding', 'Offboarding', 'Reporting', 'All')][string]$Task = 'All')

    $map = @{
        Onboarding  = @('User.ReadWrite.All', 'Group.ReadWrite.All', 'Organization.Read.All')
        Offboarding = @('User.ReadWrite.All', 'Group.ReadWrite.All', 'User.RevokeSessions.All')
        Reporting   = @('User.Read.All', 'Organization.Read.All', 'AuditLog.Read.All')
    }
    if ($Task -eq 'All') {
        return @($map.Values | ForEach-Object { $_ } | Sort-Object -Unique)
    }
    @($map[$Task])
}
