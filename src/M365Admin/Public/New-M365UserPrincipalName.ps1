function New-M365UserPrincipalName {
    <#
    .SYNOPSIS
        Builds a user principal name from a person's name using a consistent naming convention.
    .DESCRIPTION
        Removes accents (an accented e becomes e), apostrophes, spaces and other characters that are not valid in
        a UPN, lower-cases the result and applies the chosen format. When a name is already taken,
        a number is appended (jane.doe2, jane.doe3, ...) until a free name is found.
    .PARAMETER GivenName
        First name.
    .PARAMETER Surname
        Last name.
    .PARAMETER Domain
        Verified domain, for example contoso.com.
    .PARAMETER Format
        FirstDotLast (jane.doe), FirstInitialLast (jdoe) or FirstLast (janedoe).
    .PARAMETER ExistingName
        UPNs that are already in use. Comparison is case-insensitive.
    .PARAMETER ExistsScript
        Optional script block that receives a candidate UPN and returns $true when it is taken,
        for example { param($u) Test-M365GraphUser -UserPrincipalName $u }.
    .EXAMPLE
        New-M365UserPrincipalName -GivenName 'Mary Ann' -Surname "O'Brien" -Domain contoso.com
        maryann.obrien@contoso.com
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure function: returns a value and changes no state.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$GivenName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Surname,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}$')]
        [string]$Domain,

        [ValidateSet('FirstDotLast', 'FirstInitialLast', 'FirstLast')]
        [string]$Format = 'FirstDotLast',

        [string[]]$ExistingName = @(),

        [scriptblock]$ExistsScript
    )

    $first = ConvertTo-M365AsciiName -Value $GivenName
    $last = ConvertTo-M365AsciiName -Value $Surname
    if (-not $first -or -not $last) {
        throw "Cannot build a user principal name from '$GivenName $Surname': no valid characters remain."
    }

    $alias = switch ($Format) {
        'FirstDotLast' { "$first.$last" }
        'FirstInitialLast' { "$($first.Substring(0, 1))$last" }
        'FirstLast' { "$first$last" }
    }
    # The local part of a UPN is limited to 64 characters; leave room for a numeric suffix.
    if ($alias.Length -gt 60) {
        $alias = $alias.Substring(0, 60).TrimEnd('.')
    }

    $taken = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $ExistingName) {
        if ($name) { [void]$taken.Add($name) }
    }

    $domainLower = $Domain.ToLowerInvariant()
    for ($n = 1; $n -le 999; $n++) {
        $suffix = if ($n -eq 1) { '' } else { "$n" }
        $candidate = "$alias$suffix@$domainLower"
        $inUse = $taken.Contains($candidate)
        if (-not $inUse -and $ExistsScript) {
            $inUse = [bool](& $ExistsScript $candidate)
        }
        if (-not $inUse) {
            return $candidate
        }
    }
    throw "No free user principal name found for '$alias@$domainLower'."
}

function ConvertTo-M365AsciiName {
    # Internal helper (not exported): strip diacritics and anything that is not a-z or 0-9.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    $decomposed = $Value.Normalize([Text.NormalizationForm]::FormD)
    $builder = [Text.StringBuilder]::new()
    foreach ($char in $decomposed.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($char) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($char)
        }
    }
    ($builder.ToString().ToLowerInvariant() -replace '[^a-z0-9]', '')
}
