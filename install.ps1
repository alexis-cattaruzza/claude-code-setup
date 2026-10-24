#Requires -Version 5.1
<#
  claude-code-setup: baseline Claude Code setup for any machine and any stack.
  Global:   powershell -ExecutionPolicy Bypass -File .\install.ps1
  Project:  powershell -ExecutionPolicy Bypass -File .\install.ps1 -Project C:\path\to\repo
#>
[CmdletBinding()]
param(
    [string]$Project,            # repo or workspace folder to initialise (optional)
    [switch]$Force,              # overwrite an existing project CLAUDE.md
    [switch]$Share,              # do not hide Claude files from git (team wants them committed)
    [switch]$NoAttribution,      # no Co-Authored-By / PR footer from Claude
    [switch]$SkipClaudeInstall
)
$ErrorActionPreference = 'Stop'
$UserHome  = [Environment]::GetFolderPath('UserProfile')
$ClaudeDir = Join-Path $UserHome '.claude'
$BackupDir = Join-Path $ClaudeDir ("backups\base-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Begin = '<!-- claude-code-setup:begin -->'
$End   = '<!-- claude-code-setup:end -->'
$Changes = New-Object System.Collections.Generic.List[string]

# ---------- helpers ----------
function Write-Text($Path, $Text) {
    $dir = Split-Path $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($Path, ($Text -replace "`r`n", "`n"), $Utf8NoBom)
}
function Backup-File($Path) {
    if (Test-Path $Path) {
        New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
        Copy-Item $Path (Join-Path $BackupDir ((Split-Path $Path -Leaf) + '.' + (Split-Path (Split-Path $Path) -Leaf))) -Force
    }
}
function Set-ManagedBlock($Path, $Block) {
    Backup-File $Path
    $new = "$Begin`n$Block`n$End"
    $cur = if (Test-Path $Path) { [IO.File]::ReadAllText($Path) } else { '' }
    $i = $cur.IndexOf($Begin); $j = $cur.IndexOf($End)
    if ($i -ge 0 -and $j -gt $i) { $cur = $cur.Substring(0, $i) + $new + $cur.Substring($j + $End.Length) }
    elseif ($cur.Trim()) { $cur = $cur.TrimEnd() + "`n`n" + $new }
    else { $cur = $new }
    Write-Text $Path ($cur.TrimEnd() + "`n")
    $Changes.Add("CLAUDE.md block updated: $Path")
}
function ConvertTo-Hash($o) {
    if ($o -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}; foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = ConvertTo-Hash $p.Value }; return $h
    }
    if ($o -is [System.Collections.IEnumerable] -and $o -isnot [string]) { return ,@($o | ForEach-Object { ConvertTo-Hash $_ }) }
    return $o
}
function Merge-Hash($Cur, $Base) {   # existing values win, arrays are unioned
    foreach ($k in $Base.Keys) {
        if (-not $Cur.Contains($k)) { $Cur[$k] = $Base[$k] }
        elseif ($Cur[$k] -is [System.Collections.IDictionary] -and $Base[$k] -is [System.Collections.IDictionary]) { [void](Merge-Hash $Cur[$k] $Base[$k]) }
        elseif ($Cur[$k] -is [array] -and $Base[$k] -is [array]) { $Cur[$k] = @(@($Cur[$k]) + @($Base[$k]) | Select-Object -Unique) }
    }
    return $Cur
}
function Merge-Settings($Path, $Base) {
    Backup-File $Path
    $cur = [ordered]@{}
    if (Test-Path $Path) {
        try { $cur = ConvertTo-Hash (Get-Content $Path -Raw | ConvertFrom-Json) }
        catch { throw "Invalid JSON in $Path. Fix it or delete it, then re-run." }
    }
    Write-Text $Path ((Merge-Hash $cur $Base | ConvertTo-Json -Depth 10) + "`n")
    $Changes.Add("settings merged: $Path")
}

# ---------- 1. prerequisites ----------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warning 'Git not found. Recommended: https://git-scm.com/downloads/win (Claude Code then uses Git Bash).'
}
if (-not (Get-Command claude -ErrorAction SilentlyContinue) -and -not $SkipClaudeInstall) {
    Write-Host 'Installing Claude Code (official installer)...'
    Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
    $bin = Join-Path $UserHome '.local\bin'
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath -notlike "*$bin*") { [Environment]::SetEnvironmentVariable('Path', "$userPath;$bin", 'User') }
    $env:Path += ";$bin"
    $Changes.Add('Claude Code installed')
}

# ---------- 2. global CLAUDE.md ----------
$GlobalRules = @'
# Base rules (all projects)

## Workflow
- Understand before changing: read the relevant code, ask when the request is ambiguous.
- For changes touching several files, propose a solid version and never guess anything.
- Root cause first, then the fix. No speculative fixes.

## Code
- Minimal diffs that follow the existing patterns and style of the project.
- Verify names, signatures and schemas in the source before using them. Never guess.
- No new dependency, framework or abstraction without asking.
- No unrelated refactoring or reformatting.
- Do not add comments that only restate the code.

## Verification
- Before saying done, run what the project has (build, tests, linter, type check) and say what ran.
- Review failure cases: empty or invalid input, timeouts, duplicates, missing config.

## Tokens
- Locate code with grep/glob or the code-finder agent, then read only the needed line ranges.
- Never read build output, dependencies, lock files, generated code or logs in full.
- Answers short and direct, with exact file:line locations.

## Git and safety
- Never commit, push or open a PR/MR without explicit approval. Leave changes uncommitted.
- Never print, copy or commit secrets (.env, keys, tokens, passwords).
- Never run destructive commands (rm -rf, force push, hard reset, dropping data) without approval.
'@
Set-ManagedBlock (Join-Path $ClaudeDir 'CLAUDE.md') $GlobalRules

# ---------- 3. global settings.json ----------
$Global = [ordered]@{
    '$schema'   = 'https://json.schemastore.org/claude-code-settings.json'
    permissions = [ordered]@{
        ask  = @('Bash(git commit *)', 'Bash(git -C * commit *)', 'Bash(git push *)', 'Bash(git -C * push *)')
        deny = @('Bash(git push --force *)', 'Bash(git push -f *)', 'Bash(git reset --hard *)',
                 'Read(./.env)', 'Read(./.env.*)', 'Read(./**/*.pem)', 'Read(./**/*.key)')
    }
}
if ($NoAttribution) { $Global['attribution'] = [ordered]@{ commit = ''; pr = '' }; $Global['includeCoAuthoredBy'] = $false }
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
    $bash = Join-Path (Split-Path (Split-Path $git.Source)) 'bin\bash.exe'
    if (Test-Path $bash) { $Global['env'] = [ordered]@{ CLAUDE_CODE_GIT_BASH_PATH = $bash } }
}
Merge-Settings (Join-Path $ClaudeDir 'settings.json') $Global

# ---------- 4. search agent ----------
$Agent = @'
---
name: code-finder
description: Use to locate code (classes, functions, usages, routes, config keys) in the project. Returns paths, line numbers and a short summary, never whole files.
tools: Read, Grep, Glob
model: haiku
---
You locate code. Use Grep and Glob first, then Read only the smallest line range needed.
Answer with path:line, the signature, and at most 5 lines of explanation.
Never paste whole files. Never edit anything.
'@
$agentPath = Join-Path $ClaudeDir 'agents\code-finder.md'
Backup-File $agentPath; Write-Text $agentPath $Agent; $Changes.Add("agent: $agentPath")

# ---------- 5. project (optional) ----------
if ($Project) {
    $root = (Resolve-Path $Project).Path
    $rules = @(
        @{ f = 'package.json';      n = 'Node / JS / TS';     c = 'see package.json scripts (install, build, test, lint)'; d = 'node_modules','dist','build','.angular','.next','coverage' },
        @{ f = 'pom.xml';           n = 'Java / Maven';       c = 'mvn -q compile; mvn test (mvnw if present)';            d = 'target' },
        @{ f = 'build.gradle*';     n = 'JVM / Gradle';       c = 'gradlew build; gradlew test';                           d = 'build','.gradle' },
        @{ f = 'pyproject.toml';    n = 'Python';             c = 'pytest; linter if configured';                          d = '.venv','venv','__pycache__','.pytest_cache','dist' },
        @{ f = 'requirements*.txt'; n = 'Python';             c = 'pytest; linter if configured';                          d = '.venv','venv','__pycache__','.pytest_cache' },
        @{ f = 'go.mod';            n = 'Go';                 c = 'go build ./...; go test ./...';                         d = 'bin' },
        @{ f = 'Cargo.toml';        n = 'Rust';               c = 'cargo build; cargo test';                               d = 'target' },
        @{ f = '*.sln';             n = '.NET';               c = 'dotnet build; dotnet test';                             d = 'bin','obj' },
        @{ f = '*.csproj';          n = '.NET';               c = 'dotnet build; dotnet test';                             d = 'bin','obj' }
    )
    $skip = 'node_modules','target','dist','build','bin','obj','venv'
    $dirs = @(Get-Item $root) + @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike '.*' -and $_.Name -notin $skip })
    $found = foreach ($d in $dirs) { foreach ($r in $rules) {
        if (Get-ChildItem -Path $d.FullName -Filter $r.f -File -ErrorAction SilentlyContinue | Select-Object -First 1) {
            $rel = if ($d.FullName -eq $root) { '.' } else { $d.Name }
            [pscustomobject]@{ Rel = $rel; Name = $r.n; Cmds = $r.c; Deny = $r.d }
        } } }
    $found = @($found | Sort-Object Rel, Name -Unique)

    # project CLAUDE.md (starter, never overwritten without -Force)
    $pMd = Join-Path $root 'CLAUDE.md'
    if (-not (Test-Path $pMd) -or $Force) {
        Backup-File $pMd
        $layout = if ($found) { ($found | ForEach-Object { "- $($_.Rel): $($_.Name)" }) -join "`n" } else { '- (no known stack detected: describe the layout)' }
        $cmds   = if ($found) { ($found | ForEach-Object { "- $($_.Rel): $($_.Cmds)" }) -join "`n" } else { '- (build, test, run commands)' }
        Write-Text $pMd @"
# $(Split-Path $root -Leaf)

<!-- Replace the placeholders, or run /init in Claude Code to draft them. Keep under 150 lines. -->

What this project does: (2 lines)

## Layout
$layout

## Commands
$cmds

## Conventions
- (architecture, naming, patterns Claude must follow)

## Do not touch
- (generated code, migrations already applied, shared config...)
"@
        $Changes.Add("project CLAUDE.md: $pMd")
    } else { Write-Host "Kept existing $pMd (use -Force to replace)." }

    # project settings: deny build output of every detected stack
    $deny = @('Read(./**/*.log)') + @($found | ForEach-Object { $_.Deny } | Select-Object -Unique | ForEach-Object { "Read(./**/$_/**)" })
    Merge-Settings (Join-Path $root '.claude\settings.json') ([ordered]@{
        '$schema'   = 'https://json.schemastore.org/claude-code-settings.json'
        permissions = [ordered]@{ deny = @($deny) } })

    # keep Claude files out of git, in every repo found (root or direct subfolders)
    if (-not $Share) {
        foreach ($d in $dirs) {
            $ex = Join-Path $d.FullName '.git\info\exclude'
            if (Test-Path (Join-Path $d.FullName '.git')) {
                $cur = if (Test-Path $ex) { Get-Content $ex } else { @() }
                $add = @('CLAUDE.md', 'CLAUDE.local.md', '.claude/', '.mcp.json') | Where-Object { $cur -notcontains $_ }
                if ($add) { Add-Content -Path $ex -Value $add; $Changes.Add("git exclude: $ex") }
            }
        }
    }
}

# ---------- 6. summary ----------
Write-Host "`nDone." -ForegroundColor Green
$Changes | ForEach-Object { Write-Host "  - $_" }
if (Test-Path $BackupDir) { Write-Host "Backups: $BackupDir" }
Write-Host @"

Next steps:
  1. Open a NEW terminal, run: claude doctor
  2. In your project folder run: claude   (log in the first time)
  3. In Claude Code: /memory to see the rules, /init to complete the project CLAUDE.md
  To set up a project: rerun this script with -Project <folder>
"@