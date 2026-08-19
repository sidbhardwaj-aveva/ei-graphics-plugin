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
    $output = & az boards work-item show --id $WorkItemId --org $orgUrl --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = ($output -join [Environment]::NewLine)
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
