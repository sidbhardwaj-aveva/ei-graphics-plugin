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
    $imgMatches = [regex]::Matches($Html, '<img\s[^>]*src\s*=\s*"(?<url>[^"]+)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($m in $imgMatches) {
        $url = $m.Groups['url'].Value
        if ($url -match '(?i)(dev\.azure\.com|visualstudio\.com)') { $found.Add($url) }
    }
    return $found.ToArray()
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
$parts = @(@(
    (Get-PlainText -Text (Get-FieldValue -FieldBag $fields -Name 'System.Title')),
    (Get-PlainText -Text (Get-FieldValue -FieldBag $fields -Name 'System.Description')),
    (Get-PlainText -Text (Get-FieldValue -FieldBag $fields -Name 'Microsoft.VSTS.TCM.ReproSteps')),
    (Get-PlainText -Text (Get-FieldValue -FieldBag $fields -Name 'System.ReproSteps'))
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

# Collect image attachment URLs from all HTML fields; deduplicate by URL.
$seenUrls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$attachmentUrls = @(
    @(
        (Get-FieldValue -FieldBag $fields -Name 'System.Description'),
        (Get-FieldValue -FieldBag $fields -Name 'Microsoft.VSTS.TCM.ReproSteps'),
        (Get-FieldValue -FieldBag $fields -Name 'System.ReproSteps')
    ) | ForEach-Object { Get-AttachmentUrls -Html $_ } |
        Where-Object { $seenUrls.Add($_) } |
        ForEach-Object { [PSCustomObject]@{ url = $_ } }
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
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
}
else {
    $result
}

exit 0
