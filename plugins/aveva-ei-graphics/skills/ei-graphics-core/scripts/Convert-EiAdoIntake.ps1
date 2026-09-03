#Requires -Version 7.0
<#
.SYNOPSIS
    Turns the output of Invoke-EiAdoCliIntake.ps1 into the shape ado.schema.json wants.
.DESCRIPTION
    The intake script and the schema use different shapes. This script translates between them,
    and downloads the images attached to the work item unless told not to. Pipe the result into
    Write-EiArtifact.ps1 -ArtifactType ado.
#>[CmdletBinding()]
param(
    [string] $IntakeJson,
    [string] $StoryId,
    [string] $Summary,
    [string] $Root = '.',
    [switch] $SkipAttachmentDownload,
    [switch] $Json,
    [switch] $Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Help) { Get-Help -Detailed $PSCommandPath; exit 0 }

$invariant = [System.Globalization.CultureInfo]::InvariantCulture
function Write-Problem { param([string] $Message) [Console]::Error.WriteLine($Message) }

# The culture argument is not optional: in a format string ':' is the culture's time separator.
function Get-UtcTimestamp { (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', $invariant) }

function ConvertTo-IsoTimestamp {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', $invariant) }
    if ($Value -is [datetimeoffset]) { return $Value.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ', $invariant) }
    [string] $Value
}

function Get-OrNull {
    param($Owner, [string] $Name)
    if ($null -eq $Owner -or $Owner.PSObject.Properties.Name -notcontains $Name) { return $null }
    $value = $Owner.$Name
    if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) { return $null }
    $value
}

function Get-Attachment {
    # Downloads each attached image and reports only the ones that arrived.
    param($Entries, [string] $Folder)

    $token = ''
    try {
        $raw = & az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --output json 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) { $token = ($raw -join '' | ConvertFrom-Json).accessToken }
    } catch { $token = '' }
    if (-not $token) {
        Write-Problem 'No Azure DevOps token was available, so no attachment was downloaded. Run az login if you need the images.'
        return , @()
    }

    if (-not (Test-Path -LiteralPath $Folder)) { $null = New-Item -ItemType Directory -Path $Folder -Force }
    $saved = [System.Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($entry in @($Entries)) {
        $index++
        $url = $entry
        $source = 'unknown'
        if ($entry -isnot [string]) {
            $url = Get-OrNull -Owner $entry -Name 'url'
            $found = Get-OrNull -Owner $entry -Name 'source'
            if ($found) { $source = $found }
        }
        if (-not $url) { continue }
        $name = "image-$index.png"
        $query = [regex]::Match([string] $url, '[?&]fileName=([^&]+)')
        if ($query.Success) { $name = [System.Uri]::UnescapeDataString($query.Groups[1].Value) }
        # The index prefix stops two attachments with the same name colliding.
        $name = "$index-$name"
        $localPath = Join-Path $Folder $name
        try {
            Invoke-WebRequest -Uri $url -Headers @{ Authorization = "Bearer $token" } -OutFile $localPath -ErrorAction Stop
            $saved.Add([ordered]@{ url = [string] $url; localPath = $localPath; fileName = $name; source = $source })
        } catch {
            Write-Problem "Could not download the attachment $url. Carrying on without it. $($_.Exception.Message)"
        }
    }
    , $saved.ToArray()
}

if (-not $StoryId) { Write-Problem 'No -StoryId was given. Pass the story number this intake belongs to.'; exit 1 }
if (-not $IntakeJson) { Write-Problem 'No -IntakeJson was given. Pipe the output of Invoke-EiAdoCliIntake.ps1 into it.'; exit 1 }

try { $intake = $IntakeJson | ConvertFrom-Json }
catch { Write-Problem "The text passed to -IntakeJson is not valid JSON. $($_.Exception.Message)"; exit 1 }

$context = Get-OrNull -Owner $intake -Name 'workItemContext'
$workItemId = [string] (Get-OrNull -Owner $context -Name 'workItemId')
$status = [string] (Get-OrNull -Owner $intake -Name 'status')
$reason = [string] (Get-OrNull -Owner $intake -Name 'reason')

if ($status -ne 'retrieved') {
    Write-Problem "The intake for work item '$workItemId' did not retrieve the story. It reported status '$status', reason '$reason'. Only a clean retrieval becomes an artifact, so fix the intake and run it again."
    exit 1
}
if ($workItemId -notmatch '^[1-9][0-9]*$') {
    Write-Problem "The intake gave a work item id of '$workItemId'. It must be a positive whole number with no leading zero. Check the work item link, or the id you passed to the intake script."
    exit 1
}
$description = [string] (Get-OrNull -Owner $intake -Name 'descriptionText')
if (-not $description) {
    Write-Problem "Work item $workItemId has an empty description, so there is nothing to understand. Add a description to the work item, or supply the detail another way."
    exit 1
}

$artifact = [ordered]@{
    schemaVersion = '1.0.0'
    source        = 'ei-azure-devops-cli-intake'
    storyId       = $StoryId
    storyRef      = Get-OrNull -Owner $context -Name 'workItemUrl'
    summary       = $null
    description   = $description
    workItem      = [ordered]@{
        id           = $workItemId
        organization = [string] (Get-OrNull -Owner $context -Name 'organization')
        project      = [string] (Get-OrNull -Owner $context -Name 'project')
        url          = Get-OrNull -Owner $context -Name 'workItemUrl'
    }
    retrieval     = [ordered]@{
        status     = $status
        reason     = $reason
        authSource = [string] (Get-OrNull -Owner $context -Name 'authSource')
    }
    retrievedAt   = Get-UtcTimestamp
}
if ($Summary) { $artifact['summary'] = $Summary }
if (-not $SkipAttachmentDownload) {
    $folder = Join-Path (Resolve-Path -LiteralPath $Root).Path '.ei-session-logs' $StoryId 'attachments'
    $artifact['attachments'] = Get-Attachment -Entries (Get-OrNull -Owner $intake -Name 'attachmentUrls') -Folder $folder
}
$commentRetrieval = Get-OrNull -Owner $intake -Name 'commentRetrieval'
if ($commentRetrieval) {
    $artifact['commentRetrieval'] = [ordered]@{
        status = [string] $commentRetrieval.status
        reason = [string] $commentRetrieval.reason
    }
}
$comments = @(Get-OrNull -Owner $intake -Name 'comments')
if ($comments.Count -gt 0) {
    $artifact['comments'] = @($comments | ForEach-Object {
        [ordered]@{
            id          = [string] $_.id
            author      = [string] $_.author
            createdDate = ConvertTo-IsoTimestamp -Value $_.createdDate
            text        = [string] $_.text
        }
    })
}

if ($Json) { $artifact | ConvertTo-Json -Depth 20 } else { $artifact }
exit 0
