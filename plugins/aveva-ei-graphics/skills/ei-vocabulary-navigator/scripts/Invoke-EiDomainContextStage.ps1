#!/usr/bin/env pwsh
<#
.SYNOPSIS
Run the `domain-context` lifecycle stage: detect relevant domain SKILL.md files for the story.

.DESCRIPTION
Reads the sealed ADO artifact and checks its story text against every entry in the domain skill
registry (`references/domain-skill-registry.json`). A domain is matched when any of its
detectionTerms appears in the story text (case-insensitive substring match). Each matched domain
contributes a `domainSkills` entry that carries the domain's Key Files as candidate evidence for
the scope resolver. Key files are never automatic scope.

No domain match is not a gate failure. The stage always completes unless the ADO artifact is
absent or the artifact write fails.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details (Details.Payload holds the artifact).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StateDir,
    [string]$RegistryPath = '',
    [string]$StageId = 'domain-context',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stateScripts = Join-Path $PSScriptRoot '..' '..' 'ei-workflow-state' 'scripts'
. (Join-Path $stateScripts 'helpers' 'EiWorkflowState.ps1')

$result = New-EiResult
$result = Set-EiDetail -Result $result -Name 'StateDir' -Value $StateDir
$result = Set-EiDetail -Result $result -Name 'StageId' -Value $StageId

$stagePath = Join-Path $stateScripts 'Set-EiWorkflowStage.ps1'
$writePath = Join-Path $stateScripts 'Write-EiWorkflowArtifact.ps1'
$readPath  = Join-Path $stateScripts 'Read-EiWorkflowArtifact.ps1'

if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $PSScriptRoot '..' 'references' 'domain-skill-registry.json'
}

$domainSkillReaderPath = Join-Path $PSScriptRoot 'helpers' 'Read-EiDomainSkillContext.ps1'

function Block-EiDomainContextStage {
    param(
        [Parameter(Mandatory)][psobject]$Result,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Remediation
    )

    $blocked = & $stagePath -StateDir $StateDir -StageId $StageId -Action block `
        -BlockCode $Code -BlockMessage $Message -Remediation $Remediation -Json | ConvertFrom-Json

    $updated = Add-EiError -Result $Result -Code $Code -Message $Message
    if ($blocked.Status -ne 'Valid') {
        $updated = Add-EiWarning -Result $updated -Message "The stage could not be recorded as blocked: $(@($blocked.Errors) -join '; ')"
    }

    Set-EiDetail -Result $updated -Name 'StageStatus' -Value 'blocked'
}

if (-not (Test-Path -LiteralPath $StateDir -PathType Container)) {
    $result = Add-EiError -Result $result -Code 'EIVN-STATE-MISSING' -Message "State directory was not found at '$StateDir'."
    Exit-EiResult -Result $result -Json:$Json
}

$statePayload = & $readPath -StateDir $StateDir -Name 'workflow-state' -Json | ConvertFrom-Json
if ($statePayload.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIVN-STATE-UNREADABLE' -Message "Workflow state could not be read from '$StateDir': $(@($statePayload.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$storyId = $statePayload.Details.Payload.storyId
$result = Set-EiDetail -Result $result -Name 'StoryId' -Value $storyId

# The story text is read from the sealed ado artifact so detection is always against the real story.
$adoArtifact = & $readPath -StateDir $StateDir -Name 'ado' -Json | ConvertFrom-Json
if ($adoArtifact.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIVN-ADO-UNREADABLE' -Message "The ado artifact could not be read, so there is no story to detect domains against: $(@($adoArtifact.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$started = & $stagePath -StateDir $StateDir -StageId $StageId -Action start -Json | ConvertFrom-Json
if ($started.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIVN-STAGE-NOT-STARTED' -Message "Stage '$StageId' could not be started: $(@($started.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

# ── Domain skill detection ────────────────────────────────────────────────────
# Match story text against registered domain SKILL.md detection terms. No match is not a failure.
$domainSkills = [System.Collections.Generic.List[object]]::new()
$storySummary     = [string]$adoArtifact.Details.Payload.summary
$storyDescription = [string]$adoArtifact.Details.Payload.description
$storySearchText  = (($storySummary + ' ' + $storyDescription).Trim())

if (Test-Path -LiteralPath $RegistryPath) {
    try {
        $registry = Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json
        $pluginRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path

        foreach ($domain in @($registry.domains)) {
            $matched = $false
            foreach ($term in @($domain.detectionTerms)) {
                if ($storySearchText.IndexOf([string]$term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $matched = $true
                    break
                }
            }
            if (-not $matched) { continue }

            $domainSkillPathRaw = [string]$domain.skillPath
            $skillAbsPath = if ([System.IO.Path]::IsPathRooted($domainSkillPathRaw)) {
                $domainSkillPathRaw
            } else {
                Join-Path $pluginRoot $domainSkillPathRaw
            }
            try {
                $ctx = & $domainSkillReaderPath `
                    -SkillPath $skillAbsPath `
                    -DomainId ([string]$domain.id) `
                    -DisplayName ([string]$domain.displayName)
                $domainSkills.Add($ctx)
            }
            catch {
                $result = Add-EiWarning -Result $result `
                    -Message "Could not load domain skill '$($domain.id)' from '$skillAbsPath': $($_.Exception.Message)"
            }
        }
    }
    catch {
        $result = Add-EiWarning -Result $result `
            -Message "Domain skill registry could not be parsed from '$RegistryPath': $($_.Exception.Message)"
    }
}
else {
    $result = Add-EiWarning -Result $result `
        -Message "Domain skill registry was not found at '$RegistryPath'; no domain skill context will be injected."
}

$result = Set-EiDetail -Result $result -Name 'DetectedDomains' -Value @($domainSkills | ForEach-Object { $_.domainId })

$artifact = [ordered]@{
    schemaVersion = $script:EiStateSchemaVersion
    source        = 'ei-domain-skill-registry'
    storyId       = $storyId
    generatedAt   = Get-EiUtcTimestamp
    domainSkills  = @($domainSkills)
}

$written = & $writePath -StateDir $StateDir -Name 'domain-context' -Content ($artifact | ConvertTo-Json -Depth 10) -Json | ConvertFrom-Json
if ($written.Status -ne 'Valid') {
    $result = Block-EiDomainContextStage -Result $result -Code 'EIVN-ARTIFACT-UNWRITABLE' `
        -Message "The domain-context artifact could not be persisted: $(@($written.Errors) -join '; ')" `
        -Remediation 'Fix the reported schema or state-directory problem and re-run the domain-context stage.'
    Exit-EiResult -Result $result -Json:$Json
}

# The gate passes on evidence, not on intent: the persisted artifact has to read back and validate.
$readBack = & $readPath -StateDir $StateDir -Name 'domain-context' -Json | ConvertFrom-Json
if ($readBack.Status -ne 'Valid') {
    $result = Block-EiDomainContextStage -Result $result -Code 'EIVN-ARTIFACT-ABSENT' `
        -Message "The domain-context artifact did not read back after being written: $(@($readBack.Errors) -join '; ')" `
        -Remediation 'Inspect the state directory for a truncated or hand-edited domain-context.json and re-run the domain-context stage.'
    Exit-EiResult -Result $result -Json:$Json
}

$completed = & $stagePath -StateDir $StateDir -StageId $StageId -Action complete -GateResult pass -Json | ConvertFrom-Json
if ($completed.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIVN-STAGE-NOT-COMPLETED' -Message "Stage '$StageId' could not be completed: $(@($completed.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'StageStatus' -Value 'complete'
$result = Set-EiDetail -Result $result -Name 'GateResult' -Value 'pass'
$result = Set-EiDetail -Result $result -Name 'WorkflowStatus' -Value $completed.Details.WorkflowStatus
$result = Set-EiDetail -Result $result -Name 'Path' -Value $written.Details.Path
$result = Set-EiDetail -Result $result -Name 'Payload' -Value $readBack.Details.Payload

Exit-EiResult -Result $result -Json:$Json
