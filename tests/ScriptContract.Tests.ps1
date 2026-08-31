#Requires -Version 7.0
Set-StrictMode -Version Latest

# Discovery-time state. Pester needs -ForEach data before any BeforeAll block runs.
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$PluginsRoot = Join-Path $RepoRoot 'plugins'

# The ceilings live here, not in plan.md. A ceiling may be raised once, with the script, the old
# value, the new value and the reason recorded in that task's BUILD-LOG.md block. None has been
# raised.
$LineCeilings = @{
    'Write-EiArtifact'         = 120
    'Write-EiSessionEntry'     = 200
    'Export-EiSessionSummary'  = 180
    'Get-EiDomainSkillCatalog' = 120
    'Test-EiScopeDrift'        = 100
    'Convert-EiAdoIntake'      = 160
}

# Which task in plan.md owns each of our scripts.
$OwningTask = @{
    'Write-EiArtifact'         = 'T007'
    'Write-EiSessionEntry'     = 'T008'
    'Export-EiSessionSummary'  = 'T009'
    'Get-EiDomainSkillCatalog' = 'T010'
    'Test-EiScopeDrift'        = 'T011'
    'Convert-EiAdoIntake'      = 'T012'
}

# Copied from the old repository and never edited. Hardcoded, as the plan requires.
$CopiedScripts = @(
    'Invoke-EiAdoCliIntake.ps1'
    'EiWorkItemReference.ps1'
    'EiAdoTimestamp.ps1'
    'Invoke-EiLayerGuard.ps1'
)

$OurScripts = @($LineCeilings.Keys | ForEach-Object { "$_.ps1" } | Sort-Object)
$FoundNames = @(Get-ChildItem -LiteralPath $PluginsRoot -File -Recurse -Filter '*.ps1' |
        ForEach-Object { $_.Name } | Sort-Object)
$AllListed = @($OurScripts + $CopiedScripts | Sort-Object)

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:PluginsRoot = Join-Path $script:RepoRoot 'plugins'
    $script:PlanText = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'plan.md') -Raw
    $script:HashFile = Join-Path $script:RepoRoot 'tests' 'data' 'ported-file-hashes.json'

    $script:LineCeilings = @{
        'Write-EiArtifact'         = 120
        'Write-EiSessionEntry'     = 200
        'Export-EiSessionSummary'  = 180
        'Get-EiDomainSkillCatalog' = 120
        'Test-EiScopeDrift'        = 100
        'Convert-EiAdoIntake'      = 160
    }
    $script:OwningTask = @{
        'Write-EiArtifact'         = 'T007'
        'Write-EiSessionEntry'     = 'T008'
        'Export-EiSessionSummary'  = 'T009'
        'Get-EiDomainSkillCatalog' = 'T010'
        'Test-EiScopeDrift'        = 'T011'
        'Convert-EiAdoIntake'      = 'T012'
    }
    $script:CopiedScripts = @(
        'Invoke-EiAdoCliIntake.ps1'
        'EiWorkItemReference.ps1'
        'EiAdoTimestamp.ps1'
        'Invoke-EiLayerGuard.ps1'
    )
    $script:OurScripts = @($script:LineCeilings.Keys | ForEach-Object { "$_.ps1" } | Sort-Object)

    function Resolve-Script {
        param([Parameter(Mandatory)] [string] $Name)
        $found = @(Get-ChildItem -LiteralPath $script:PluginsRoot -File -Recurse -Filter $Name)
        if ($found.Count -eq 0) { throw "$Name is listed in a set but is not on disk under plugins/." }
        $found[0].FullName
    }

    function Get-RosterFromPlan {
        <#
        .SYNOPSIS
            Reads the parameter roster for one task out of plan.md.
        .DESCRIPTION
            Anchored on the '#### T0NN' heading, never on the marker text: two rosters say "exactly
            these 7", so neither the marker nor the count identifies a task on its own. The roster
            may span several bullets below the marker, as T008's does, so reading continues to the
            end of the roster block rather than to the end of the marker line.
        #>
        param([Parameter(Mandatory)] [string] $PlanText, [Parameter(Mandatory)] [string] $TaskId)

        $section = [regex]::Match($PlanText, "(?ms)^#### $TaskId\b.*?(?=^#### T\d{3}\b|\z)")
        if (-not $section.Success) {
            throw "plan.md has no '#### $TaskId' heading. The roster parser cannot work without it."
        }

        $marker = [regex]::Match($section.Value, '(?ms)\*\*Parameters[^*]*exactly these \d+[^*]*\*\*')
        if (-not $marker.Success) {
            throw "The '#### $TaskId' section of plan.md has no 'Parameters, exactly these N' marker."
        }

        $roster = [System.Collections.Generic.List[string]]::new()
        $started = $false
        foreach ($line in (($section.Value.Substring($marker.Index)) -split '\r?\n')) {
            $trimmed = $line.Trim()
            if ($trimmed -match '`-[A-Za-z]') { $roster.Add($trimmed); $started = $true; continue }
            if (-not $started) { continue }
            if ($trimmed -eq '' -or $trimmed -match '^\*\*') { continue }
            break
        }

        $names = @(
            [regex]::Matches(($roster -join ' '), '`-([A-Za-z][A-Za-z0-9]*)`') |
                ForEach-Object { $_.Groups[1].Value } |
                Sort-Object -Unique
        )
        if ($names.Count -eq 0) { throw "No parameter names were found in the roster for $TaskId." }
        , $names
    }
}

Describe 'The roster parser' -Tag 'Unit' {

    It 'recovers T008 exactly, whose 21 names span three bullets' {
        $expected = @(
            'Action', 'BugPatternMatched', 'DomainSkillUsed', 'DurationMs', 'Finalize',
            'FilesModified', 'FilesRead', 'Help', 'HumanInput', 'HumanInteractions', 'Json',
            'Outcome', 'Phase', 'Reasoning', 'Root', 'ScriptOutput', 'SessionOutcome', 'StoryId',
            'TestsPassed', 'TestsRun', 'TokensUsed'
        ) | Sort-Object
        $actual = Get-RosterFromPlan -PlanText $script:PlanText -TaskId 'T008'
        $actual.Count | Should -Be 21
        ($actual -join ',') | Should -Be ($expected -join ',')
    }

    It 'recovers T012 exactly, one of the two rosters that say seven' {
        $expected = @('Help', 'IntakeJson', 'Json', 'Root', 'SkipAttachmentDownload', 'StoryId', 'Summary') | Sort-Object
        $actual = Get-RosterFromPlan -PlanText $script:PlanText -TaskId 'T012'
        $actual.Count | Should -Be 7
        ($actual -join ',') | Should -Be ($expected -join ',')
    }

    It 'tells T007 and T012 apart, although both rosters say seven' {
        $seven = Get-RosterFromPlan -PlanText $script:PlanText -TaskId 'T007'
        $twelve = Get-RosterFromPlan -PlanText $script:PlanText -TaskId 'T012'
        ($seven -join ',') | Should -Not -Be ($twelve -join ',')
        $seven | Should -Contain 'ArtifactType'
        $twelve | Should -Contain 'IntakeJson'
    }

    It 'fails loudly when the task heading is missing' {
        { Get-RosterFromPlan -PlanText '# nothing here' -TaskId 'T007' } | Should -Throw '*T007*heading*'
    }

    It 'fails loudly when the section has no roster' {
        { Get-RosterFromPlan -PlanText "#### T007 - a task`n`nSome words, but no roster." -TaskId 'T007' } |
            Should -Throw '*marker*'
    }
}

Describe 'Script contract' -Tag 'Unit' {

    Context 'every script under plugins falls in exactly one set' {
        It 'found scripts to check' -TestCases @(@{ Count = $FoundNames.Count }) {
            $Count | Should -BeGreaterThan 0
        }

        It '<_> is in exactly one set' -ForEach $FoundNames {
            # A script in neither set is an error, not a skip. Otherwise it slips past both
            # contracts and nobody notices.
            $inOurs = $script:OurScripts -contains $_
            $inCopied = $script:CopiedScripts -contains $_
            ($inOurs -or $inCopied) | Should -BeTrue -Because "$_ belongs to neither set"
            ($inOurs -and $inCopied) | Should -BeFalse -Because "$_ is in both sets"
        }

        It '<_> is listed in a set and exists on disk' -ForEach $AllListed {
            # The other direction of the same rule. Catches a rename or a deletion.
            { Resolve-Script -Name $_ } | Should -Not -Throw
        }

        It 'the total count is 12 or fewer, and is 10 today' -TestCases @(@{ Count = $FoundNames.Count }) {
            $Count | Should -BeLessOrEqual 12
            $Count | Should -Be 10
        }
    }

    Context 'our six scripts' {
        It '<_> follows the full contract' -ForEach $OurScripts {
            $raw = Get-Content -LiteralPath (Resolve-Script -Name $_) -Raw
            $raw | Should -Match '(?m)^#Requires -Version 7\.0\s*$'
            $raw | Should -Match 'Set-StrictMode -Version Latest'
            $raw | Should -Match "\`$ErrorActionPreference = 'Stop'"
            $raw | Should -Match '\[switch\]\s*\$Help'
            $raw | Should -Match '(?m)^if \(\$Help\)'
            $raw | Should -Not -Match 'Read-Host'
            $raw | Should -Not -Match '(?m)^\s*Pause\b'
        }

        It '<_> is within its line ceiling' -ForEach $OurScripts {
            $name = $_ -replace '\.ps1$', ''
            @(Get-Content -LiteralPath (Resolve-Script -Name $_)).Count |
                Should -BeLessOrEqual $script:LineCeilings[$name]
        }

        It '<_> declares exactly the parameters its task lists' -ForEach $OurScripts {
            $name = $_ -replace '\.ps1$', ''
            $expected = Get-RosterFromPlan -PlanText $script:PlanText -TaskId $script:OwningTask[$name]

            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Resolve-Script -Name $_), [ref]$null, [ref]$null)
            $declared = @($ast.ParamBlock.Parameters |
                    ForEach-Object { $_.Name.VariablePath.UserPath } | Sort-Object -Unique)

            ($declared -join ',') | Should -Be (($expected | Sort-Object) -join ',')
        }
    }

    Context 'the four copied scripts get the reduced contract' {
        It '<_> has Set-StrictMode and prompts for nothing' -ForEach $CopiedScripts {
            $raw = Get-Content -LiteralPath (Resolve-Script -Name $_) -Raw
            $raw | Should -Match 'Set-StrictMode'
            $raw | Should -Not -Match 'Read-Host'
            $raw | Should -Not -Match '(?m)^\s*Pause\b'
        }

        It '<_> has no -Help switch, and that must not be fixed' -ForEach $CopiedScripts {
            # Stated as a test so nobody edits a copied script to match our contract.
            $raw = Get-Content -LiteralPath (Resolve-Script -Name $_) -Raw
            $raw | Should -Not -Match '\[switch\]\s*\$Help'
        }
    }

    Context 'the recorded hashes' {
        It 'holds exactly 6 entries, and the expected file list' {
            # A bare count that disagrees with its own contents is how this check rots.
            $names = @((Get-Content -LiteralPath $script:HashFile -Raw | ConvertFrom-Json).files.PSObject.Properties.Name)
            $names.Count | Should -Be 6

            $expected = @(
                'plugins/demo-ei-graphics/skills/ei-graphics-core/schemas/ado.schema.json'
                'plugins/demo-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/Invoke-EiAdoCliIntake.ps1'
                'plugins/demo-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/helpers/EiWorkItemReference.ps1'
                'plugins/demo-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/helpers/EiAdoTimestamp.ps1'
                'plugins/demo-ei-graphics/skills/ei-layer-guard/SKILL.md'
                'plugins/demo-ei-graphics/skills/ei-layer-guard/scripts/Invoke-EiLayerGuard.ps1'
            )
            (($names | Sort-Object) -join "`n") | Should -Be (($expected | Sort-Object) -join "`n")
        }

        It 'every recorded file still matches its hash' {
            $record = Get-Content -LiteralPath $script:HashFile -Raw | ConvertFrom-Json
            foreach ($property in $record.files.PSObject.Properties) {
                $path = Join-Path $script:RepoRoot $property.Name
                Test-Path -LiteralPath $path | Should -BeTrue -Because "$($property.Name) is recorded but missing"
                $actual = 'sha256:' + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
                $actual | Should -Be $property.Value -Because "$($property.Name) has changed since it was copied"
            }
        }
    }

    Context 'the registry is complete in both directions' {
        It 'every skill folder is either registered or on the allowlist' {
            $allow = @('ei-graphics-core', 'ei-azure-devops-cli-intake', 'ei-layer-guard')
            $pluginFolder = Join-Path $script:PluginsRoot 'demo-ei-graphics'
            $registryPath = Join-Path $pluginFolder 'skills' 'ei-graphics-core' 'references' 'domain-skill-registry.json'
            $registered = @((Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json).domains | ForEach-Object { $_.id })

            $folders = @(Get-ChildItem -LiteralPath (Join-Path $pluginFolder 'skills') -Directory |
                    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') })
            $folders.Count | Should -BeGreaterThan 0

            foreach ($folder in $folders) {
                ($registered -contains $folder.Name -or $allow -contains $folder.Name) |
                    Should -BeTrue -Because "$($folder.Name) is neither registered nor allowlisted"
            }
        }

        It 'every registered skillPath resolves to a file that exists' {
            $pluginFolder = Join-Path $script:PluginsRoot 'demo-ei-graphics'
            $registryPath = Join-Path $pluginFolder 'skills' 'ei-graphics-core' 'references' 'domain-skill-registry.json'
            foreach ($domain in @((Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json).domains)) {
                Test-Path -LiteralPath (Join-Path $pluginFolder $domain.skillPath) |
                    Should -BeTrue -Because "$($domain.skillPath) does not exist"
            }
        }
    }
}
