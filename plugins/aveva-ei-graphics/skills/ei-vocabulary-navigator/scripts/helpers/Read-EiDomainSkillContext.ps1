#!/usr/bin/env pwsh
<#
.SYNOPSIS
Parse a domain skill SKILL.md and extract its domain knowledge and Key Files section.

.DESCRIPTION
Reads the given SKILL.md and returns a structured object containing:
  - domainId     : the registry id of the domain
  - displayName  : human-readable domain name
  - summary      : first substantive body sentence from the skill file (best-effort)
  - keyFiles     : array of {file, purpose} extracted from the "Key Files" markdown table
  - keyFilesNote : a reminder that key files are candidate evidence, not automatic scope

The Key Files section is located by finding the first heading whose text is "Key Files" (any
heading level). Rows from the markdown table that follows are parsed until the table ends (a line
that does not start with "|"). The header row and separator row are skipped automatically.

If no Key Files section is found the keyFiles array is empty.
If the SKILL.md cannot be read the function throws so the caller can decide whether to warn or block.

.OUTPUTS
PSCustomObject
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SkillPath,
    [Parameter(Mandatory)][string]$DomainId,
    [Parameter(Mandatory)][string]$DisplayName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SkillPath -PathType Leaf)) {
    throw "Domain skill SKILL.md was not found at '$SkillPath'."
}

$lines = Get-Content -LiteralPath $SkillPath

# ── Summary extraction ──────────────────────────────────────────────────────
# Walk past the title heading and find the first non-empty, non-heading,
# non-list, non-table, non-code-fence line of body text.
$summary = ''
$inCodeBlock = $false
$pastTitle = $false

foreach ($line in $lines) {
    if ($line -match '^\s*```') {
        $inCodeBlock = -not $inCodeBlock
        continue
    }
    if ($inCodeBlock) { continue }

    if (-not $pastTitle) {
        if ($line -match '^#\s+') { $pastTitle = $true }
        continue
    }

    # Skip headings, bullets, table rows, horizontal rules, and blank lines.
    if ($line -match '^\s*$') { continue }
    if ($line -match '^#+\s') { continue }
    if ($line -match '^\s*[-*+]\s') { continue }
    if ($line -match '^\s*\|') { continue }
    if ($line -match '^---+$') { continue }

    $summary = $line.Trim()
    break
}

# ── Key Files extraction ─────────────────────────────────────────────────────
# Locate the "Key Files" heading, then parse the table that follows.
$keyFiles = [System.Collections.Generic.List[object]]::new()
$inKeyFilesSection = $false
$tableStarted = $false
$separatorSeen = $false
$inCodeBlock = $false

foreach ($line in $lines) {
    if ($line -match '^\s*```') {
        $inCodeBlock = -not $inCodeBlock
        continue
    }
    if ($inCodeBlock) { continue }

    if (-not $inKeyFilesSection) {
        if ($line -match '^#+\s+Key Files\s*$') {
            $inKeyFilesSection = $true
        }
        continue
    }

    # A new heading ends the Key Files section.
    if ($line -match '^#+\s') { break }

    if (-not $tableStarted) {
        # Wait for the first table row (the header).
        if ($line -match '^\s*\|') { $tableStarted = $true }
        continue
    }

    # End of table: non-pipe, non-empty line after the table started.
    if ($line -notmatch '^\s*\|') {
        if ($line -match '^\s*$') { continue }   # allow blank lines inside the section
        break
    }

    # Skip the separator row (contains only |, -, and spaces).
    if ($line -match '^\s*\|[\s\-|]+\|\s*$') {
        $separatorSeen = $true
        continue
    }

    # Skip the header row (before separator) if separator not yet seen.
    if (-not $separatorSeen) { continue }

    # Parse a data row: | file | purpose |
    $cells = @($line -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    if ($cells.Count -lt 2) { continue }

    $filePath = $cells[0] -replace '`', ''      # strip backtick quoting
    $purpose  = $cells[1]

    if ([string]::IsNullOrWhiteSpace($filePath)) { continue }

    $keyFiles.Add([ordered]@{
        file    = $filePath
        purpose = $purpose
    })
}

[PSCustomObject]@{
    domainId     = $DomainId
    displayName  = $DisplayName
    summary      = $summary
    keyFiles     = @($keyFiles)
    keyFilesNote = 'Key files are candidate evidence for the scope-resolver to investigate. They are not automatically approved scope: the scope-resolver must find independent repository evidence before proposing any of them.'
}
