[CmdletBinding()]
param(
    [string]$WorkItemUrl = '',
    [string]$WorkItemId = '',
    [string]$Organization = '',
    [string]$Project = '',
    [string]$CliWorkItemJson = '',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WorkItemUrl = $WorkItemUrl.Trim()
$WorkItemId = $WorkItemId.Trim()
$Organization = $Organization.Trim()
$Project = $Project.Trim()

function Get-PlainText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $withoutTags = [regex]::Replace($Text, '<[^>]+>', ' ')
    $decoded = [System.Net.WebUtility]::HtmlDecode($withoutTags)
    return [regex]::Replace($decoded, '\s+', ' ').Trim()
}

function Get-FieldValue {
    param(
        [object]$FieldBag,
        [string]$Name
    )

    if ($null -eq $FieldBag -or [string]::IsNullOrWhiteSpace($Name)) {
        return ''
    }

    $property = $FieldBag.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return ''
    }

    return [string]$property.Value
}

function Test-AdoHostUrl {
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $false
    }

    try {
        $uri = [System.Uri]$Url
    }
    catch {
        return $false
    }

    if (-not $uri.IsAbsoluteUri -or [string]::IsNullOrWhiteSpace($uri.Host)) {
        return $false
    }

    return ($uri.Host.Equals('dev.azure.com', [System.StringComparison]::OrdinalIgnoreCase) -or
        $uri.Host.EndsWith('.visualstudio.com', [System.StringComparison]::OrdinalIgnoreCase))
}

function Split-WorkItemReference {
    param([string]$Text)

    $reference = [ordered]@{ url = ''; label = '' }

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return [PSCustomObject]$reference
    }

    $trimmed = $Text.Trim()
    $link = [regex]::Match($trimmed, '^\[(?<label>[^\]]+)\]\(\s*(?<url>[^)\s]+)\s*\)$')
    if ($link.Success) {
        $reference.label = $link.Groups['label'].Value.Trim()
        $reference.url = $link.Groups['url'].Value.Trim()
    }
    elseif ($trimmed -match '^[A-Za-z][A-Za-z0-9+.-]*://') {
        $reference.url = $trimmed
    }
    else {
        $reference.label = $trimmed
    }

    return [PSCustomObject]$reference
}

function Get-WorkItemIdFromLabel {
    param([string]$Label)

    if ([string]::IsNullOrWhiteSpace($Label)) {
        return ''
    }

    $typed = [regex]::Match($Label, '(?i)\b(?:bug|defect|issue|user\s+story|story|task|feature|epic|pbi|work\s*item)\s*#?\s*(?<id>[1-9][0-9]*)\b')
    if ($typed.Success) {
        return $typed.Groups['id'].Value
    }

    $hashed = [regex]::Match($Label, '#\s*(?<id>[1-9][0-9]*)\b')
    if ($hashed.Success) {
        return $hashed.Groups['id'].Value
    }

    # Identifiers such as "SR205" stay glued to their letters, so they never match this token.
    $bare = [regex]::Match($Label, '(?<![0-9A-Za-z])(?<id>[1-9][0-9]{2,})(?![0-9A-Za-z])')
    if ($bare.Success) {
        return $bare.Groups['id'].Value
    }

    return ''
}

function Resolve-FromWorkItemUrl {
    param([string]$Url)

    $result = [ordered]@{
        status = 'failed'
        reason = 'invalid-work-item-url'
        workItemId = ''
        organization = ''
        project = ''
    }

    if ([string]::IsNullOrWhiteSpace($Url)) {
        $result.reason = 'missing-work-item-url'
        return [PSCustomObject]$result
    }

    try {
        $uri = [System.Uri]$Url
    }
    catch {
        return [PSCustomObject]$result
    }

    if (-not $uri.IsAbsoluteUri -or [string]::IsNullOrWhiteSpace($uri.Host)) {
        return [PSCustomObject]$result
    }

    $segments = @($uri.AbsolutePath.Trim('/').Split('/', [System.StringSplitOptions]::RemoveEmptyEntries))

    if ($uri.Host.Equals('dev.azure.com', [System.StringComparison]::OrdinalIgnoreCase)) {
        if ($segments.Count -ge 2) {
            $result.organization = [string]$segments[0]
            $result.project = [System.Uri]::UnescapeDataString([string]$segments[1])
        }
    }
    elseif ($uri.Host.EndsWith('.visualstudio.com', [System.StringComparison]::OrdinalIgnoreCase)) {
        $result.organization = [string]($uri.Host.Split('.')[0])
        if ($segments.Count -ge 1) {
            $result.project = [System.Uri]::UnescapeDataString([string]$segments[0])
        }
    }
    else {
        $result.reason = 'unsupported-work-item-url-host'
        return [PSCustomObject]$result
    }

    $idMatch = [regex]::Match($uri.AbsolutePath, '/_workitems/edit/(?<id>[1-9][0-9]*)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $idMatch.Success) {
        $idMatch = [regex]::Match($uri.AbsolutePath, '/_apis/wit/workitems/(?<id>[1-9][0-9]*)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    if (-not $idMatch.Success) {
        $idMatch = [regex]::Match($uri.Query, '(?:^|[?&])id=(?<id>[1-9][0-9]*)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    # Boards URL: _boards/board/...?workitem=<id>
    if (-not $idMatch.Success) {
        $idMatch = [regex]::Match($uri.Query, '(?:^|[?&])workitem=(?<id>[1-9][0-9]*)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    if (-not $idMatch.Success) {
        $result.reason = 'missing-work-item-id-in-url'
        return [PSCustomObject]$result
    }

    $result.workItemId = [string]$idMatch.Groups['id'].Value
    if ([string]::IsNullOrWhiteSpace($result.organization) -or [string]::IsNullOrWhiteSpace($result.project)) {
        $result.reason = 'missing-organization-or-project'
        return [PSCustomObject]$result
    }

    $result.status = 'resolved'
    $result.reason = ''
    return [PSCustomObject]$result
}

function Get-AdoCliFailureReason {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return 'az-cli-request-failed'
    }

    if ($Message -match 'TF401019|not found|does not exist|could not be found') {
        return 'ado-work-item-not-found'
    }
    if ($Message -match 'TF401444|not authorized|unauthorized|access denied|401|403') {
        return 'ado-auth-failed'
    }
    if ($Message -match 'az login|not logged in|run "az login"') {
        return 'az-cli-not-authenticated'
    }

    return 'az-cli-request-failed'
}

# A reference is often pasted as a markdown link whose href is a local editor address rather than the
# work item, for example `[Bug 4965976 SR205 - ...](vscode-file://.../workbench.html)`. In that case
# the identity lives in the label, so the href is discarded instead of failing as an unsupported host.
$referenceLabel = ''

if (-not [string]::IsNullOrWhiteSpace($WorkItemUrl)) {
    $reference = Split-WorkItemReference -Text $WorkItemUrl
    if ([string]::IsNullOrWhiteSpace($reference.url) -or
        (-not (Test-AdoHostUrl -Url $reference.url) -and -not [string]::IsNullOrWhiteSpace($reference.label))) {
        $referenceLabel = $reference.label
        $WorkItemUrl = ''
    }
    else {
        $WorkItemUrl = $reference.url
    }
}

if (-not [string]::IsNullOrWhiteSpace($WorkItemId) -and $WorkItemId -notmatch '^[1-9][0-9]*$') {
    $reference = Split-WorkItemReference -Text $WorkItemId
    if (Test-AdoHostUrl -Url $reference.url) {
        if ([string]::IsNullOrWhiteSpace($WorkItemUrl)) { $WorkItemUrl = $reference.url }
        $WorkItemId = ''
    }
    else {
        $WorkItemId = Get-WorkItemIdFromLabel -Label $reference.label
        if ([string]::IsNullOrWhiteSpace($referenceLabel)) { $referenceLabel = $reference.label }
    }
}

if ([string]::IsNullOrWhiteSpace($WorkItemUrl) -and [string]::IsNullOrWhiteSpace($WorkItemId) -and
    -not [string]::IsNullOrWhiteSpace($referenceLabel)) {
    $WorkItemId = Get-WorkItemIdFromLabel -Label $referenceLabel
    if ([string]::IsNullOrWhiteSpace($WorkItemId)) {
        $failed = [PSCustomObject]@{
            status = 'failed'
            reason = 'missing-work-item-id-in-reference'
            workItemContext = [PSCustomObject]@{
                workItemUrl = ''
                workItemId = ''
                organization = $Organization
                project = $Project
                authSource = ''
            }
            descriptionText = ''
        }

        if ($Json) { $failed | ConvertTo-Json -Depth 6 } else { $failed }
        exit 1
    }
}

if ([string]::IsNullOrWhiteSpace($WorkItemUrl) -and [string]::IsNullOrWhiteSpace($WorkItemId)) {
    $blocked = [PSCustomObject]@{
        status = 'blocked'
        reason = 'missing-work-item-url-or-id'
        workItemContext = [PSCustomObject]@{
            workItemUrl = $WorkItemUrl
            workItemId = $WorkItemId
            organization = $Organization
            project = $Project
            authSource = ''
        }
        descriptionText = ''
    }

    if ($Json) { $blocked | ConvertTo-Json -Depth 6 } else { $blocked }
    exit 1
}

if (-not [string]::IsNullOrWhiteSpace($WorkItemUrl)) {
    $resolved = Resolve-FromWorkItemUrl -Url $WorkItemUrl
    if ($resolved.status -eq 'resolved') {
        if ([string]::IsNullOrWhiteSpace($WorkItemId)) { $WorkItemId = $resolved.workItemId }
        if ([string]::IsNullOrWhiteSpace($Organization)) { $Organization = $resolved.organization }
        if ([string]::IsNullOrWhiteSpace($Project)) { $Project = $resolved.project }
    }
    else {
        $failed = [PSCustomObject]@{
            status = 'failed'
            reason = $resolved.reason
            workItemContext = [PSCustomObject]@{
                workItemUrl = $WorkItemUrl
                workItemId = $WorkItemId
                organization = $Organization
                project = $Project
                authSource = ''
            }
            descriptionText = ''
        }

        if ($Json) { $failed | ConvertTo-Json -Depth 6 } else { $failed }
        exit 1
    }
}

if ([string]::IsNullOrWhiteSpace($Organization)) {
    $Organization = [string]$env:AZDO_ORG
}
if ([string]::IsNullOrWhiteSpace($Project)) {
    $Project = [string]$env:AZDO_PROJECT
}

# Fixed AVEVA defaults — org and project never change for this plugin.
if ([string]::IsNullOrWhiteSpace($Organization)) { $Organization = 'AVEVA-VSTS' }
if ([string]::IsNullOrWhiteSpace($Project))      { $Project      = 'Dabacon Products' }

if ($WorkItemId -notmatch '^[1-9][0-9]*$') {
    $failed = [PSCustomObject]@{
        status = 'failed'
        reason = 'invalid-work-item-id'
        workItemContext = [PSCustomObject]@{
            workItemUrl = $WorkItemUrl
            workItemId = $WorkItemId
            organization = $Organization
            project = $Project
            authSource = ''
        }
        descriptionText = ''
    }

    if ($Json) { $failed | ConvertTo-Json -Depth 6 } else { $failed }
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Organization) -or [string]::IsNullOrWhiteSpace($Project)) {
    $failed = [PSCustomObject]@{
        status = 'failed'
        reason = 'missing-organization-or-project'
        workItemContext = [PSCustomObject]@{
            workItemUrl = $WorkItemUrl
            workItemId = $WorkItemId
            organization = $Organization
            project = $Project
            authSource = ''
        }
        descriptionText = ''
    }

    if ($Json) { $failed | ConvertTo-Json -Depth 6 } else { $failed }
    exit 1
}

$workItem = $null
$authSource = ''

if (-not [string]::IsNullOrWhiteSpace($CliWorkItemJson)) {
    try {
        $workItem = $CliWorkItemJson | ConvertFrom-Json -Depth 20
        $authSource = 'cli-mock-json'
    }
    catch {
        $failed = [PSCustomObject]@{
            status = 'failed'
            reason = 'mock-json-invalid'
            workItemContext = [PSCustomObject]@{
                workItemUrl = $WorkItemUrl
                workItemId = $WorkItemId
                organization = $Organization
                project = $Project
                authSource = ''
            }
            descriptionText = ''
        }

        if ($Json) { $failed | ConvertTo-Json -Depth 6 } else { $failed }
        exit 1
    }
}
else {
    $azCommand = Get-Command az -ErrorAction SilentlyContinue
    if ($null -eq $azCommand) {
        $failed = [PSCustomObject]@{
            status = 'failed'
            reason = 'az-cli-not-installed'
            workItemContext = [PSCustomObject]@{
                workItemUrl = $WorkItemUrl
                workItemId = $WorkItemId
                organization = $Organization
                project = $Project
                authSource = ''
            }
            descriptionText = ''
        }

        if ($Json) { $failed | ConvertTo-Json -Depth 6 } else { $failed }
        exit 1
    }

    $orgUrl = "https://dev.azure.com/$([System.Uri]::EscapeDataString($Organization))"
    # Capture stderr in a temp file so the cp1252 encoding warning never contaminates the JSON.
    $stderrFile = [System.IO.Path]::GetTempFileName()
    $output = & az boards work-item show --id $WorkItemId --org $orgUrl --output json 2>$stderrFile
    $azExitCode = $LASTEXITCODE
    $stderrText = Get-Content -LiteralPath $stderrFile -Raw -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
    if ($azExitCode -ne 0) {
        $message = [string]$stderrText
        $failed = [PSCustomObject]@{
            status = 'failed'
            reason = (Get-AdoCliFailureReason -Message $message)
            workItemContext = [PSCustomObject]@{
                workItemUrl = $WorkItemUrl
                workItemId = $WorkItemId
                organization = $Organization
                project = $Project
                authSource = 'az-cli'
            }
            descriptionText = ''
        }

        if ($Json) { $failed | ConvertTo-Json -Depth 6 } else { $failed }
        exit 1
    }

    try {
        $workItem = ($output -join [Environment]::NewLine) | ConvertFrom-Json -Depth 20
        $authSource = 'az-cli-session'
    }
    catch {
        $failed = [PSCustomObject]@{
            status = 'failed'
            reason = 'az-cli-invalid-json'
            workItemContext = [PSCustomObject]@{
                workItemUrl = $WorkItemUrl
                workItemId = $WorkItemId
                organization = $Organization
                project = $Project
                authSource = 'az-cli'
            }
            descriptionText = ''
        }

        if ($Json) { $failed | ConvertTo-Json -Depth 6 } else { $failed }
        exit 1
    }
}

$fields = $workItem.fields
$parts = @(@(
    (Get-PlainText -Text (Get-FieldValue -FieldBag $fields -Name 'System.Title')),
    (Get-PlainText -Text (Get-FieldValue -FieldBag $fields -Name 'System.Description')),
    (Get-PlainText -Text (Get-FieldValue -FieldBag $fields -Name 'Microsoft.VSTS.TCM.ReproSteps')),
    (Get-PlainText -Text (Get-FieldValue -FieldBag $fields -Name 'System.ReproSteps'))
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

if (@($parts).Count -eq 0) {
    $failed = [PSCustomObject]@{
        status = 'failed'
        reason = 'ado-response-missing-fields'
        workItemContext = [PSCustomObject]@{
            workItemUrl = $WorkItemUrl
            workItemId = $WorkItemId
            organization = $Organization
            project = $Project
            authSource = $authSource
        }
        descriptionText = ''
    }

    if ($Json) { $failed | ConvertTo-Json -Depth 6 } else { $failed }
    exit 1
}

$result = [PSCustomObject]@{
    status = 'retrieved'
    reason = if ($authSource -eq 'cli-mock-json') { 'mock-json' } else { 'ado-cli' }
    workItemContext = [PSCustomObject]@{
        workItemUrl = $WorkItemUrl
        workItemId = $WorkItemId
        organization = $Organization
        project = $Project
        authSource = $authSource
    }
    descriptionText = ($parts -join ' ')
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
}
else {
    $result
}

exit 0
