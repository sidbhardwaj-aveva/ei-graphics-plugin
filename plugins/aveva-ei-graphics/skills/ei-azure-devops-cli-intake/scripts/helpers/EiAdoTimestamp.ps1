#!/usr/bin/env pwsh
<#
.DESCRIPTION
Shared timestamp normalisation for the Azure DevOps intake scripts.

ConvertFrom-Json turns an ISO-8601 string into a DateTime, and casting that DateTime back to a
string renders it in the current culture ("08/01/2026 10:00:00" on an en-GB machine). Every hop
that deserialises and re-serialises the intake payload therefore has to format explicitly, or the
sealed artifact stops being byte-identical across machines and downstream readers can no longer
recognise the value as a date.
#>

Set-StrictMode -Version Latest

function ConvertTo-EiIsoTimestamp {
    param([object]$Value)

    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) {
        return ([datetime]$Value).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [datetimeoffset]) {
        return ([datetimeoffset]$Value).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return [string]$Value
}
