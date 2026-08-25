#!/usr/bin/env pwsh
<#
.SYNOPSIS
Run the `domain-context` lifecycle stage: inject domain SKILL.md context for the story.

.DESCRIPTION
Accepts a human-confirmed list of domain IDs (selected by the agent after presenting its
understanding of the story to the user). For each selected ID, looks up the domain in
`references/domain-skill-registry.json`, loads the corresponding SKILL.md via
Read-EiDomainSkillContext.ps1, and writes the domain-context artifact.

The stage blocks unless -HumanConfirmed is set. This enforces that the agent received explicit
user confirmation of the domain selection before the workflow advances to scope-candidate.

An empty -SelectedDomainIds list is allowed when the agent and user agree that no registered
domain applies: the artifact is written with an empty domainSkills array.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details (Details.Payload holds the artifact).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StateDir,
    [string[]]$SelectedDomainIds = @(),
    [string]$RegistryPath = '',
    [string]$StageId = 'domain-context',
    [switch]$HumanConfirmed,
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

# The ado artifact must exist before this stage may run; its content is not used for detection.
$adoArtifact = & $readPath -StateDir $StateDir -Name 'ado' -Json | ConvertFrom-Json
if ($adoArtifact.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIVN-ADO-UNREADABLE' -Message "The ado artifact could not be read, so there is no story to attach domain context to: $(@($adoArtifact.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$started = & $stagePath -StateDir $StateDir -StageId $StageId -Action start -Json | ConvertFrom-Json
if ($started.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIVN-STAGE-NOT-STARTED' -Message "Stage '$StageId' could not be started: $(@($started.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

# ── Require human confirmation ────────────────────────────────────────────────
# The agent must present its story understanding and domain selection to the user and receive
# explicit confirmation before this stage may write the domain-context artifact.
if (-not $HumanConfirmed) {
    $result = Block-EiDomainContextStage -Result $result `
        -Code 'EIVN-DOMAIN-NOT-CONFIRMED' `
        -Message 'Domain selection requires explicit human confirmation before the stage may proceed.' `
        -Remediation 'Present the agent understanding and domain selection to the user, then re-run with -HumanConfirmed after they confirm.'
    Exit-EiResult -Result $result -Json:$Json
}

# ── Load registry and resolve selected domain IDs ─────────────────────────────
$domainSkills = [System.Collections.Generic.List[object]]::new()
$normalizedIds = @($SelectedDomainIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$result = Set-EiDetail -Result $result -Name 'SelectedDomainIds' -Value $normalizedIds

if ($normalizedIds.Count -gt 0) {
    if (-not (Test-Path -LiteralPath $RegistryPath)) {
        $result = Block-EiDomainContextStage -Result $result `
            -Code 'EIVN-REGISTRY-MISSING' `
            -Message "Domain skill registry was not found at '$RegistryPath'." `
            -Remediation 'Ensure the registry file exists and re-run.'
        Exit-EiResult -Result $result -Json:$Json
    }

    $registry = $null
    try {
        $registry = Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json
    }
    catch {
        $result = Block-EiDomainContextStage -Result $result `
            -Code 'EIVN-REGISTRY-INVALID' `
            -Message "Domain skill registry at '$RegistryPath' is not valid JSON: $($_.Exception.Message)" `
            -Remediation 'Fix the registry JSON and re-run.'
        Exit-EiResult -Result $result -Json:$Json
    }

    $pluginRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path

    foreach ($selectedId in $normalizedIds) {
        $domain = @($registry.domains) | Where-Object { [string]$_.id -eq $selectedId } | Select-Object -First 1
        if ($null -eq $domain) {
            $registeredIds = @($registry.domains | ForEach-Object { $_.id }) -join ', '
            $result = Block-EiDomainContextStage -Result $result `
                -Code 'EIVN-DOMAIN-NOT-REGISTERED' `
                -Message "Domain '$selectedId' is not registered in the domain skill registry. Registered IDs: $registeredIds." `
                -Remediation "Select only domain IDs that exist in the registry and re-run."
            Exit-EiResult -Result $result -Json:$Json
        }

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
            $result = Block-EiDomainContextStage -Result $result `
                -Code 'EIVN-SKILL-UNREADABLE' `
                -Message "Could not load domain skill '$selectedId' from '$skillAbsPath': $($_.Exception.Message)" `
                -Remediation "Fix or restore the domain skill SKILL.md at '$skillAbsPath' and re-run."
            Exit-EiResult -Result $result -Json:$Json
        }
    }
}

$result = Set-EiDetail -Result $result -Name 'DetectedDomains' -Value @($domainSkills | ForEach-Object { $_.domainId })

$artifact = [ordered]@{
    schemaVersion     = $script:EiStateSchemaVersion
    source            = 'ei-domain-skill-registry'
    storyId           = $storyId
    generatedAt       = Get-EiUtcTimestamp
    domainSkills      = @($domainSkills)
    humanConfirmation = [ordered]@{ status = 'confirmed' }
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

$result = Set-EiDetail -Result $result -Name 'StageStatus'     -Value 'complete'
$result = Set-EiDetail -Result $result -Name 'GateResult'      -Value 'pass'
$result = Set-EiDetail -Result $result -Name 'WorkflowStatus'  -Value $completed.Details.WorkflowStatus
$result = Set-EiDetail -Result $result -Name 'HumanConfirmed'  -Value $true
$result = Set-EiDetail -Result $result -Name 'Path'            -Value $written.Details.Path
$result = Set-EiDetail -Result $result -Name 'Payload'         -Value $readBack.Details.Payload

Exit-EiResult -Result $result -Json:$Json
