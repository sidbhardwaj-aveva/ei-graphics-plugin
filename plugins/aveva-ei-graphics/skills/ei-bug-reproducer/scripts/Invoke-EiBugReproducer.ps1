[CmdletBinding()]
param(
    [string]$BugId = '',
    [string]$WorkItemUrl = '',
    [string]$DescriptionText = '',
    [string]$Organization = '',
    [string]$Project = '',
    [string]$AccessToken = '',
    [string]$AdoWorkItemJson = '',
    [string[]]$Keywords = @(),
    [switch]$UseAzCliToken,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BugId = $BugId.Trim()
$WorkItemUrl = $WorkItemUrl.Trim()
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

function Get-AdoAuthHeader {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return @{}
    }

    if ($Token.StartsWith('eyJ', [System.StringComparison]::Ordinal)) {
        return @{
            Authorization = "Bearer $Token"
            'X-TFS-FedAuthRedirect' = 'Suppress'
        }
    }

    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$Token"))
    return @{
        Authorization = "Basic $encoded"
        'X-TFS-FedAuthRedirect' = 'Suppress'
    }
}

function Get-AdoOrganizationFromUri {
    param([string]$CollectionUri)

    if ([string]::IsNullOrWhiteSpace($CollectionUri)) {
        return ''
    }

    try {
        $uri = [System.Uri]$CollectionUri
        if (-not $uri.Host.Equals('dev.azure.com', [System.StringComparison]::OrdinalIgnoreCase)) {
            return ''
        }

        $segments = @($uri.AbsolutePath.Trim('/').Split('/', [System.StringSplitOptions]::RemoveEmptyEntries))
        if ($segments.Count -lt 1) {
            return ''
        }

        return [string]$segments[0]
    }
    catch {
        return ''
    }
}

function Resolve-AdoContext {
    param(
        [string]$Organization,
        [string]$Project
    )

    $resolvedOrganization = $Organization.Trim()
    $resolvedProject = $Project.Trim()

    if ([string]::IsNullOrWhiteSpace($resolvedOrganization)) {
        $resolvedOrganization = [string]$env:AZDO_ORG
    }
    if ([string]::IsNullOrWhiteSpace($resolvedOrganization)) {
        $resolvedOrganization = Get-AdoOrganizationFromUri -CollectionUri ([string]$env:SYSTEM_COLLECTIONURI)
    }

    if ([string]::IsNullOrWhiteSpace($resolvedProject)) {
        $resolvedProject = [string]$env:AZDO_PROJECT
    }
    if ([string]::IsNullOrWhiteSpace($resolvedProject)) {
        $resolvedProject = [string]$env:SYSTEM_TEAMPROJECT
    }

    return [PSCustomObject]@{
        organization = $resolvedOrganization
        project = $resolvedProject
    }
}

function Resolve-AdoContextFromWorkItemUrl {
    param([string]$Url)

    $result = [ordered]@{
        status = 'failed'
        reason = 'invalid-work-item-url'
        bugId = ''
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

    $result.bugId = [string]$idMatch.Groups['id'].Value
    if ([string]::IsNullOrWhiteSpace($result.organization) -or [string]::IsNullOrWhiteSpace($result.project)) {
        $result.reason = 'missing-organization-or-project'
        return [PSCustomObject]$result
    }

    $result.status = 'resolved'
    $result.reason = ''
    return [PSCustomObject]$result
}

function Get-AdoFailureReason {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    if ($null -eq $ErrorRecord) {
        return 'ado-request-failed'
    }

    $statusCodeProperty = $ErrorRecord.Exception.PSObject.Properties['ResponseStatusCode']
    if ($null -ne $statusCodeProperty -and $null -ne $statusCodeProperty.Value) {
        $statusCode = [int]$statusCodeProperty.Value
        if ($statusCode -eq 401 -or $statusCode -eq 403) { return 'ado-auth-failed' }
        if ($statusCode -eq 404) { return 'ado-work-item-not-found' }
        if ($statusCode -eq 429) { return 'ado-throttled' }
        if ($statusCode -ge 500) { return 'ado-server-error' }
        return 'ado-request-failed'
    }

    $responseProperty = $ErrorRecord.Exception.PSObject.Properties['Response']
    if ($null -ne $responseProperty -and $null -ne $responseProperty.Value) {
        $response = $responseProperty.Value
        $statusCodeObject = $response.PSObject.Properties['StatusCode']
        if ($null -ne $statusCodeObject -and $null -ne $statusCodeObject.Value) {
            $statusCode = [int]$statusCodeObject.Value
            if ($statusCode -eq 401 -or $statusCode -eq 403) { return 'ado-auth-failed' }
            if ($statusCode -eq 404) { return 'ado-work-item-not-found' }
            if ($statusCode -eq 429) { return 'ado-throttled' }
            if ($statusCode -ge 500) { return 'ado-server-error' }
        }
    }

    $message = [string]$ErrorRecord.Exception.Message
    if ($message -match 'Maximum redirection count has been exceeded|_signin\?realm=dev\.azure\.com|Object moved') {
        return 'ado-auth-failed'
    }

    if ($message -match 'sign-in page instead of data|Content-Type') {
        return 'ado-auth-failed'
    }

    return 'ado-request-failed'
}

function Get-AdoCliAccessToken {
    param([string]$Organization)

    $azCommand = Get-Command az -ErrorAction SilentlyContinue
    if ($null -eq $azCommand) {
        return ''
    }

    $arguments = @('account', 'get-access-token', '--resource', '499b84ac-1321-427f-aa17-267ca6975798', '--output', 'json')

    if (-not [string]::IsNullOrWhiteSpace($Organization)) {
        $orgTenant = ''
        try {
            $probe = Invoke-WebRequest -Uri "https://vssps.dev.azure.com/$Organization" -Method Head -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Stop
            $orgTenant = [string]$probe.Headers['x-vss-resourcetenant']
        }
        catch {
            $response = $_.Exception.PSObject.Properties['Response']
            if ($null -ne $response -and $null -ne $response.Value -and $null -ne $response.Value.Headers) {
                $headerValue = $response.Value.Headers['x-vss-resourcetenant']
                if ($null -ne $headerValue) {
                    $orgTenant = [string]$headerValue
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($orgTenant)) {
            $arguments += @('--tenant', $orgTenant)
        }
    }

    try {
        $json = & az @arguments 2>$null
        if ($LASTEXITCODE -ne 0) {
            return ''
        }

        $tokenData = $json | ConvertFrom-Json -Depth 10
        return [string]$tokenData.accessToken
    }
    catch {
        return ''
    }
}

function Invoke-AdoWorkItemRequest {
    param(
        [string]$Url,
        [hashtable]$Headers
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -Method Get -Headers $Headers -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Stop
    }
    catch {
        return [PSCustomObject]@{
            status = 'failed'
            reason = (Get-AdoFailureReason -ErrorRecord $_)
            workItem = $null
        }
    }

    $statusCode = [int]$response.StatusCode
    $contentType = [string]$response.Headers['Content-Type']

    if ($statusCode -eq 401 -or $statusCode -eq 403) {
        return [PSCustomObject]@{ status = 'failed'; reason = 'ado-auth-failed'; workItem = $null }
    }
    if ($statusCode -eq 404) {
        return [PSCustomObject]@{ status = 'failed'; reason = 'ado-work-item-not-found'; workItem = $null }
    }
    if ($statusCode -eq 429) {
        return [PSCustomObject]@{ status = 'failed'; reason = 'ado-throttled'; workItem = $null }
    }
    if ($statusCode -ge 500) {
        return [PSCustomObject]@{ status = 'failed'; reason = 'ado-server-error'; workItem = $null }
    }
    if ($statusCode -eq 301 -or $statusCode -eq 302 -or $statusCode -eq 307 -or $statusCode -eq 308) {
        return [PSCustomObject]@{ status = 'failed'; reason = 'ado-auth-failed'; workItem = $null }
    }
    if ($statusCode -lt 200 -or $statusCode -gt 299) {
        return [PSCustomObject]@{ status = 'failed'; reason = 'ado-request-failed'; workItem = $null }
    }

    if (-not [string]::IsNullOrWhiteSpace($contentType) -and $contentType -notlike '*application/json*') {
        return [PSCustomObject]@{ status = 'failed'; reason = 'ado-auth-failed'; workItem = $null }
    }

    try {
        $workItem = $response.Content | ConvertFrom-Json -Depth 20
        return [PSCustomObject]@{ status = 'ok'; reason = ''; workItem = $workItem }
    }
    catch {
        return [PSCustomObject]@{ status = 'failed'; reason = 'ado-request-failed'; workItem = $null }
    }
}

function Invoke-EiAdoCliIntakeSkill {
    param(
        [string]$WorkItemUrl,
        [string]$Organization,
        [string]$Project,
        [string]$CliWorkItemJson
    )

    $skillScript = Join-Path $PSScriptRoot '..' '..' 'ei-azure-devops-cli-intake' 'scripts' 'Invoke-EiAdoCliIntake.ps1'
    if (-not (Test-Path -LiteralPath $skillScript -PathType Leaf)) {
        return [PSCustomObject]@{
            status = 'failed'
            reason = 'ado-cli-intake-skill-missing'
            workItemId = ''
            organization = $Organization
            project = $Project
            descriptionText = ''
            authSource = ''
        }
    }

    $output = & $skillScript -WorkItemUrl $WorkItemUrl -Organization $Organization -Project $Project -CliWorkItemJson $CliWorkItemJson -Json
    $exitCode = $LASTEXITCODE

    if ([string]::IsNullOrWhiteSpace(($output -join ''))) {
        return [PSCustomObject]@{
            status = 'failed'
            reason = 'ado-cli-intake-empty-response'
            workItemId = ''
            organization = $Organization
            project = $Project
            descriptionText = ''
            authSource = ''
        }
    }

    try {
        $parsed = ($output | ConvertFrom-Json -Depth 20)
    }
    catch {
        return [PSCustomObject]@{
            status = 'failed'
            reason = 'ado-cli-intake-invalid-response'
            workItemId = ''
            organization = $Organization
            project = $Project
            descriptionText = ''
            authSource = ''
        }
    }

    if ($exitCode -eq 0 -and $parsed.status -eq 'retrieved') {
        return [PSCustomObject]@{
            status = 'retrieved'
            reason = [string]$parsed.reason
            workItemId = [string]$parsed.workItemContext.workItemId
            organization = [string]$parsed.workItemContext.organization
            project = [string]$parsed.workItemContext.project
            descriptionText = [string]$parsed.descriptionText
            authSource = [string]$parsed.workItemContext.authSource
        }
    }

    return [PSCustomObject]@{
        status = 'failed'
        reason = [string]$parsed.reason
        workItemId = [string]$parsed.workItemContext.workItemId
        organization = [string]$parsed.workItemContext.organization
        project = [string]$parsed.workItemContext.project
        descriptionText = [string]$parsed.descriptionText
        authSource = [string]$parsed.workItemContext.authSource
    }
}

function Get-RetrievalConfidenceCap {
    param([string]$Reason)

    switch ($Reason) {
        'ado-auth-failed' { return 0.2 }
        'ado-throttled' { return 0.2 }
        'ado-server-error' { return 0.2 }
        'ado-request-failed' { return 0.25 }
        'missing-auth-token' { return 0.25 }
        'ado-work-item-not-found' { return 0.3 }
        'invalid-bug-id' { return 0.3 }
        'missing-organization-or-project' { return 0.35 }
        default { return 0.35 }
    }
}

function Get-IsTransientRetrievalReason {
    param([string]$Reason)

    return @('ado-throttled', 'ado-server-error', 'ado-request-failed').Contains($Reason)
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

function Get-AdoBugContext {
    param(
        [string]$BugId,
        [string]$Organization,
        [string]$Project,
        [string]$AccessToken,
        [string]$AdoWorkItemJson,
        [switch]$UseAzCliToken
    )

    $context = [ordered]@{
        status = 'not-attempted'
        reason = ''
        descriptionText = ''
        organization = ''
        project = ''
        authSource = ''
    }

    if (-not [string]::IsNullOrWhiteSpace($AdoWorkItemJson)) {
        try {
            $workItem = $AdoWorkItemJson | ConvertFrom-Json -Depth 20
            $fields = $workItem.fields
            $parts = @(@(
                (Get-PlainText -Text (Get-FieldValue -FieldBag $fields -Name 'System.Title')),
                (Get-PlainText -Text (Get-FieldValue -FieldBag $fields -Name 'System.Description')),
                (Get-PlainText -Text (Get-FieldValue -FieldBag $fields -Name 'Microsoft.VSTS.TCM.ReproSteps')),
                (Get-PlainText -Text (Get-FieldValue -FieldBag $fields -Name 'System.ReproSteps'))
            ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

            if (@($parts).Count -gt 0) {
                $context.status = 'retrieved'
                $context.reason = 'mock-json'
                $context.descriptionText = ($parts -join ' ')
            }
            else {
                $context.status = 'failed'
                $context.reason = 'mock-json-missing-fields'
            }
        }
        catch {
            $context.status = 'failed'
            $context.reason = 'mock-json-invalid'
        }

        return [PSCustomObject]$context
    }

    if ($BugId -notmatch '^[1-9][0-9]*$') {
        $context.status = 'failed'
        $context.reason = 'invalid-bug-id'
        return [PSCustomObject]$context
    }

    $resolvedContext = Resolve-AdoContext -Organization $Organization -Project $Project
    $context.organization = $resolvedContext.organization
    $context.project = $resolvedContext.project

    if ([string]::IsNullOrWhiteSpace($context.organization) -or [string]::IsNullOrWhiteSpace($context.project)) {
        $context.status = 'failed'
        $context.reason = 'missing-organization-or-project'
        return [PSCustomObject]$context
    }

    $token = $AccessToken
    if ([string]::IsNullOrWhiteSpace($token)) {
        $token = $env:AZURE_DEVOPS_EXT_PAT
        if (-not [string]::IsNullOrWhiteSpace($token)) {
            $context.authSource = 'env-azure-devops-ext-pat'
        }
    }
    if ([string]::IsNullOrWhiteSpace($token)) {
        $token = $env:SYSTEM_ACCESSTOKEN
        if (-not [string]::IsNullOrWhiteSpace($token)) {
            $context.authSource = 'env-system-accesstoken'
        }
    }
    if ([string]::IsNullOrWhiteSpace($token) -and $UseAzCliToken) {
        $token = Get-AdoCliAccessToken -Organization $context.organization
        if (-not [string]::IsNullOrWhiteSpace($token)) {
            $context.authSource = 'az-cli-token'
        }
    }
    if ([string]::IsNullOrWhiteSpace($token)) {
        $context.status = 'failed'
        $context.reason = 'missing-auth-token'
        return [PSCustomObject]$context
    }

    $headers = Get-AdoAuthHeader -Token $token
    $url = "https://dev.azure.com/$([System.Uri]::EscapeDataString($context.organization))/$([System.Uri]::EscapeDataString($context.project))/_apis/wit/workitems/${BugId}?`$expand=all&api-version=7.1-preview.3"

    $workItemResponse = Invoke-AdoWorkItemRequest -Url $url -Headers $headers
    if ($workItemResponse.status -ne 'ok' -or $null -eq $workItemResponse.workItem) {
        $context.status = 'failed'
        $context.reason = $workItemResponse.reason
        return [PSCustomObject]$context
    }

    try {
        $workItem = $workItemResponse.workItem
        $fields = $workItem.fields
        $parts = @(@(
            (Get-PlainText -Text (Get-FieldValue -FieldBag $fields -Name 'System.Title')),
            (Get-PlainText -Text (Get-FieldValue -FieldBag $fields -Name 'System.Description')),
            (Get-PlainText -Text (Get-FieldValue -FieldBag $fields -Name 'Microsoft.VSTS.TCM.ReproSteps')),
            (Get-PlainText -Text (Get-FieldValue -FieldBag $fields -Name 'System.ReproSteps'))
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

        if (@($parts).Count -gt 0) {
            $context.status = 'retrieved'
            $context.reason = 'ado-live'
            $context.descriptionText = ($parts -join ' ')
        }
        else {
            $context.status = 'failed'
            $context.reason = 'ado-response-missing-fields'
        }
    }

    catch {
        $context.status = 'failed'
        $context.reason = 'ado-request-failed'
    }

    return [PSCustomObject]$context
}

$retrievalContext = [PSCustomObject]@{
    status = 'not-attempted'
    reason = ''
    organization = ''
    project = ''
    authSource = ''
    isTransient = $false
}

if (-not [string]::IsNullOrWhiteSpace($WorkItemUrl)) {
    $cliIntake = Invoke-EiAdoCliIntakeSkill -WorkItemUrl $WorkItemUrl -Organization $Organization -Project $Project -CliWorkItemJson $AdoWorkItemJson
    if ($cliIntake.status -eq 'retrieved') {
        if ([string]::IsNullOrWhiteSpace($BugId)) { $BugId = $cliIntake.workItemId }
        if ([string]::IsNullOrWhiteSpace($Organization)) { $Organization = $cliIntake.organization }
        if ([string]::IsNullOrWhiteSpace($Project)) { $Project = $cliIntake.project }
        if ([string]::IsNullOrWhiteSpace($DescriptionText)) { $DescriptionText = $cliIntake.descriptionText }

        $retrievalContext = [PSCustomObject]@{
            status = 'retrieved'
            reason = if ([string]::IsNullOrWhiteSpace($cliIntake.reason)) { 'ado-cli-intake' } else { $cliIntake.reason }
            organization = $cliIntake.organization
            project = $cliIntake.project
            authSource = if ([string]::IsNullOrWhiteSpace($cliIntake.authSource)) { 'az-cli-intake-skill' } else { $cliIntake.authSource }
            isTransient = $false
        }
    }
    elseif ([string]::IsNullOrWhiteSpace($BugId) -and [string]::IsNullOrWhiteSpace($DescriptionText) -and @('missing-work-item-id-in-url', 'invalid-work-item-url', 'unsupported-work-item-url-host').Contains($cliIntake.reason)) {
        $blockedFromUrl = [PSCustomObject]@{
            status = 'blocked'
            bugContext = [PSCustomObject]@{
                bugId = $BugId
                workItemUrl = $WorkItemUrl
                descriptionText = $DescriptionText
                organization = $Organization
                project = $Project
                keywords = @($Keywords)
            }
            reproductionHints = @("Unable to resolve work item URL: $($cliIntake.reason).")
            affectedAreas = @()
            recentChanges = @()
            relatedTests = @()
            runtimeRequired = $false
            confidence = 0.0
        }

        if ($Json) { $blockedFromUrl | ConvertTo-Json -Depth 6 } else { $blockedFromUrl }
        exit 1
    }
    else {
        if ([string]::IsNullOrWhiteSpace($BugId) -and -not [string]::IsNullOrWhiteSpace($cliIntake.workItemId)) { $BugId = $cliIntake.workItemId }
        if ([string]::IsNullOrWhiteSpace($Organization) -and -not [string]::IsNullOrWhiteSpace($cliIntake.organization)) { $Organization = $cliIntake.organization }
        if ([string]::IsNullOrWhiteSpace($Project) -and -not [string]::IsNullOrWhiteSpace($cliIntake.project)) { $Project = $cliIntake.project }

        if ($retrievalContext.status -eq 'not-attempted') {
            $retrievalContext = [PSCustomObject]@{
                status = 'failed'
                reason = $cliIntake.reason
                organization = $cliIntake.organization
                project = $cliIntake.project
                authSource = $cliIntake.authSource
                isTransient = (Get-IsTransientRetrievalReason -Reason $cliIntake.reason)
            }
        }
    }
}

if ([string]::IsNullOrWhiteSpace($BugId) -and [string]::IsNullOrWhiteSpace($DescriptionText)) {
    $blocked = [PSCustomObject]@{
        status = 'blocked'
        bugContext = [PSCustomObject]@{
            bugId = $BugId
            workItemUrl = $WorkItemUrl
            descriptionText = $DescriptionText
            organization = $Organization
            project = $Project
            keywords = @($Keywords)
        }
        reproductionHints = @('Provide either a bug ID with retrievable ADO context or a bug description text.')
        affectedAreas = @()
        recentChanges = @()
        relatedTests = @()
        runtimeRequired = $false
        confidence = 0.0
    }

    if ($Json) { $blocked | ConvertTo-Json -Depth 6 } else { $blocked }
    exit 1
}

if ([string]::IsNullOrWhiteSpace($DescriptionText) -and -not [string]::IsNullOrWhiteSpace($BugId)) {
    $retrieval = Get-AdoBugContext -BugId $BugId -Organization $Organization -Project $Project -AccessToken $AccessToken -AdoWorkItemJson $AdoWorkItemJson -UseAzCliToken:$UseAzCliToken
    $retrievalContext = [PSCustomObject]@{
        status = $retrieval.status
        reason = $retrieval.reason
        organization = $retrieval.organization
        project = $retrieval.project
        authSource = $retrieval.authSource
        isTransient = (Get-IsTransientRetrievalReason -Reason $retrieval.reason)
    }

    if ($retrieval.status -eq 'retrieved' -and -not [string]::IsNullOrWhiteSpace($retrieval.descriptionText)) {
        $DescriptionText = $retrieval.descriptionText
    }
}

$dataPath = Join-Path $PSScriptRoot '..' '..' 'ei-vocabulary-navigator' 'data' 'vocabulary-map.json'
$data = Get-Content -LiteralPath $dataPath -Raw | ConvertFrom-Json -Depth 10

$searchText = (($DescriptionText + ' ' + ($Keywords -join ' ')).Trim()).ToLowerInvariant()
$matched = @(
    $data.terms | Where-Object {
        $entry = $_
        $searchText.Contains($entry.term.ToLowerInvariant()) -or
        @($entry.aliases | Where-Object { $searchText.Contains($_.ToLowerInvariant()) }).Count -gt 0
    }
)

$affectedAreas = [System.Collections.Generic.List[string]]::new()
$relatedTests = [System.Collections.Generic.List[string]]::new()
$reproductionHints = [System.Collections.Generic.List[string]]::new()
$confidenceSeed = 0.2
$runtimeRequired = $false

foreach ($entry in $matched) {
    foreach ($value in $entry.services) { if (-not $affectedAreas.Contains($value)) { $affectedAreas.Add($value) } }
    foreach ($value in $entry.commands) { if (-not $affectedAreas.Contains($value)) { $affectedAreas.Add($value) } }
    foreach ($value in $entry.relatedTests) { if (-not $relatedTests.Contains($value)) { $relatedTests.Add($value) } }
    $reproductionHints.Add("Inspect code paths related to '$($entry.term)'.")
    if ($entry.runtimeRequired) {
        $runtimeRequired = $true
    }
    $confidenceSeed += 0.18
}

if ($searchText.Contains('e3d') -or $searchText.Contains('everything3d') -or $searchText.Contains('launcheng')) {
    $runtimeRequired = $true
    $reproductionHints.Add('Validate against a local E3D runtime if available.')
    $confidenceSeed += 0.1
}

if ([string]::IsNullOrWhiteSpace($DescriptionText) -and -not [string]::IsNullOrWhiteSpace($BugId)) {
    $status = 'needs-manual-review'
    $reproductionHints.Add('ADO bug context could not be retrieved; supply copied description text for stronger evidence.')
    if (-not [string]::IsNullOrWhiteSpace($retrievalContext.reason)) {
        $reproductionHints.Add("ADO retrieval reason: $($retrievalContext.reason).")
    }
    if ($retrievalContext.isTransient) {
        $reproductionHints.Add('Treat this as transient; retry ADO retrieval before broader diagnosis changes.')
    }

    $confidenceCap = Get-RetrievalConfidenceCap -Reason $retrievalContext.reason
    $confidenceSeed = [Math]::Min($confidenceSeed, $confidenceCap)
}
elseif ($matched.Count -eq 0) {
    $status = 'needs-manual-review'
    $reproductionHints.Add('No vocabulary-backed EI terms were recognized from the supplied description.')
    $confidenceSeed = [Math]::Min($confidenceSeed, 0.3)
}
else {
    $status = 'ready'
}

$confidence = [Math]::Round([Math]::Min($confidenceSeed, 0.95), 2)

$result = [PSCustomObject]@{
    status = $status
    bugContext = [PSCustomObject]@{
        bugId = $BugId
        workItemUrl = $WorkItemUrl
        descriptionText = $DescriptionText
        organization = if (-not [string]::IsNullOrWhiteSpace($retrievalContext.organization)) { $retrievalContext.organization } else { $Organization }
        project = if (-not [string]::IsNullOrWhiteSpace($retrievalContext.project)) { $retrievalContext.project } else { $Project }
        keywords = @($Keywords)
        retrieval = $retrievalContext
    }
    reproductionHints = @($reproductionHints | Select-Object -Unique)
    affectedAreas = @($affectedAreas)
    recentChanges = @()
    relatedTests = @($relatedTests)
    runtimeRequired = $runtimeRequired
    confidence = $confidence
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
}
else {
    $result
}

if ($status -eq 'ready') {
    exit 0
}

exit 1
