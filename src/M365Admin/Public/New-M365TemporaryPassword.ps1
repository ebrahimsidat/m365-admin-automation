function New-M365TemporaryPassword {
    <#
    .SYNOPSIS
        Generates a random temporary password that meets Entra ID complexity requirements.
    .DESCRIPTION
        Uses a cryptographically secure random number generator. The password always contains at
        least one upper-case letter, lower-case letter, digit and symbol, and avoids characters that
        are easily confused (0/O, 1/l/I). Users are forced to change it at first sign-in.
    .PARAMETER Length
        Password length, 14 to 256 characters (default 16).
    .PARAMETER AsSecureString
        Return a SecureString instead of plain text.
    .EXAMPLE
        New-M365TemporaryPassword -Length 20
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure function: returns a value and changes no state.')]
    [CmdletBinding()]
    [OutputType([string], [securestring])]
    param(
        [ValidateRange(14, 256)]
        [int]$Length = 16,

        [switch]$AsSecureString
    )

    $sets = @(
        'ABCDEFGHJKLMNPQRSTUVWXYZ',
        'abcdefghijkmnopqrstuvwxyz',
        '23456789',
        '!@#$%^&*-_=+?'
    )
    $all = -join $sets

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $next = {
            param([int]$Max)
            # Rejection sampling avoids modulo bias.
            $bytes = [byte[]]::new(4)
            $limit = [uint32]::MaxValue - ([uint32]::MaxValue % [uint32]$Max)
            do {
                $rng.GetBytes($bytes)
                $value = [BitConverter]::ToUInt32($bytes, 0)
            } while ($value -ge $limit)
            [int]($value % [uint32]$Max)
        }

        $chars = [System.Collections.Generic.List[char]]::new()
        foreach ($set in $sets) {
            $chars.Add($set[(& $next $set.Length)])
        }
        while ($chars.Count -lt $Length) {
            $chars.Add($all[(& $next $all.Length)])
        }
        # Fisher-Yates shuffle so the guaranteed characters are not always first.
        for ($i = $chars.Count - 1; $i -gt 0; $i--) {
            $j = & $next ($i + 1)
            $tmp = $chars[$i]
            $chars[$i] = $chars[$j]
            $chars[$j] = $tmp
        }
    }
    finally {
        $rng.Dispose()
    }

    $password = -join $chars
    if ($AsSecureString) {
        $secure = [securestring]::new()
        foreach ($c in $password.ToCharArray()) { $secure.AppendChar($c) }
        $secure.MakeReadOnly()
        return $secure
    }
    $password
}
