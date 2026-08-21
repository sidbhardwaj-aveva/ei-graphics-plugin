#!/usr/bin/env pwsh
# Copyright (c) AVEVA.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

Describe 'Test-EiGraphicsSpecSync' -Tag 'Unit' {

    BeforeAll {
        $script:ScriptPath = Join-Path $PSScriptRoot '..' '..' 'tools' 'Test-EiGraphicsSpecSync.ps1'
    }

    It 'passes when no EI plugin files changed' {
        $output = & $script:ScriptPath -ChangedPaths @(
            'README.md',
            'docs/commit-message-guidelines.md'
        ) *>&1

        if ($LASTEXITCODE -ne 0) { throw "Expected exit code 0, got $LASTEXITCODE" }
        if (($output -join "`n") -notmatch 'PASS: No changes detected') { throw 'Expected pass message for non-plugin changes' }
    }

    It 'fails when EI plugin files changed without spec updates' {
        $output = & $script:ScriptPath -ChangedPaths @(
            'plugins/aveva-ei-graphics/README.md',
            'plugins/aveva-ei-graphics/skills/ei-layer-guard/SKILL.md'
        ) *>&1

        if ($LASTEXITCODE -ne 1) { throw "Expected exit code 1, got $LASTEXITCODE" }
        if (($output -join "`n") -notmatch 'require at least one update') { throw 'Expected fail message when spec folder is unchanged' }
    }

    It 'passes when EI plugin and EI spec files both changed' {
        $output = & $script:ScriptPath -ChangedPaths @(
            'plugins/aveva-ei-graphics/README.md',
            'specs/002-ei-graphics-plugin-foundation/current-status.md'
        ) *>&1

        if ($LASTEXITCODE -ne 0) { throw "Expected exit code 0, got $LASTEXITCODE" }
        if (($output -join "`n") -notmatch 'matching spec change\(s\)') { throw 'Expected pass message when both plugin and spec changed' }
    }

    It 'normalizes Windows-style path separators' {
        $output = & $script:ScriptPath -ChangedPaths @(
            'plugins\\aveva-ei-graphics\\agents\\ei-graphics.agent.md',
            'specs\\002-ei-graphics-plugin-foundation\\progress-log.md'
        ) *>&1

        if ($LASTEXITCODE -ne 0) { throw "Expected exit code 0, got $LASTEXITCODE" }
        if (($output -join "`n") -notmatch 'matching spec change\(s\)') { throw 'Expected path normalization to keep policy passing' }
    }

    It 'returns usage error when neither ChangedPaths nor FromRef is supplied' {
        $output = & $script:ScriptPath *>&1

        if ($LASTEXITCODE -ne 2) { throw "Expected exit code 2, got $LASTEXITCODE" }
        if (($output -join "`n") -notmatch 'Provide either -ChangedPaths or -FromRef/-ToRef') { throw 'Expected usage error message' }
    }
}
