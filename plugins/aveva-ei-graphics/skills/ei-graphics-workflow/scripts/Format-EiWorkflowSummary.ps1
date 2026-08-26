#!/usr/bin/env pwsh
<#
.SYNOPSIS
Produce a human-readable summary of the current EI Graphics workflow state.

.DESCRIPTION
Reads the workflow state and available artifacts from the given state directory and
builds a structured markdown summary suitable for presenting to a team member.

The summary follows this structure:
  Story → Understanding → Discussion → Relevant Area → Proposed Scope → Validation → Next Step

Internal implementation terminology (phase labels, artifact names, gate codes) is kept
out of the primary output. Use -Technical to append a diagnostic section for debugging.

.PARAMETER StateDir
The workflow state directory, e.g. .copilottracking/ei-graphics/123456.

.PARAMETER Technical
Include a technical-detail section with artifact inventory, gate results, and block codes.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details.
Details.Summary holds the formatted markdown string.
Details.WorkflowStatus holds the machine-readable workflow status.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StateDir,
    [switch]$Technical,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stateScripts = Join-Path $PSScriptRoot '..' '..' 'ei-workflow-state' 'scripts'
. "$stateScripts/helpers/EiWorkflowState.ps1"

$result = New-EiResult
$result = Set-EiDetail -Result $result -Name 'StateDir' -Value $StateDir

if (-not (Test-Path -LiteralPath $StateDir -PathType Container)) {
    $result = Add-EiError -Result $result -Code 'EIWF-STATE-MISSING' -Message "State directory was not found at '$StateDir'."
    Exit-EiResult -Result $result -Json:$Json
}

$stateFile = Join-Path $StateDir 'workflow-state.json'
if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf)) {
    $result = Add-EiError -Result $result -Code 'EIWF-STATE-MISSING' -Message "workflow-state.json was not found in '$StateDir'."
    Exit-EiResult -Result $result -Json:$Json
}

$state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
$workflowStatus = [string]$state.status
$result = Set-EiDetail -Result $result -Name 'WorkflowStatus' -Value $workflowStatus

# ── Helper: try to read an artifact, return $null if absent ──────────────────
function TryReadArtifact {
    param([string]$Name)
    $path = Join-Path $StateDir "$Name.json"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
        catch { return $null }
    }
    return $null
}

# ── Read available artifacts ──────────────────────────────────────────────────
$adoArtifact       = TryReadArtifact 'ado'
$domainCtx         = TryReadArtifact 'domain-context'
$proposedScope     = TryReadArtifact 'proposed-scope'
$approvedScopeV1   = TryReadArtifact 'approved-scope.v1'
$workflowResultArt = TryReadArtifact 'workflow-result'

$analysisEvidence = $null
$analysisPath = Join-Path $StateDir 'validation' 'scope-analysis.json'
if (Test-Path -LiteralPath $analysisPath -PathType Leaf) {
    try { $analysisEvidence = Get-Content -LiteralPath $analysisPath -Raw | ConvertFrom-Json }
    catch { }
}

# ── Build summary sections ────────────────────────────────────────────────────
$sb = [System.Text.StringBuilder]::new()

# ── Section: Story ────────────────────────────────────────────────────────────
[void]$sb.AppendLine('## Story')
if ($null -ne $adoArtifact) {
    $storyRef = [string]$adoArtifact.storyRef
    $summary  = [string]$adoArtifact.summary
    $storyId  = [string]$state.storyId

    if ($storyRef -match 'http') {
        [void]$sb.AppendLine("**[Story $storyId]($storyRef)** — $summary")
    } else {
        [void]$sb.AppendLine("**Story $storyId** — $summary")
    }
} else {
    [void]$sb.AppendLine("Story **$($state.storyId)** — intake not yet complete.")
}
[void]$sb.AppendLine()

# ── Section: Understanding ────────────────────────────────────────────────────
[void]$sb.AppendLine('## Understanding')
if ($null -ne $adoArtifact -and -not [string]::IsNullOrWhiteSpace([string]$adoArtifact.description)) {
    $description = ([string]$adoArtifact.description).Trim()
    # Truncate very long descriptions to keep the summary readable.
    if ($description.Length -gt 500) {
        $description = $description.Substring(0, 497) + '...'
    }
    [void]$sb.AppendLine($description)
} elseif ($null -ne $proposedScope) {
    [void]$sb.AppendLine($proposedScope.rationale)
} else {
    [void]$sb.AppendLine('Story intake is pending.')
}
[void]$sb.AppendLine()

# ── Section: Discussion ────────────────────────────────────────────────────────
# A later comment routinely supersedes the written story, so the thread travels with every summary
# rather than being read once at the domain checkpoint and dropped before the approval prompt.
[void]$sb.AppendLine('## Discussion')
if ($null -eq $adoArtifact) {
    [void]$sb.AppendLine('Story intake is pending.')
}
else {
    $commentStatus = 'skipped'
    $commentReason = 'not-recorded'
    if ($null -ne $adoArtifact.PSObject.Properties['commentRetrieval']) {
        $commentStatus = [string]$adoArtifact.commentRetrieval.status
        $commentReason = [string]$adoArtifact.commentRetrieval.reason
    }

    $comments = @()
    if ($null -ne $adoArtifact.PSObject.Properties['comments']) {
        $comments = @($adoArtifact.comments)
    }

    if ($commentStatus -ne 'retrieved') {
        # An unread thread is not an empty one, and the difference decides whether the reader can
        # trust this summary as the whole story.
        [void]$sb.AppendLine("The discussion thread could not be read ($commentReason), so any clarification posted in comments is **not** reflected in this summary.")
    }
    elseif ($comments.Count -eq 0) {
        [void]$sb.AppendLine('No comments on this work item.')
    }
    else {
        $shown = if ($comments.Count -gt 5) { $comments[-5..-1] } else { $comments }
        if ($comments.Count -gt $shown.Count) {
            [void]$sb.AppendLine("Showing the $($shown.Count) most recent of $($comments.Count) comments.")
            [void]$sb.AppendLine()
        }
        foreach ($comment in $shown) {
            $author = [string]$comment.author
            if ([string]::IsNullOrWhiteSpace($author)) { $author = 'Unknown' }

            # Reading the artifact back turns the sealed ISO string into a DateTime, whose default
            # string cast is culture-dependent; format explicitly rather than trusting the cast.
            $rawDate = $comment.createdDate
            $when = if ($rawDate -is [datetime]) {
                ([datetime]$rawDate).ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
            }
            elseif ([string]$rawDate -match '^(\d{4}-\d{2}-\d{2})') { $Matches[1] }
            else { '' }

            $text = ([string]$comment.text).Trim()
            if ($text.Length -gt 240) { $text = $text.Substring(0, 237) + '...' }
            if ([string]::IsNullOrWhiteSpace($text)) { $text = '(no text)' }

            $prefix = if ($when) { "**$author** ($when)" } else { "**$author**" }
            [void]$sb.AppendLine("- $prefix — $text")
        }
    }
}
[void]$sb.AppendLine()

# ── Section: Relevant Area ────────────────────────────────────────────────────
[void]$sb.AppendLine('## Relevant Area')
if ($null -ne $domainCtx) {
    $skills = @($domainCtx.domainSkills)
    if ($skills.Count -gt 0) {
        foreach ($skill in $skills) {
            [void]$sb.AppendLine("**$($skill.displayName)**")
            if (-not [string]::IsNullOrWhiteSpace([string]$skill.summary)) {
                [void]$sb.AppendLine($skill.summary)
            }
            $keyFiles = @($skill.keyFiles)
            if ($keyFiles.Count -gt 0) {
                [void]$sb.AppendLine()
                [void]$sb.AppendLine('Key files in this area (candidate evidence, not automatic scope):')
                foreach ($kf in $keyFiles) {
                    $filePart = [string]$kf.file
                    $purposePart = [string]$kf.purpose
                    [void]$sb.AppendLine("- ``$filePart`` — $purposePart")
                }
            }
        }
    } else {
        [void]$sb.AppendLine('No specific domain area was detected from the story content. The scope resolver will work from repository evidence alone.')
    }
} else {
    [void]$sb.AppendLine('Domain analysis is pending.')
}
[void]$sb.AppendLine()

# ── Section: Proposed Scope ───────────────────────────────────────────────────
[void]$sb.AppendLine('## Proposed Scope')
if ($null -ne $approvedScopeV1) {
    # The scope was approved — show what was sealed.
    $scope = $approvedScopeV1.scope
    [void]$sb.AppendLine('The following scope was reviewed and **approved**.')
    [void]$sb.AppendLine()
    $files = @($scope.proposedFiles)
    if ($files.Count -gt 0) {
        [void]$sb.AppendLine('**Files authorised for change:**')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('| File | Change |')
        [void]$sb.AppendLine('|------|--------|')
        foreach ($f in $files) {
            $intent = [string]$f.changeIntent
            [void]$sb.AppendLine("| ``$($f.path)`` | $intent |")
        }
        [void]$sb.AppendLine()
    }
    $tests = @($scope.relatedTests)
    if ($tests.Count -gt 0) {
        [void]$sb.AppendLine('**Tests covering this change:**')
        foreach ($t in $tests) {
            [void]$sb.AppendLine("- ``$($t.target)``")
        }
        [void]$sb.AppendLine()
    }
    $excluded = @($scope.excluded)
    if ($excluded.Count -gt 0) {
        [void]$sb.AppendLine('**Explicitly excluded:**')
        foreach ($ex in $excluded) {
            [void]$sb.AppendLine("- ``$($ex.path)`` — $($ex.reason)")
        }
        [void]$sb.AppendLine()
    }
} elseif ($null -ne $proposedScope) {
    $files = @($proposedScope.proposedFiles)
    $tests = @($proposedScope.relatedTests)
    $excluded = @($proposedScope.excluded)
    $unresolved = @($proposedScope.unresolved)

    if ($files.Count -gt 0) {
        [void]$sb.AppendLine('**Files proposed for change:**')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('| File | Change |')
        [void]$sb.AppendLine('|------|--------|')
        foreach ($f in $files) {
            $intent = [string]$f.changeIntent
            [void]$sb.AppendLine("| ``$($f.path)`` | $intent |")
        }
        [void]$sb.AppendLine()
    } else {
        [void]$sb.AppendLine('No files have been proposed yet.')
        [void]$sb.AppendLine()
    }

    if ($tests.Count -gt 0) {
        [void]$sb.AppendLine('**Tests identified:**')
        foreach ($t in $tests) {
            [void]$sb.AppendLine("- ``$($t.target)``")
        }
        [void]$sb.AppendLine()
    }

    if ($excluded.Count -gt 0) {
        [void]$sb.AppendLine('**Excluded from scope:**')
        foreach ($ex in $excluded) {
            [void]$sb.AppendLine("- ``$($ex.path)`` — $($ex.reason)")
        }
        [void]$sb.AppendLine()
    }

    if ($unresolved.Count -gt 0) {
        [void]$sb.AppendLine('**Items needing clarification:**')
        foreach ($ur in $unresolved) {
            [void]$sb.AppendLine("- $($ur.message)")
        }
        [void]$sb.AppendLine()
    }
} else {
    [void]$sb.AppendLine('Scope analysis is pending.')
    [void]$sb.AppendLine()
}

# ── Section: Validation ───────────────────────────────────────────────────────
[void]$sb.AppendLine('## Validation')
$checksCompleted = [System.Collections.Generic.List[string]]::new()
$warnings        = [System.Collections.Generic.List[string]]::new()
$blocking        = [System.Collections.Generic.List[string]]::new()

foreach ($stage in @($state.stages)) {
    $stageId = [string]$stage.id
    $stageStatus = [string]$stage.status

    if ($stageStatus -eq 'complete' -and [string]$stage.gateResult -eq 'pass') {
        switch ($stageId) {
            'ado-intake'     { $checksCompleted.Add('Story context retrieved successfully.') }
            'domain-context' { $checksCompleted.Add('Domain area identified from story content.') }
            'proposed-scope' { $checksCompleted.Add('Scope analysis completed successfully.') }
            'scope-analysis' { $checksCompleted.Add('Scope is narrow enough to be reviewed. No blocking issues found.') }
            'scope-approval' { $checksCompleted.Add('Scope approved and recorded.') }
        }
    }

    if ($stageStatus -eq 'blocked') {
        $reason = [string]$stage.blockReason
        switch ($stageId) {
            'ado-intake'     { $blocking.Add("Story details could not be retrieved. $reason") }
            'domain-context' { $blocking.Add("Domain area could not be determined. $reason") }
            'proposed-scope' { $blocking.Add("Scope could not be resolved. $reason") }
            'scope-analysis' { $blocking.Add("Scope was not ready for review. $reason") }
            'scope-approval' { $blocking.Add("Scope was rejected. $reason") }
            default          { $blocking.Add("A check did not pass for '$stageId'. $reason") }
        }
    }
}

foreach ($block in @($state.blocks)) {
    $msg = [string]$block.message
    if ($blocking -notcontains $msg) {
        $blocking.Add($msg)
    }
}

if ($checksCompleted.Count -gt 0) {
    [void]$sb.AppendLine('**Completed checks:**')
    foreach ($check in $checksCompleted) {
        [void]$sb.AppendLine("- $check")
    }
    [void]$sb.AppendLine()
}

if ($warnings.Count -gt 0) {
    [void]$sb.AppendLine('**Warnings:**')
    foreach ($w in $warnings) {
        [void]$sb.AppendLine("- $w")
    }
    [void]$sb.AppendLine()
}

if ($null -ne $analysisEvidence) {
    $advisoryFindings = @(@($analysisEvidence.findings) | Where-Object { $_.severity -ne 'blocking' })
    if ($advisoryFindings.Count -gt 0) {
        [void]$sb.AppendLine('**Points for the reviewer to consider:**')
        foreach ($f in $advisoryFindings) {
            [void]$sb.AppendLine("- $($f.message)")
        }
        [void]$sb.AppendLine()
    }
}

if ($blocking.Count -gt 0) {
    [void]$sb.AppendLine('**Issues that need attention:**')
    foreach ($b in $blocking) {
        [void]$sb.AppendLine("- $b")
    }
    [void]$sb.AppendLine()
}

# ── Section: Review Required / Approval ──────────────────────────────────────
if ($workflowStatus -eq 'awaiting-approval') {
    [void]$sb.AppendLine('## Review Required')

    if ($null -ne $analysisEvidence) {
        $summary = [string]$analysisEvidence.summary
        if (-not [string]::IsNullOrWhiteSpace($summary)) {
            [void]$sb.AppendLine($summary)
            [void]$sb.AppendLine()
        }
    }

    [void]$sb.AppendLine('The proposed change is within the allowed boundaries and is ready for your decision.')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('**To approve:** confirm that the files listed in "Proposed Scope" are the right set for this story, then run the approve command.')
    [void]$sb.AppendLine('**To reject:** provide a reason so the scope can be revised and resubmitted.')
    [void]$sb.AppendLine()
}

# ── Section: Next Step ────────────────────────────────────────────────────────
[void]$sb.AppendLine('## Next Step')
$nextAction = if ($null -ne $workflowResultArt -and -not [string]::IsNullOrWhiteSpace([string]$workflowResultArt.nextAction)) {
    $workflowResultArt.nextAction
} else {
    switch ($workflowStatus) {
        'awaiting-approval' { 'Review the proposed scope above and approve or reject it.' }
        'blocked'           { 'Address the issues listed above, then re-run the affected step.' }
        'failed'            { 'A check failed and needs manual investigation. Review the issues above.' }
        'completed'         { 'The workflow completed successfully. The pull request is ready for code review.' }
        'in-progress'       { 'The workflow is running. Wait for the current step to finish.' }
        default             { 'No further action is needed at this time.' }
    }
}
[void]$sb.AppendLine($nextAction)
[void]$sb.AppendLine()

# ── Section: Technical details (opt-in) ──────────────────────────────────────
if ($Technical) {
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine('## Technical Details')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("**State directory:** ``$($state.stateDir)``")
    [void]$sb.AppendLine("**Workflow status:** ``$workflowStatus``")
    [void]$sb.AppendLine("**Current stage:** ``$($state.stage)``")
    [void]$sb.AppendLine()

    $gateRows = @($state.stages) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.gate) }
    if ($gateRows.Count -gt 0) {
        [void]$sb.AppendLine('**Gate results:**')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('| Stage | Gate | Result |')
        [void]$sb.AppendLine('|-------|------|--------|')
        foreach ($row in $gateRows) {
            $gr = if ([string]::IsNullOrWhiteSpace([string]$row.gateResult)) { 'not-run' } else { [string]$row.gateResult }
            [void]$sb.AppendLine("| ``$($row.id)`` | ``$($row.gate)`` | $gr |")
        }
        [void]$sb.AppendLine()
    }

    if (@($state.blocks).Count -gt 0) {
        [void]$sb.AppendLine('**Blocks:**')
        foreach ($b in @($state.blocks)) {
            [void]$sb.AppendLine("- ``$($b.code)`` — $($b.message)")
        }
        [void]$sb.AppendLine()
    }
}

$summaryText = $sb.ToString()
$result = Set-EiDetail -Result $result -Name 'Summary' -Value $summaryText

Exit-EiResult -Result $result -Json:$Json
