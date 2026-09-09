#Requires -Version 7.0
<#
.SYNOPSIS
    Diagnose EI Graphics plugin setup readiness.
.DESCRIPTION
    Run a read-only health check on the plugin's dependencies, configuration, and artifacts.
    Checks: PowerShell runtime, Azure DevOps CLI & authentication, plugin file structure,
    skill registry & schemas, session artifacts, and git configuration.
    
    -Root names the target repository a story is worked in (defaults to the current directory):
    session artifacts and git configuration are checked there. The plugin's own files are always
    resolved from this script's install location, never from -Root, because the target repository
    does not contain a copy of the plugin.
    
    Returns status: pass | blocked | needs-manual-review
    Exit code: 0 if status is "pass", 1 if "blocked" or "needs-manual-review".
#>
[CmdletBinding()]
param(
    [string] $Root = '.',
    [switch] $Json,
    [switch] $Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Help) { Get-Help -Detailed $PSCommandPath; exit 0 }

# ============================================================================
# Helpers
# ============================================================================

function Write-Problem { param([string] $Message) [Console]::Error.WriteLine($Message) }

function New-Finding {
    param(
        [Parameter(Mandatory)] [string] $Code,
        [Parameter(Mandatory)] [string] $Severity, # Block | ManualReview | Info
        [string] $Path,
        [Parameter(Mandatory)] [string] $Message
    )
    [pscustomobject]@{
        Code     = $Code
        Severity = $Severity
        Path     = $Path
        Message  = $Message
    }
}

function New-CheckDetail {
    param(
        [Parameter(Mandatory)] [string] $CheckName,
        [Parameter(Mandatory)] [string] $Status, # ready | blocked | needs-manual-review
        [hashtable] $Details = @{}
    )
    $obj = [pscustomobject]@{ Status = $Status }
    foreach ($k in $Details.Keys) {
        $obj | Add-Member -NotePropertyName $k -NotePropertyValue $Details[$k]
    }
    [pscustomobject]@{
        Name = $CheckName
        Check = $obj
    }
}

# ============================================================================
# Check 1: PowerShell Runtime (EIGD001)
# ============================================================================

function Test-PowerShellRuntime {
    $findings = @()
    $details = @{}
    
    $version = $PSVersionTable.PSVersion
    $details.Version = "$($version.Major).$($version.Minor).$($version.Patch)"
    $details.VersionOK = $version.Major -ge 7
    
    if ($version.Major -lt 7) {
        $findings += New-Finding -Code 'EIGD001' -Severity 'Block' `
            -Path 'PowerShell' `
            -Message "PowerShell $($details.Version) is too old. Required: 7.0 or later. Install PowerShell 7+ from https://github.com/PowerShell/PowerShell/releases"
    }
    
    # Test strict mode
    try {
        & { Set-StrictMode -Version Latest; $null = 1 }
        $details.StrictModeWorks = $true
    } catch {
        $findings += New-Finding -Code 'EIGD001' -Severity 'Block' `
            -Path 'PowerShell' `
            -Message "StrictMode Latest cannot be enabled: $($_.Exception.Message)"
        $details.StrictModeWorks = $false
    }
    
    , @($findings, $details)
}

# ============================================================================
# Check 2: Azure DevOps CLI & Authentication (EIGD002)
# ============================================================================

function Test-AzureDevOpsCli {
    $findings = @()
    $details = @{
        AuthStatus = 'unknown'
        CliVersion = $null
        Organization = $null
    }
    
    # Check if the azure-devops extension is installed. `az devops -v` is not a valid command
    # (devops is an extension command group that requires a subcommand); the extension's own
    # metadata is the correct source for "is it installed".
    $azVersion = $null
    try {
        $output = az extension show --name azure-devops --output json 2>&1
        if ($LASTEXITCODE -eq 0) {
            $extensionObj = $output -join '' | ConvertFrom-Json -ErrorAction SilentlyContinue
            $azVersion = $extensionObj.version
            $details.CliVersion = $azVersion
        } else {
            $findings += New-Finding -Code 'EIGD002' -Severity 'Block' `
                -Path 'az devops' `
                -Message "Azure DevOps CLI extension is not installed. Install with: az extension add --name azure-devops"
            $details.AuthStatus = 'blocked'
        }
    } catch {
        $findings += New-Finding -Code 'EIGD002' -Severity 'Block' `
            -Path 'az devops' `
            -Message "Azure DevOps CLI is not installed or not in PATH. Install with: npm install -g @microsoft/azure-devops-cli or winget install Microsoft.AzureDevOpsCli"
        $details.AuthStatus = 'blocked'
    }
    
    # Check authentication by listing projects (doesn't require --organization if default is set)
    if ($null -ne $azVersion) {
        $org = $null
        try {
            # `az devops configure -l` always prints INI-style text; it ignores --output json.
            $config = @(az devops configure -l 2>&1)
            if ($LASTEXITCODE -eq 0) {
                $orgLine = $config | Where-Object { $_ -match '^\s*organization\s*=\s*(.+?)\s*$' } | Select-Object -First 1
                if ($orgLine -and $orgLine -match '^\s*organization\s*=\s*(.+?)\s*$') {
                    $org = $Matches[1]
                    $details.DefaultOrg = $org
                }
            }
        } catch {
            # Silently fail - default org may not be set
        }
        
        if ($null -ne $org) {
            try {
                $projects = az devops project list --organization $org --output json 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $details.AuthStatus = 'authenticated'
                    $details.Organization = $org
                } else {
                    $findings += New-Finding -Code 'EIGD002' -Severity 'Block' `
                        -Path 'az devops' `
                        -Message "Authentication failed for organization '$org'. Run: az login"
                    $details.AuthStatus = 'blocked'
                }
            } catch {
                $findings += New-Finding -Code 'EIGD002' -Severity 'Block' `
                    -Path 'az devops' `
                    -Message "Could not list projects in organization '$org': $($_.Exception.Message). Run: az login"
                $details.AuthStatus = 'blocked'
            }
        } else {
            $findings += New-Finding -Code 'EIGD002' -Severity 'ManualReview' `
                -Path 'az devops' `
                -Message "No default Azure DevOps organization is configured. Run: az devops configure --defaults organization=<your-org>"
            $details.AuthStatus = 'needs-config'
        }
    }
    
    , @($findings, $details)
}

# ============================================================================
# Check 3: Plugin File Structure (EIGD003)
# ============================================================================

function Test-PluginFileStructure {
    param([string] $PluginRoot)
    
    $findings = @()
    $details = @{}
    
    $pluginRoot = $PluginRoot
    
    $requiredFiles = @(
        'agents/ei-graphics.agent.md',
        'skills/ei-azure-devops-cli-intake/SKILL.md',
        'skills/ei-graphics-core/SKILL.md',
        'skills/ei-layer-guard/SKILL.md',
        'skills/termination-drawing/SKILL.md',
        'skills/ei-graphics-core/references/domain-skill-registry.json',
        'skills/ei-graphics-core/schemas/ado.schema.json',
        'skills/ei-graphics-core/schemas/session.schema.json',
        'skills/ei-graphics-core/schemas/story-understanding.schema.json',
        'skills/ei-graphics-core/schemas/approved-files.schema.json',
        'skills/ei-graphics-core/schemas/domain-skill-registry.schema.json'
    )
    
    $filesFound = 0
    $filesValid = 0
    $missingFiles = @()
    $truncatedFiles = @()
    
    # domain-skill-registry.json is legitimately small with few domains registered; Check 4
    # already validates its content against a JSON schema, so it gets a lower floor than the
    # prose documents this heuristic exists to catch truncated copies of.
    $minSizeOverrides = @{
        'skills/ei-graphics-core/references/domain-skill-registry.json' = 100
    }
    
    foreach ($file in $requiredFiles) {
        $fullPath = Join-Path $pluginRoot $file
        if (Test-Path -LiteralPath $fullPath) {
            $filesFound++
            $size = (Get-Item -LiteralPath $fullPath).Length
            $minSize = if ($minSizeOverrides.ContainsKey($file)) { $minSizeOverrides[$file] } else { 500 }
            if ($size -lt $minSize) {
                $truncatedFiles += $file
                $findings += New-Finding -Code 'EIGD003' -Severity 'Block' `
                    -Path $file `
                    -Message "File is truncated ($size bytes). Expected >= $minSize bytes. Check: $fullPath"
            } else {
                $filesValid++
            }
        } else {
            $missingFiles += $file
            $findings += New-Finding -Code 'EIGD003' -Severity 'Block' `
                -Path $file `
                -Message "Required file not found. Expected: $fullPath"
        }
    }
    
    $details.FilesRequired = $requiredFiles.Count
    $details.FilesFound = $filesFound
    $details.FilesValid = $filesValid
    $details.MissingFiles = $missingFiles.Count
    $details.TruncatedFiles = $truncatedFiles.Count
    
    , @($findings, $details)
}

# ============================================================================
# Check 4: Skill Registry & Schemas (EIGD004)
# ============================================================================

function Test-SkillRegistry {
    param([string] $PluginRoot)
    
    $findings = @()
    $details = @{}
    
    $pluginRoot = $PluginRoot
    $registryPath = Join-Path $pluginRoot 'skills' 'ei-graphics-core' 'references' 'domain-skill-registry.json'
    $registrySchemaPath = Join-Path $pluginRoot 'skills' 'ei-graphics-core' 'schemas' 'domain-skill-registry.schema.json'
    $schemaFiles = @(
        'ado.schema.json',
        'session.schema.json',
        'story-understanding.schema.json',
        'approved-files.schema.json',
        'domain-skill-registry.schema.json'
    )
    
    # Default every key the report renderer reads, so an early return still yields a complete object
    $details.DomainsRegistered = 0
    $details.DomainsResolvable = 0
    $details.DomainsNotFound = 0
    $details.SchemasChecked = $schemaFiles.Count
    $details.SchemasLoaded = 0
    $details.SchemasNotFound = $schemaFiles.Count
    
    # Load registry
    if (-not (Test-Path -LiteralPath $registryPath)) {
        $findings += New-Finding -Code 'EIGD004' -Severity 'Block' `
            -Path 'domain-skill-registry.json' `
            -Message "Registry not found: $registryPath"
        , @($findings, $details)
        return
    }
    
    $registryText = $null
    try {
        $registryText = Get-Content -LiteralPath $registryPath -Raw
        $registry = $registryText | ConvertFrom-Json
    } catch {
        $findings += New-Finding -Code 'EIGD004' -Severity 'Block' `
            -Path 'domain-skill-registry.json' `
            -Message "Registry is not valid JSON: $($_.Exception.Message)"
        , @($findings, $details)
        return
    }
    
    # Validate registry against schema
    if (Test-Path -LiteralPath $registrySchemaPath) {
        $schemaText = Get-Content -LiteralPath $registrySchemaPath -Raw
        try {
            $null = $registryText | Test-Json -Schema $schemaText -ErrorAction Stop
        } catch {
            $findings += New-Finding -Code 'EIGD004' -Severity 'Block' `
                -Path 'domain-skill-registry.json' `
                -Message "Registry does not validate against schema: $($_.Exception.Message)"
        }
    }
    
    # Check all registered domains (which are skills)
    $domainsNotFound = @()
    
    if ($registry.domains) {
        $details.DomainsRegistered = $registry.domains.Count
        foreach ($domain in $registry.domains) {
            $domainId = $domain.id
            $skillPath = Join-Path $pluginRoot $domain.skillPath
            
            if (Test-Path -LiteralPath $skillPath) {
                $details.DomainsResolvable++
                
                # Check for frontmatter. (?m) matches per line; without it ^/$ anchor to the
                # whole file, so a real opening '---' followed by more content never matches.
                $skillText = Get-Content -LiteralPath $skillPath -Raw
                if (-not ($skillText -match '(?m)^---\s*$')) {
                    $findings += New-Finding -Code 'EIGD004' -Severity 'ManualReview' `
                        -Path $domain.skillPath `
                        -Message "Domain skill $domainId does not have YAML frontmatter (no opening ---)."
                    continue
                }
                
                if (-not ($skillText -match '(?m)^\s*name:\s*')) {
                    $findings += New-Finding -Code 'EIGD004' -Severity 'ManualReview' `
                        -Path $domain.skillPath `
                        -Message "Domain skill $domainId frontmatter is missing 'name:' key."
                }
                
                if (-not ($skillText -match '(?m)^\s*description:\s*')) {
                    $findings += New-Finding -Code 'EIGD004' -Severity 'ManualReview' `
                        -Path $domain.skillPath `
                        -Message "Domain skill $domainId frontmatter is missing 'description:' key."
                }
            } else {
                $domainsNotFound += $domainId
                $findings += New-Finding -Code 'EIGD004' -Severity 'Block' `
                    -Path $domain.skillPath `
                    -Message "Registered domain skill $domainId not found. Expected: $skillPath"
            }
        }
    }
    
    $details.DomainsNotFound = $domainsNotFound.Count
    
    # Check all schema files
    $schemasNotFound = @()
    
    foreach ($schemaFile in $schemaFiles) {
        $schemaPath = Join-Path $pluginRoot 'skills' 'ei-graphics-core' 'schemas' $schemaFile
        if (Test-Path -LiteralPath $schemaPath) {
            try {
                $schemaText = Get-Content -LiteralPath $schemaPath -Raw
                $null = $schemaText | ConvertFrom-Json -ErrorAction Stop
                $details.SchemasLoaded++
            } catch {
                $findings += New-Finding -Code 'EIGD004' -Severity 'Block' `
                    -Path "schemas/$schemaFile" `
                    -Message "Schema is not valid JSON: $($_.Exception.Message)"
            }
        } else {
            $schemasNotFound += $schemaFile
            $findings += New-Finding -Code 'EIGD004' -Severity 'Block' `
                -Path "schemas/$schemaFile" `
                -Message "Schema file not found: $schemaPath"
        }
    }
    
    $details.SchemasNotFound = $schemasNotFound.Count
    
    , @($findings, $details)
}

# ============================================================================
# Check 5: Session Artifacts (EIGD005)
# ============================================================================

function Test-SessionArtifacts {
    param([string] $RootPath, [string] $PluginRoot)
    
    $findings = @()
    $details = @{}
    
    $logsDir = Join-Path $RootPath '.ei-session-logs'
    
    # Check if directory exists
    $details.DirectoryExists = Test-Path -LiteralPath $logsDir -PathType Container
    if (-not $details.DirectoryExists) {
        $findings += New-Finding -Code 'EIGD005' -Severity 'ManualReview' `
            -Path '.ei-session-logs' `
            -Message "Session logs directory does not exist yet: $logsDir. It will be created on first run."
        $details.DirectoryWritable = $null
        , @($findings, $details)
        return
    }
    
    # Check if directory is writable
    $details.DirectoryWritable = $false
    $tempFile = Join-Path $logsDir ".test-writable-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    try {
        $null | Out-File -LiteralPath $tempFile -Force -ErrorAction Stop
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction Stop
        $details.DirectoryWritable = $true
    } catch {
        $findings += New-Finding -Code 'EIGD005' -Severity 'Block' `
            -Path '.ei-session-logs' `
            -Message "Session logs directory is not writable: $logsDir. Error: $($_.Exception.Message)"
    }
    
    # If directory exists and is writable, check for artifacts
    if ($details.DirectoryWritable) {
        $sessionDirs = @(Get-ChildItem -LiteralPath $logsDir -Directory -ErrorAction SilentlyContinue)
        $details.SessionsFound = $sessionDirs.Count
        
        if ($sessionDirs.Count -gt 0) {
            # Check latest session artifacts
            $latestSession = $sessionDirs | Sort-Object -Property Name -Descending | Select-Object -First 1
            $latestPath = $latestSession.FullName
            
            $artifactTypes = @{
                'session.json' = 'session.schema.json'
                'story-understanding.json' = 'story-understanding.schema.json'
                'ado.json' = 'ado.schema.json'
            }
            
            $pluginRoot = $PluginRoot
            
            foreach ($artifact in $artifactTypes.Keys) {
                $artifactPath = Join-Path $latestPath $artifact
                if (Test-Path -LiteralPath $artifactPath) {
                    $schemaName = $artifactTypes[$artifact]
                    $schemaPath = Join-Path $pluginRoot 'skills' 'ei-graphics-core' 'schemas' $schemaName
                    
                    try {
                        $artifactText = Get-Content -LiteralPath $artifactPath -Raw
                        $null = $artifactText | ConvertFrom-Json -ErrorAction Stop
                        
                        # Try schema validation if schema exists
                        if (Test-Path -LiteralPath $schemaPath) {
                            $schemaText = Get-Content -LiteralPath $schemaPath -Raw
                            try {
                                $null = $artifactText | Test-Json -Schema $schemaText -ErrorAction Stop
                            } catch {
                                $findings += New-Finding -Code 'EIGD005' -Severity 'ManualReview' `
                                    -Path ".ei-session-logs/$($latestSession.Name)/$artifact" `
                                    -Message "Artifact does not validate against schema: $($_.Exception.Message)"
                            }
                        }
                    } catch {
                        $findings += New-Finding -Code 'EIGD005' -Severity 'Block' `
                            -Path ".ei-session-logs/$($latestSession.Name)/$artifact" `
                            -Message "Artifact is not valid JSON: $($_.Exception.Message)"
                    }
                }
            }
        }
    }
    
    , @($findings, $details)
}

# ============================================================================
# Check 6: Git Configuration (EIGD006)
# ============================================================================

function Test-GitConfiguration {
    param([string] $RootPath)
    
    $findings = @()
    $details = @{}
    
    # Default every key the report renderer reads, so an early return still yields a complete object
    $details.UserName = $null
    $details.UserConfigured = $false
    $details.UserEmail = $null
    $details.EmailConfigured = $false
    $details.GcAutoValue = $null
    $details.GcAutoSet = $false
    
    $gitDir = Join-Path $RootPath '.git'
    $details.GitRepoExists = Test-Path -LiteralPath $gitDir -PathType Container
    
    if (-not $details.GitRepoExists) {
        $findings += New-Finding -Code 'EIGD006' -Severity 'Block' `
            -Path '.git' `
            -Message "Git repository not initialized. Run: git init from the root directory."
        , @($findings, $details)
        return
    }
    
    # Check user.name
    $userName = $null
    try {
        Push-Location -LiteralPath $RootPath
        $userName = git config --local user.name 2>$null
        if (-not $userName) {
            $userName = git config --global user.name 2>$null
        }
        $details.UserName = $userName
        $details.UserConfigured = -not [string]::IsNullOrWhiteSpace($userName)
    } catch {
        $details.UserConfigured = $false
    } finally {
        Pop-Location
    }
    
    if (-not $details.UserConfigured) {
        $findings += New-Finding -Code 'EIGD006' -Severity 'ManualReview' `
            -Path '.git/config' `
            -Message "Git user name is not configured. Run: git config --local user.name 'Your Name'"
    }
    
    # Check user.email
    $userEmail = $null
    try {
        Push-Location -LiteralPath $RootPath
        $userEmail = git config --local user.email 2>$null
        if (-not $userEmail) {
            $userEmail = git config --global user.email 2>$null
        }
        $details.UserEmail = $userEmail
        $details.EmailConfigured = -not [string]::IsNullOrWhiteSpace($userEmail)
    } catch {
        $details.EmailConfigured = $false
    } finally {
        Pop-Location
    }
    
    if (-not $details.EmailConfigured) {
        $findings += New-Finding -Code 'EIGD006' -Severity 'ManualReview' `
            -Path '.git/config' `
            -Message "Git user email is not configured. Run: git config --local user.email 'your.email@example.com'"
    }
    
    # Check gc.auto for OneDrive safety
    $gcAuto = $null
    try {
        Push-Location -LiteralPath $RootPath
        $gcAuto = git config --local gc.auto 2>$null
        if ($null -eq $gcAuto) {
            $gcAuto = git config --global gc.auto 2>$null
        }
        $details.GcAutoValue = $gcAuto
        $details.GcAutoSet = -not [string]::IsNullOrWhiteSpace($gcAuto)
    } catch {
        $details.GcAutoSet = $false
    } finally {
        Pop-Location
    }
    
    if ($details.GcAutoSet -and $gcAuto -ne '0') {
        $findings += New-Finding -Code 'EIGD006' -Severity 'ManualReview' `
            -Path '.git/config' `
            -Message "gc.auto is set to '$gcAuto' but should be 0 for OneDrive sync safety. Run: git config --local gc.auto 0"
    } elseif (-not $details.GcAutoSet) {
        $findings += New-Finding -Code 'EIGD006' -Severity 'ManualReview' `
            -Path '.git/config' `
            -Message "gc.auto is not set. For OneDrive sync safety, run: git config --local gc.auto 0"
    }
    
    , @($findings, $details)
}

# ============================================================================
# Main
# ============================================================================

$rootPath = (Resolve-Path -LiteralPath $Root).Path

# The plugin's own files live beside this script, not necessarily under -Root: -Root is the
# target repository a story is being worked in, which never contains a copy of the plugin.
$pluginRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path

$findings = @()
$checkDetails = @{}

# Run all checks
Write-Problem 'Checking PowerShell runtime...'
$result = Test-PowerShellRuntime
$findings += $result[0]
$checkDetails.PowerShellRuntime = $result[1]

Write-Problem 'Checking Azure DevOps CLI & authentication...'
$result = Test-AzureDevOpsCli
$findings += $result[0]
$checkDetails.AzureDevOpsCliAuth = $result[1]

Write-Problem 'Checking plugin file structure...'
$result = Test-PluginFileStructure -PluginRoot $pluginRoot
$findings += $result[0]
$checkDetails.PluginFileStructure = $result[1]

Write-Problem 'Checking skill registry & schemas...'
$result = Test-SkillRegistry -PluginRoot $pluginRoot
$findings += $result[0]
$checkDetails.SkillRegistryAndSchemas = $result[1]

Write-Problem 'Checking session artifacts...'
$result = Test-SessionArtifacts -RootPath $rootPath -PluginRoot $pluginRoot
$findings += $result[0]
$checkDetails.SessionArtifacts = $result[1]

Write-Problem 'Checking git configuration...'
$result = Test-GitConfiguration -RootPath $rootPath
$findings += $result[0]
$checkDetails.GitConfiguration = $result[1]

# Determine overall status
$status = 'pass'
$violations = @($findings | Where-Object { $_.Severity -eq 'Block' })
$reviewFlags = @($findings | Where-Object { $_.Severity -in @('ManualReview', 'Info') })

if ($violations.Count -gt 0) {
    $status = 'blocked'
} elseif ($reviewFlags.Count -gt 0) {
    $status = 'needs-manual-review'
}

# Collect affected areas
$affectedAreas = @($findings | Select-Object -ExpandProperty Path -Unique | Where-Object { $_ })

# Collect required actions
$requiredActions = @(
    $findings | 
    Where-Object { $_.Severity -in @('Block', 'ManualReview') } |
    ForEach-Object { 
        if ($_.Message -match 'Run: (.+)$') {
            $Matches[1]
        } else {
            $_.Message
        }
    } |
    Select-Object -Unique
)

if ($Json) {
    # Output JSON
    $output = [pscustomobject]@{
        status          = $status
        timestamp       = [System.DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        targetRoot      = $rootPath
        pluginRoot      = $pluginRoot
        violations      = $violations
        reviewFlags     = $reviewFlags
        affectedAreas   = @($affectedAreas | Select-Object -Unique)
        requiredActions = @($requiredActions | Select-Object -Unique)
        checkDetails    = [pscustomobject]$checkDetails
    }
    $output | ConvertTo-Json -Depth 10
} else {
    # Output table
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗"
    Write-Host "║          EI GRAPHICS PLUGIN DIAGNOSTIC REPORT                 ║"
    Write-Host "╚════════════════════════════════════════════════════════════════╝`n"
    
    # Compute check statuses into variables (avoid 'if' inside hashtable literals)
    $psStatus = if ($checkDetails.PowerShellRuntime.VersionOK) { 'Ready' } else { 'Blocked' }
    $azStatus = if ($checkDetails.AzureDevOpsCliAuth.AuthStatus -eq 'authenticated') { 'Ready' } elseif ($checkDetails.AzureDevOpsCliAuth.AuthStatus -eq 'needs-config') { 'ManualReview' } else { 'Blocked' }
    $pluginStatus = if ($checkDetails.PluginFileStructure.MissingFiles -eq 0 -and $checkDetails.PluginFileStructure.TruncatedFiles -eq 0) { 'Ready' } else { 'Blocked' }
    $registryStatus = if ($checkDetails.SkillRegistryAndSchemas.DomainsResolvable -eq $checkDetails.SkillRegistryAndSchemas.DomainsRegistered -and $checkDetails.SkillRegistryAndSchemas.SchemasLoaded -eq $checkDetails.SkillRegistryAndSchemas.SchemasChecked) { 'Ready' } else { 'Blocked' }
    $sessionStatus = if ($checkDetails.SessionArtifacts.DirectoryWritable -eq $true) { 'Ready' } elseif ($checkDetails.SessionArtifacts.DirectoryExists -eq $false) { 'ManualReview' } else { 'Blocked' }
    $gitStatus = if ($checkDetails.GitConfiguration.UserConfigured -and ($checkDetails.GitConfiguration.GcAutoValue -eq '0' -or $checkDetails.GitConfiguration.GcAutoValue -eq $null)) { 'Ready' } else { 'ManualReview' }
    
    $psEvidence = "v$($checkDetails.PowerShellRuntime.Version ?? 'unknown')"
    $azEvidence = $checkDetails.AzureDevOpsCliAuth.Organization ?? 'Not configured'
    $pluginEvidence = "$($checkDetails.PluginFileStructure.FilesValid ?? 0)/$($checkDetails.PluginFileStructure.FilesRequired ?? 0) files OK"
    $registryEvidence = "$($checkDetails.SkillRegistryAndSchemas.DomainsResolvable ?? 0) domains, $($checkDetails.SkillRegistryAndSchemas.SchemasLoaded ?? 0) schemas"
    $sessionEvidence = if ($checkDetails.SessionArtifacts.DirectoryWritable) { 'Writable' } else { 'Not ready' }
    $gitEvidence = if ($checkDetails.GitConfiguration.UserConfigured) { "User: $($checkDetails.GitConfiguration.UserName ?? 'unknown')" } else { 'Not configured' }
    
    $checks = @(
        [pscustomobject]@{ Check = 'PowerShell Runtime'; Status = $psStatus; Evidence = $psEvidence },
        [pscustomobject]@{ Check = 'Azure DevOps CLI'; Status = $azStatus; Evidence = $azEvidence },
        [pscustomobject]@{ Check = 'Plugin Structure'; Status = $pluginStatus; Evidence = $pluginEvidence },
        [pscustomobject]@{ Check = 'Skill Registry'; Status = $registryStatus; Evidence = $registryEvidence },
        [pscustomobject]@{ Check = 'Session Artifacts'; Status = $sessionStatus; Evidence = $sessionEvidence },
        [pscustomobject]@{ Check = 'Git Configuration'; Status = $gitStatus; Evidence = $gitEvidence }
    )
    
    $checks | Format-Table -AutoSize
    
    Write-Host "`n─ Required Actions ─`n"
    if ($requiredActions.Count -eq 0) {
        Write-Host "   ✓ All checks passed. No actions required.`n"
    } else {
        foreach ($action in $requiredActions) {
            Write-Host "   • $action"
        }
        Write-Host ""
    }
    
    Write-Host "─ Overall Status ─`n"
    $statusColor = switch ($status) {
        'pass' { 'Green' }
        'blocked' { 'Red' }
        'needs-manual-review' { 'Yellow' }
        default { 'Gray' }
    }
    Write-Host "   STATUS: " -NoNewline
    Write-Host $status.ToUpper() -ForegroundColor $statusColor
    Write-Host ""
}

# Exit with appropriate code
$exitCode = if ($status -eq 'pass') { 0 } else { 1 }
exit $exitCode
