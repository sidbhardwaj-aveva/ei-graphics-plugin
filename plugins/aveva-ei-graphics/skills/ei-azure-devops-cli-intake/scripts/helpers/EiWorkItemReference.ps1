#!/usr/bin/env pwsh
<#
.SYNOPSIS
Deterministic parsing of a pasted Azure DevOps work item reference.

.DESCRIPTION
The agent is handed a reference by a human, almost always as a pasted markdown link such as
`[Bug 4983245 SR350 - <title>](https://dev.azure.com/AVEVA-VSTS/Dabacon%20Products/_workitems/edit/4983245)`.
Reading the id off that link is a rule, not a judgement, so it belongs in a script rather than in
the model.

Organization and project are fixed for EI Graphics: every story lives in `AVEVA-VSTS` /
`Dabacon Products`, so the pasted link never decides them. A link that names something else is
ignored, not obeyed, which keeps two runs of the same story from recording two different projects.

Dot-source this file; it defines functions only.
#>

Set-StrictMode -Version Latest

$script:EiAdoDefaultOrganization = 'AVEVA-VSTS'
$script:EiAdoDefaultProject = 'Dabacon Products'

function Resolve-EiAdoOrganization {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Override = '')

    if (-not [string]::IsNullOrWhiteSpace($Override)) { return $Override.Trim() }
    if (-not [string]::IsNullOrWhiteSpace([string]$env:AZDO_ORG)) { return ([string]$env:AZDO_ORG).Trim() }
    return $script:EiAdoDefaultOrganization
}

function Resolve-EiAdoProject {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Override = '')

    if (-not [string]::IsNullOrWhiteSpace($Override)) { return $Override.Trim() }
    if (-not [string]::IsNullOrWhiteSpace([string]$env:AZDO_PROJECT)) { return ([string]$env:AZDO_PROJECT).Trim() }
    return $script:EiAdoDefaultProject
}

function Test-EiAdoHostUrl {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Url = '')

    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }

    try { $uri = [System.Uri]$Url } catch { return $false }
    if (-not $uri.IsAbsoluteUri -or [string]::IsNullOrWhiteSpace($uri.Host)) { return $false }

    return ($uri.Host.Equals('dev.azure.com', [System.StringComparison]::OrdinalIgnoreCase) -or
        $uri.Host.EndsWith('.visualstudio.com', [System.StringComparison]::OrdinalIgnoreCase))
}

function Split-EiWorkItemReference {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text = '')

    $parts = [ordered]@{ Url = ''; Label = '' }
    if ([string]::IsNullOrWhiteSpace($Text)) { return [PSCustomObject]$parts }

    $trimmed = $Text.Trim()

    # The link is searched for rather than required to be the whole string, because a pasted
    # reference often arrives with prose around it.
    $link = [regex]::Match($trimmed, '\[(?<label>[^\]]*)\]\(\s*<?(?<url>[^)<>\s]+)>?(?:\s+"[^"]*")?\s*\)')
    if ($link.Success) {
        $parts.Label = $link.Groups['label'].Value.Trim()
        $parts.Url = $link.Groups['url'].Value.Trim()
        return [PSCustomObject]$parts
    }

    $bare = [regex]::Match($trimmed, '[A-Za-z][A-Za-z0-9+.-]*://[^\s<>"'']+')
    if ($bare.Success) {
        $parts.Url = $bare.Value.TrimEnd('.', ',', ';', ':', '!', ')', ']')
        $parts.Label = ($trimmed.Remove($bare.Index, $bare.Length)).Trim()
        return [PSCustomObject]$parts
    }

    $parts.Label = $trimmed
    return [PSCustomObject]$parts
}

function Get-EiWorkItemIdFromLabel {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Label = '')

    if ([string]::IsNullOrWhiteSpace($Label)) { return '' }

    $typed = [regex]::Match($Label, '(?i)\b(?:bug|defect|issue|user\s+story|story|task|feature|epic|pbi|work\s*item)\s*#?\s*(?<id>[1-9][0-9]*)\b')
    if ($typed.Success) { return $typed.Groups['id'].Value }

    $hashed = [regex]::Match($Label, '#\s*(?<id>[1-9][0-9]*)\b')
    if ($hashed.Success) { return $hashed.Groups['id'].Value }

    # Identifiers such as "SR205" stay glued to their letters, so they never match this token.
    $bare = [regex]::Match($Label, '(?<![0-9A-Za-z])(?<id>[1-9][0-9]{2,})(?![0-9A-Za-z])')
    if ($bare.Success) { return $bare.Groups['id'].Value }

    return ''
}

function Get-EiAdoUrlWorkItemId {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Url = '')

    if (-not (Test-EiAdoHostUrl -Url $Url)) { return '' }

    $uri = [System.Uri]$Url
    $patterns = @(
        @{ Text = $uri.AbsolutePath; Pattern = '/_workitems/edit/(?<id>[1-9][0-9]*)' },
        @{ Text = $uri.AbsolutePath; Pattern = '/_apis/wit/work ?items/(?<id>[1-9][0-9]*)' },
        @{ Text = $uri.Query; Pattern = '(?:^|[?&])id=(?<id>[1-9][0-9]*)' },
        @{ Text = $uri.Query; Pattern = '(?:^|[?&])workitem=(?<id>[1-9][0-9]*)' }
    )

    foreach ($candidate in $patterns) {
        $match = [regex]::Match($candidate.Text, $candidate.Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) { return $match.Groups['id'].Value }
    }

    return ''
}

function Resolve-EiWorkItemReference {
    <#
    .SYNOPSIS
    Turn any pasted reference into a work item id plus the fixed EI Graphics org and project.

    .OUTPUTS
    PSCustomObject with status ('resolved' | 'failed'), reason, workItemId, workItemUrl,
    organization and project.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Reference = '',
        [AllowEmptyString()][string]$WorkItemId = '',
        [AllowEmptyString()][string]$Organization = '',
        [AllowEmptyString()][string]$Project = ''
    )

    $referenceText = "$Reference".Trim()
    $idText = "$WorkItemId".Trim()

    $result = [ordered]@{
        status       = 'failed'
        reason       = 'missing-work-item-url-or-id'
        workItemId   = ''
        workItemUrl  = ''
        organization = (Resolve-EiAdoOrganization -Override $Organization)
        project      = (Resolve-EiAdoProject -Override $Project)
    }

    if ([string]::IsNullOrWhiteSpace($referenceText) -and [string]::IsNullOrWhiteSpace($idText)) {
        return [PSCustomObject]$result
    }

    $adoUrl = ''
    $foreignUrl = ''
    $labels = [System.Collections.Generic.List[string]]::new()

    foreach ($text in @($referenceText, $idText)) {
        if ([string]::IsNullOrWhiteSpace($text)) { continue }

        $parts = Split-EiWorkItemReference -Text $text
        if (Test-EiAdoHostUrl -Url $parts.Url) {
            if ([string]::IsNullOrWhiteSpace($adoUrl)) { $adoUrl = $parts.Url }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($parts.Url) -and [string]::IsNullOrWhiteSpace($foreignUrl)) {
            $foreignUrl = $parts.Url
        }

        if (-not [string]::IsNullOrWhiteSpace($parts.Label)) { $labels.Add($parts.Label) }
    }

    $workItemIdValue = ''
    if ($idText -match '^[1-9][0-9]*$') {
        $workItemIdValue = $idText
    }
    else {
        $workItemIdValue = Get-EiAdoUrlWorkItemId -Url $adoUrl
    }

    if ([string]::IsNullOrWhiteSpace($workItemIdValue)) {
        foreach ($label in $labels) {
            $candidate = Get-EiWorkItemIdFromLabel -Label $label
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                $workItemIdValue = $candidate
                break
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($workItemIdValue)) {
        $result.reason =
            if (-not [string]::IsNullOrWhiteSpace($adoUrl)) { 'missing-work-item-id-in-url' }
            elseif (-not [string]::IsNullOrWhiteSpace($foreignUrl) -and $labels.Count -eq 0) { 'unsupported-work-item-url-host' }
            else { 'missing-work-item-id-in-reference' }

        return [PSCustomObject]$result
    }

    $result.workItemId = $workItemIdValue
    $result.workItemUrl = $adoUrl
    $result.status = 'resolved'
    $result.reason = ''
    return [PSCustomObject]$result
}
