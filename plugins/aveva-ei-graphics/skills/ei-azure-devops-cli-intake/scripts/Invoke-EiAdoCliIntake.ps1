[CmdletBinding()]
param(
    [string]$WorkItemUrl = '',
    [string]$WorkItemId = '',
    [string]$Organization = '',
    [string]$Project = '',
    [string]$CliWorkItemJson = '',
    [string]$CliCommentsJson = '',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'helpers' 'EiWorkItemReference.ps1')

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

function Get-AttachmentUrls {
    param([string]$Html)
    if ([string]::IsNullOrWhiteSpace($Html)) { return @() }
    $found = [System.Collections.Generic.List[string]]::new()
    $imgMatches = [regex]::Matches($Html, '<img\s[^>]*src\s*=\s*(?:"(?<url>[^"]+)"|''(?<url>[^'']+)'')', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($m in $imgMatches) {
        # ADO stores the src HTML-encoded, so `&amp;` must be decoded or the download url loses its query.
        $url = [System.Net.WebUtility]::HtmlDecode($m.Groups['url'].Value)
        if ($url -match '(?i)(dev\.azure\.com|visualstudio\.com)') { $found.Add($url) }
    }
    return $found.ToArray()
}

function Get-RawProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-FieldValue {
    param(
        [object]$FieldBag,
        [string]$Name
    )

    return [string](Get-RawProperty -Object $FieldBag -Name $Name)
}

# Comments are a separate endpoint: `az boards work-item show` never returns them, so a story whose
# clarifications live in the discussion thread would otherwise reach the run as if they were never
# written. Retrieval is best-effort -- an unavailable thread is reported, never fatal.
function Get-WorkItemComments {
    param(
        [string]$Organization,
        [string]$Project,
        [string]$WorkItemId,
        [string]$MockJson,
        [bool]$IsMockRun
    )

    $empty = @()

    if (-not [string]::IsNullOrWhiteSpace($MockJson)) {
        try { $payload = $MockJson | ConvertFrom-Json -Depth 20 }
        catch { return [PSCustomObject]@{ status = 'unavailable'; reason = 'mock-comments-invalid'; comments = $empty } }
        return [PSCustomObject]@{ status = 'retrieved'; reason = 'mock-json'; comments = (ConvertTo-NormalizedComment -Payload $payload) }
    }

    if ($IsMockRun) {
        return [PSCustomObject]@{ status = 'skipped'; reason = 'mock-run-without-comments'; comments = $empty }
    }

    $url = 'https://dev.azure.com/{0}/{1}/_apis/wit/workItems/{2}/comments?api-version=7.1-preview.4' -f `
        [System.Uri]::EscapeDataString($Organization), [System.Uri]::EscapeDataString($Project), $WorkItemId

    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $output = & az rest --method get --url $url --resource '499b84ac-1321-427f-aa17-267ca6975798' --output json 2>$stderrFile
        $exitCode = $LASTEXITCODE
    }
    catch {
        $exitCode = 1
        $output = $null
    }
    finally {
        Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
    }

    if ($exitCode -ne 0) {
        return [PSCustomObject]@{ status = 'unavailable'; reason = 'comments-request-failed'; comments = $empty }
    }

    try { $payload = ($output -join [Environment]::NewLine) | ConvertFrom-Json -Depth 20 }
    catch { return [PSCustomObject]@{ status = 'unavailable'; reason = 'comments-invalid-json'; comments = $empty } }

    return [PSCustomObject]@{ status = 'retrieved'; reason = 'ado-cli'; comments = (ConvertTo-NormalizedComment -Payload $payload) }
}

function ConvertTo-NormalizedComment {
    param([object]$Payload)

    $items = Get-RawProperty -Object $Payload -Name 'comments'
    if ($null -eq $items) { return @() }

    # The endpoint returns newest-first; ordering by id makes the thread chronological and the
    # artifact byte-identical across runs.
    return @(@($items) | ForEach-Object {
        $html = [string](Get-RawProperty -Object $_ -Name 'text')
        [PSCustomObject]@{
            id          = [string](Get-RawProperty -Object $_ -Name 'id')
            author      = (Get-FieldValue -FieldBag (Get-RawProperty -Object $_ -Name 'createdBy') -Name 'displayName')
            createdDate = (ConvertTo-IsoTimestamp -Value (Get-RawProperty -Object $_ -Name 'createdDate'))
            text        = (Get-PlainText -Text $html)
            html        = $html
        }
    } | Sort-Object -Property @{ Expression = { [int64]($_.id -as [int64]) } }, id)
}

# ConvertFrom-Json turns an ISO-8601 string into a DateTime, and casting that back to string renders
# it in the current culture. Formatting explicitly keeps the artifact identical on every machine.
function ConvertTo-IsoTimestamp {
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

# Reference parsing is deterministic and lives in the shared helper, so a pasted markdown link, a
# bare URL, a reference title and a bare id all resolve the same way on every run.
$reference = Resolve-EiWorkItemReference -Reference $WorkItemUrl -WorkItemId $WorkItemId `
    -Organization $Organization -Project $Project

$Organization = $reference.organization
$Project = $reference.project

if ($reference.status -ne 'resolved') {
    $failed = [PSCustomObject]@{
        status = if ($reference.reason -eq 'missing-work-item-url-or-id') { 'blocked' } else { 'failed' }
        reason = $reference.reason
        workItemContext = [PSCustomObject]@{
            workItemUrl = $reference.workItemUrl
            workItemId = $reference.workItemId
            organization = $Organization
            project = $Project
            authSource = ''
        }
        descriptionText = ''
    }

    if ($Json) { $failed | ConvertTo-Json -Depth 6 } else { $failed }
    exit 1
}

$WorkItemUrl = $reference.workItemUrl
$WorkItemId = $reference.workItemId

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

# One ordered field list feeds both the plain-text story and the image scan, so a field can never be
# read for its prose but skipped for its images. EI stories keep most of their content -- and their
# screenshots -- in AcceptanceCriteria rather than Description.
$contentFieldNames = @(
    'System.Title',
    'System.Description',
    'Microsoft.VSTS.Common.AcceptanceCriteria',
    'Microsoft.VSTS.TCM.ReproSteps',
    'System.ReproSteps'
)
$contentFields = @($contentFieldNames | ForEach-Object { Get-FieldValue -FieldBag $fields -Name $_ })

$parts = @($contentFields |
    ForEach-Object { Get-PlainText -Text $_ } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

$commentResult = Get-WorkItemComments -Organization $Organization -Project $Project `
    -WorkItemId $WorkItemId -MockJson $CliCommentsJson -IsMockRun ($authSource -eq 'cli-mock-json')
$comments = @($commentResult.comments)

# Collect image attachment URLs from the story fields and the discussion thread, keeping the source
# so the agent can say which comment a picture came from. Deduplicate by URL, first source wins.
$seenUrls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$htmlSources = [System.Collections.Generic.List[object]]::new()
for ($i = 0; $i -lt $contentFieldNames.Count; $i++) {
    $htmlSources.Add([PSCustomObject]@{ source = "field:$($contentFieldNames[$i])"; html = $contentFields[$i] })
}
foreach ($comment in $comments) {
    $htmlSources.Add([PSCustomObject]@{ source = "comment:$($comment.id)"; html = $comment.html })
}

$attachmentUrls = @(
    $htmlSources | ForEach-Object {
        $source = $_.source
        Get-AttachmentUrls -Html $_.html | ForEach-Object { [PSCustomObject]@{ url = $_; source = $source } }
    } | Where-Object { $seenUrls.Add($_.url) }
)

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
    attachmentUrls  = $attachmentUrls
    commentRetrieval = [PSCustomObject]@{
        status = $commentResult.status
        reason = $commentResult.reason
    }
    # `html` is dropped here: it was only ever needed to scan the thread for images.
    comments = @($comments | ForEach-Object {
        [PSCustomObject]@{ id = $_.id; author = $_.author; createdDate = $_.createdDate; text = $_.text }
    })
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
}
else {
    $result
}

exit 0
