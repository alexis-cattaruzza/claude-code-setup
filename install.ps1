#Requires -Version 5.1
<#
  claude-code-setup: baseline Claude Code setup for any machine and any stack.
  Machine:  claude-setup                                (first run: powershell -ExecutionPolicy Bypass -File .\install.ps1)
  Project:  claude-setup -Project <folder> [-Complete]
  Update:   claude-setup -Update
#>
[CmdletBinding()]
param(
    [string]$Project,            # repo or workspace folder to set up (optional)
    [switch]$Complete,           # then open Claude in the project to complete its files (/project-setup)
    [string]$Rules,              # personal rules file (path or URL), installed in its own block; remembered
    [switch]$Force,              # replace existing project CLAUDE.md files (a backup is kept)
    [switch]$Share,              # do not hide Claude files from git (team wants them committed)
    [switch]$NoAttribution,      # no Co-Authored-By / PR footer from Claude; remembered
    [switch]$Update,             # git pull this repo first, then run
    [switch]$SkipClaudeInstall
)
$ErrorActionPreference = 'Stop'
$Here      = $PSScriptRoot
$Tpl       = Join-Path $Here 'templates'
$Sandbox   = [bool]$env:CLAUDE_SETUP_HOME   # test runs: fake home, PATH untouched
$UserHome  = if ($Sandbox) { $env:CLAUDE_SETUP_HOME } else { [Environment]::GetFolderPath('UserProfile') }
$ClaudeDir = Join-Path $UserHome '.claude'
$BinDir    = Join-Path $UserHome '.local\bin'
$ConfigPath = Join-Path $ClaudeDir 'claude-code-setup.json'
$BackupDir = Join-Path $ClaudeDir ("backups\claude-code-setup-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Changes = New-Object System.Collections.Generic.List[string]

# ---------- 0. self update ----------
if ($Update) {
    if (-not (Test-Path (Join-Path $Here '.git'))) { throw "$Here is not a git clone. Download the repo again to update." }
    git -C $Here pull --ff-only
    if ($LASTEXITCODE) { throw 'git pull failed (local changes in the setup repo?).' }
    $rest = foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Key -eq 'Update') { continue }
        if ($kv.Value -is [System.Management.Automation.SwitchParameter]) { if ($kv.Value) { "-$($kv.Key)" } }
        else { "-$($kv.Key)"; "$($kv.Value)" }
    }
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @rest
    exit $LASTEXITCODE
}

# ---------- helpers ----------
function Read-Text($Path) { if (Test-Path $Path) { [IO.File]::ReadAllText($Path) } else { '' } }
function Read-Template($Name) {
    $p = Join-Path $Tpl $Name
    if (-not (Test-Path $p)) { throw "Missing template $p. Run install.ps1 from a full copy of the repo." }
    Read-Text $p
}
$BackedUp = New-Object System.Collections.Generic.HashSet[string]
function Backup-File($Path) {   # once per run, so the backup is always the original file
    if ((Test-Path $Path) -and $BackedUp.Add($Path)) {
        New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
        $hash = [BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($Path))).Replace('-', '').Substring(0, 6)
        $name = '{0}_{1}_{2}' -f (Split-Path (Split-Path $Path) -Leaf), (Split-Path $Path -Leaf), $hash
        Copy-Item $Path (Join-Path $BackupDir $name) -Force
        Add-Content -Path (Join-Path $BackupDir 'index.txt') -Value "$name <- $Path"
    }
}
function Save($Path, $Text, $Label) {   # writes only when the content changes, backs up the old file
    $Text = $Text -replace "`r`n", "`n"
    if ((Test-Path $Path) -and (Read-Text $Path) -eq $Text) { return }
    Backup-File $Path
    $dir = Split-Path $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
    $Changes.Add("${Label}: $Path")
}
function Set-ManagedBlock($Path, $Id, $Block) {
    $b = "<!-- claude-code-setup:${Id}:begin -->"; $e = "<!-- claude-code-setup:${Id}:end -->"
    $new = "$b`n$($Block.Trim())`n$e"
    $cur = (Read-Text $Path) -replace "`r`n", "`n"
    if ($Id -eq 'base') { $cur = $cur.Replace('<!-- claude-code-setup:begin -->', $b).Replace('<!-- claude-code-setup:end -->', $e) }
    $i = $cur.IndexOf($b); $j = $cur.IndexOf($e)
    if ($i -ge 0 -and $j -gt $i) { $cur = $cur.Substring(0, $i) + $new + $cur.Substring($j + $e.Length) }
    elseif ($cur.Trim()) { $cur = $cur.TrimEnd() + "`n`n" + $new }
    else { $cur = $new }
    Save $Path ($cur.TrimEnd() + "`n") "CLAUDE.md block '$Id'"
}
function ConvertTo-Hash($o) {
    if ($o -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}; foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = ConvertTo-Hash $p.Value }; return $h
    }
    if ($o -is [System.Collections.IEnumerable] -and $o -isnot [string]) { return ,@($o | ForEach-Object { ConvertTo-Hash $_ }) }
    return $o
}
function Read-Json($Path) {
    $raw = Read-Text $Path
    if (-not $raw.Trim()) { return [ordered]@{} }
    try { return ConvertTo-Hash ($raw | ConvertFrom-Json) }
    catch { throw "Invalid JSON in $Path. Fix it or delete it, then re-run." }
}
function Merge-Hash($Cur, $Base) {   # existing values win, arrays are unioned
    foreach ($k in $Base.Keys) {
        if (-not $Cur.Contains($k)) { $Cur[$k] = $Base[$k] }
        elseif ($Cur[$k] -is [System.Collections.IDictionary] -and $Base[$k] -is [System.Collections.IDictionary]) { [void](Merge-Hash $Cur[$k] $Base[$k]) }
        elseif ($Cur[$k] -is [array] -and $Base[$k] -is [array]) { $Cur[$k] = @(@($Cur[$k]) + @($Base[$k]) | Select-Object -Unique) }
    }
    return $Cur
}
function ConvertTo-JsonText($o) {   # PowerShell 5.1 escapes ' < > & as \u00xx: valid but unreadable
    $t = $o | ConvertTo-Json -Depth 20
    foreach ($c in 0x27, 0x3c, 0x3e, 0x26) { $t = $t.Replace(("\u{0:x4}" -f $c), [string][char]$c) }
    $t
}
function Merge-Settings($Path, $Base) {
    $cur = Read-Json $Path
    $before = ConvertTo-JsonText $cur
    $after = ConvertTo-JsonText (Merge-Hash $cur $Base)
    if ($before -ne $after) { Save $Path ($after + "`n") 'settings merged' }
}
function Add-UserPath($Dir) {
    if (($env:Path -split ';') -notcontains $Dir) { $env:Path += ";$Dir" }
    if ($Sandbox) { return }
    $p = [string][Environment]::GetEnvironmentVariable('Path', 'User')
    if (($p -split ';') -notcontains $Dir) {
        [Environment]::SetEnvironmentVariable('Path', ((@($p.TrimEnd(';'), $Dir) | Where-Object { $_ }) -join ';'), 'User')
        $Changes.Add("user PATH += $Dir")
    }
}

# ---------- 1. remembered options ----------
$Config = Read-Json $ConfigPath
if ($Rules) {
    if ($Rules -notmatch '^https?://') { $Rules = (Resolve-Path $Rules).Path }
    $Config['rules'] = $Rules
}
if ($NoAttribution) { $Config['noAttribution'] = $true }
if ($Config.Count) { Save $ConfigPath (($Config | ConvertTo-Json) + "`n") 'options' }

# ---------- 2. prerequisites ----------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warning 'Git not found. Recommended: winget install Git.Git (Claude Code then uses Git Bash).'
}
if (-not (Get-Command claude -ErrorAction SilentlyContinue) -and -not $SkipClaudeInstall -and -not $Sandbox) {
    Write-Host 'Installing Claude Code (official installer)...'
    Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
    $Changes.Add('Claude Code installed')
}
Add-UserPath $BinDir

# ---------- 3. global CLAUDE.md ----------
$GlobalMd = Join-Path $ClaudeDir 'CLAUDE.md'
Set-ManagedBlock $GlobalMd 'base' (Read-Template 'global\CLAUDE.md')
if ($Config['rules']) {
    try {
        $src = $Config['rules']
        $personal = if ($src -match '^https?://') { Invoke-RestMethod $src } else { Read-Text $src }
        if ("$personal".Trim()) { Set-ManagedBlock $GlobalMd 'personal' "$personal" } else { Write-Warning "Personal rules empty or missing: $src (block kept)." }
    } catch { Write-Warning "Cannot read personal rules from $($Config['rules']): $($_.Exception.Message) (block kept)." }
}

# ---------- 4. global settings.json ----------
$Global = ConvertTo-Hash (Read-Template 'global\settings.json' | ConvertFrom-Json)
if ($Config['noAttribution']) { $Global['attribution'] = [ordered]@{ commit = ''; pr = '' }; $Global['includeCoAuthoredBy'] = $false }
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
    $bash = Join-Path (Split-Path (Split-Path $git.Source)) 'bin\bash.exe'
    if (Test-Path $bash) { $Global['env'] = [ordered]@{ CLAUDE_CODE_GIT_BASH_PATH = $bash } }
}
Merge-Settings (Join-Path $ClaudeDir 'settings.json') $Global

# ---------- 5. agent, skill and claude-setup command ----------
Save (Join-Path $ClaudeDir 'agents\code-finder.md') (Read-Template 'agents\code-finder.md') 'agent'
Save (Join-Path $ClaudeDir 'skills\project-setup\SKILL.md') (Read-Template 'skills\project-setup\SKILL.md') 'skill'
Save (Join-Path $BinDir 'claude-setup.cmd') "@echo off`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" %*`n" 'command'

# ---------- 6. project (optional) ----------
if ($Project) {
    $root = (Resolve-Path $Project).Path
    $stacks = @(
        @{ f = 'package.json';      n = 'Node / JS / TS'; c = 'see package.json scripts (install, build, test, lint)'; d = 'node_modules','dist','build','.angular','.next','coverage' },
        @{ f = 'pom.xml';           n = 'Java / Maven';   c = 'mvn -q compile; mvn test -Dtest=ClassName (mvnw if present)'; d = 'target' },
        @{ f = 'build.gradle*';     n = 'JVM / Gradle';   c = 'gradlew build; gradlew test';                           d = 'build','.gradle' },
        @{ f = 'pyproject.toml';    n = 'Python';         c = 'pytest; linter if configured';                          d = '.venv','venv','__pycache__','.pytest_cache','dist' },
        @{ f = 'requirements*.txt'; n = 'Python';         c = 'pytest; linter if configured';                          d = '.venv','venv','__pycache__','.pytest_cache' },
        @{ f = 'go.mod';            n = 'Go';             c = 'go build ./...; go test ./...';                         d = @() },
        @{ f = 'Cargo.toml';        n = 'Rust';           c = 'cargo build; cargo test';                               d = 'target' },
        @{ f = '*.sln';             n = '.NET';           c = 'dotnet build; dotnet test';                             d = 'bin','obj' },
        @{ f = '*.csproj';          n = '.NET';           c = 'dotnet build; dotnet test';                             d = 'bin','obj' },
        @{ f = 'composer.json';     n = 'PHP';            c = 'composer install; vendor/bin/phpunit';                  d = 'vendor' },
        @{ f = 'Gemfile';           n = 'Ruby';           c = 'bundle exec rake test (or rspec)';                      d = 'vendor','tmp','log' }
    )
    $skip = 'node_modules','target','dist','build','bin','obj','venv','vendor'
    $dirs = @(Get-Item $root) + @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike '.*' -and $_.Name -notin $skip })
    $found = @(foreach ($d in $dirs) { foreach ($s in $stacks) {
        if (Get-ChildItem -Path $d.FullName -Filter $s.f -File -ErrorAction SilentlyContinue | Select-Object -First 1) {
            $rel = if ($d.FullName -eq $root) { '.' } else { $d.Name }
            [pscustomobject]@{ Rel = $rel; Name = $s.n; Cmds = $s.c; Deny = $s.d }
        } } })
    $found = @($found | Sort-Object Rel, Name -Unique)
    $repos = @($found | Where-Object { $_.Rel -ne '.' } | Select-Object -ExpandProperty Rel -Unique)
    $isWorkspace = -not ($found | Where-Object { $_.Rel -eq '.' }) -and $repos.Count -gt 0

    function Write-Starter($Path, $Text) {
        if ((Test-Path $Path) -and -not $Force) { Write-Host "Kept existing $Path (use -Force to replace)."; return }
        Save $Path $Text 'project CLAUDE.md'
    }
    function New-RepoMd($Name, $Items) {
        $stack = if ($Items) { ($Items | ForEach-Object { if ($_.Rel -eq '.') { "- $($_.Name)" } else { "- $($_.Rel): $($_.Name)" } }) -join "`n" } else { '- (no known stack detected)' }
        $cmds  = if ($Items) { ($Items | ForEach-Object { if ($_.Rel -eq '.') { "- $($_.Cmds)" } else { "- $($_.Rel): $($_.Cmds)" } }) -join "`n" } else { '- (build, test, run commands)' }
        (Read-Template 'project\CLAUDE.md').Replace('{{NAME}}', $Name).Replace('{{STACK}}', $stack).Replace('{{COMMANDS}}', $cmds)
    }

    $rootName = Split-Path $root -Leaf
    if ($isWorkspace) {
        $list = ($repos | ForEach-Object { $r = $_; "- ${r}/: " + (($found | Where-Object { $_.Rel -eq $r } | ForEach-Object { $_.Name }) -join ', ') }) -join "`n"
        Write-Starter (Join-Path $root 'CLAUDE.md') (Read-Template 'project\WORKSPACE.md').Replace('{{NAME}}', $rootName).Replace('{{REPOS}}', $list)
        foreach ($r in $repos) {
            $items = @($found | Where-Object { $_.Rel -eq $r } | ForEach-Object { [pscustomobject]@{ Rel = '.'; Name = $_.Name; Cmds = $_.Cmds } })
            Write-Starter (Join-Path $root "$r\CLAUDE.md") (New-RepoMd $r $items)
        }
    } else {
        Write-Starter (Join-Path $root 'CLAUDE.md') (New-RepoMd $rootName $found)
    }

    # project settings: deny build output and dependencies of every detected stack, at their exact place
    $deny = @('Read(./**/*.log)', 'Read(./**/.idea/**)') + @($found | ForEach-Object {
        $prefix = if ($_.Rel -eq '.') { './' } else { "./$($_.Rel)/" }
        foreach ($x in $_.Deny) { "Read($prefix$x/**)" } } | Select-Object -Unique)
    Merge-Settings (Join-Path $root '.claude\settings.json') ([ordered]@{
        '$schema'   = 'https://json.schemastore.org/claude-code-settings.json'
        permissions = [ordered]@{ deny = @($deny) } })

    # keep Claude files out of git, in every repo found (root or direct subfolders)
    if (-not $Share) {
        foreach ($d in $dirs) {
            if (-not (Test-Path (Join-Path $d.FullName '.git'))) { continue }
            $ex = Join-Path $d.FullName '.git\info\exclude'
            $cur = if (Test-Path $ex) { @(Get-Content $ex) } else { @() }
            $add = @('CLAUDE.md', 'CLAUDE.local.md', '.claude/', '.mcp.json') | Where-Object { $cur -notcontains $_ }
            if ($add) {
                New-Item -ItemType Directory -Force -Path (Split-Path $ex) | Out-Null
                Add-Content -Path $ex -Value $add; $Changes.Add("git exclude: $ex")
            }
        }
    }
}

# ---------- 7. summary ----------
Write-Host "`nDone." -ForegroundColor Green
if ($Changes.Count) { $Changes | ForEach-Object { Write-Host "  - $_" } } else { Write-Host '  Nothing to change, everything is up to date.' }
if (Test-Path $BackupDir) { Write-Host "Backups: $BackupDir" }

if ($Project -and $Complete) {
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Write-Warning 'claude not found in this terminal: open a new one, cd to the project and run: claude "/project-setup"' }
    else {
        Write-Host "`nOpening Claude in $root to complete the project files..."
        Push-Location $root
        try { claude '/project-setup' } finally { Pop-Location }
    }
} else {
    Write-Host @"

Next steps:
  - Open a NEW terminal so 'claude' and 'claude-setup' are on the PATH, then: claude doctor
  - Set up a project:   claude-setup -Project <folder> -Complete
  - Inside Claude Code: /memory shows the rules, /project-setup completes or refreshes the project files
  - Update this setup:  claude-setup -Update
"@
}
