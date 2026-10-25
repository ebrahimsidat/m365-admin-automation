<#
.SYNOPSIS
    Example unattended job: weekly licence utilisation and reclamation report.
.DESCRIPTION
    Intended for a scheduled task or Azure Automation runbook that signs in with an app registration
    and certificate (application permissions: Organization.Read.All, User.Read.All, AuditLog.Read.All).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ClientId,
    [Parameter(Mandatory)][string]$TenantId,
    [Parameter(Mandatory)][string]$CertificateThumbprint,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'reports')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../src/M365Admin/M365Admin.psd1')

Connect-M365Admin -ClientId $ClientId -TenantId $TenantId -CertificateThumbprint $CertificateThumbprint | Out-Null
try {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    $stamp = Get-Date -Format 'yyyy-MM-dd'

    $summary = Get-M365LicenseReport -Path (Join-Path $OutputDirectory "licence-summary-$stamp.csv")
    $reclaim = Get-M365LicenseReport -IncludeInactiveUsers -InactiveDays 90 -Path (Join-Path $OutputDirectory "licence-reclaim-$stamp.csv")

    $summary | Format-Table -AutoSize
    Write-Output "$(@($reclaim).Count) licensed account(s) are disabled or inactive for 90+ days."
}
finally {
    Disconnect-MgGraph | Out-Null
}
