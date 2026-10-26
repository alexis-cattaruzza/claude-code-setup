# New machine: clones (or updates) this repo to ~/.claude-setup, then runs install.ps1.
# Public repo: irm https://raw.githubusercontent.com/alexis-cattaruzza/claude-code-setup/main/bootstrap.ps1 | iex
$ErrorActionPreference = 'Stop'
$repo = if ($env:CLAUDE_SETUP_REPO) { $env:CLAUDE_SETUP_REPO } else { 'https://github.com/alexis-cattaruzza/claude-code-setup.git' }
$dir  = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude-setup'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'Git is required: install it from https://git-scm.com/downloads/win and re-run.' }
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
    $env:Path += ';' + (Join-Path $env:ProgramFiles 'Git\cmd')
}
if (Test-Path (Join-Path $dir '.git')) { git -C $dir pull --ff-only } else { git clone $repo $dir }
if ($LASTEXITCODE) { throw "git failed for $repo" }
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir 'install.ps1')
