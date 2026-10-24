# claude-code-setup

A one-command baseline setup for [Claude Code](https://code.claude.com) on any machine and any coding project (web, Java, Python, Go, Rust, .NET...).

It gives you:
- **Global rules** that make Claude work carefully and spend fewer tokens: understand before changing, minimal diffs, verify before "done", targeted reads, no commits or pushes without your approval, no secrets.
- **Safe default settings**: asks before `git commit` and `git push`, blocks force-push, hard reset and reading `.env` or key files.
- **A cheap search agent** (`code-finder`, runs on Haiku) that locates code without filling your context.
- **Per-project setup**: detects the stack, writes a starter `CLAUDE.md`, blocks reads of build and dependency folders, and keeps Claude files out of git.

Nothing is overwritten blindly: existing files are backed up, your own `CLAUDE.md` lines are kept, and settings are merged.

## Requirements

- Windows 10/11 with PowerShell 5.1 (built in) or PowerShell 7
- A Claude Pro, Max, Team or Enterprise account (the free plan has no Claude Code)
- Recommended: [Git for Windows](https://git-scm.com/downloads/win)

No admin rights are needed. If Claude Code is not installed, the script installs it with the official installer.

## Quick start

### 1. Set up your machine (once)

```powershell
git clone <repo-url>
cd claude-code-base
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

`-ExecutionPolicy Bypass` applies to this run only. It does not change your machine's policy.

### 2. Set up a project (once per project)

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Project C:\path\to\your\project
```

The folder can be a single repo or a workspace holding several repos (for example a backend and a frontend side by side). The script looks at the folder and its direct subfolders.

### 3. Start working

1. Open a **new** terminal (so the PATH is refreshed).
2. Check the install: `claude doctor`
3. Go to your project and start Claude: `claude` (log in in the browser the first time).
4. Inside Claude Code:
   - `/memory` shows the rules that were installed
   - `/init` completes the project `CLAUDE.md` from your code

## Without cloning

If the repo is reachable without login:

```powershell
# machine setup
irm <raw-url>/install.ps1 | iex

# project setup (run from the project folder)
& ([scriptblock]::Create((irm <raw-url>/install.ps1))) -Project .
```

## Options

| Option | Effect |
| --- | --- |
| `-Project <folder>` | Also set up that project or workspace |
| `-Force` | Replace an existing project `CLAUDE.md` (a backup is kept) |
| `-Share` | Do not hide Claude files from git, for teams that commit them |
| `-NoAttribution` | Remove the "Co-Authored-By: Claude" line from commits and PRs |
| `-SkipClaudeInstall` | Do not install Claude Code if it is missing |

Example: `powershell -ExecutionPolicy Bypass -File .\install.ps1 -Project . -Force -NoAttribution`

## What it changes

| File | What happens |
| --- | --- |
| `~/.claude/CLAUDE.md` | A marked block with the base rules is added or refreshed. Your own lines outside the block are kept. |
| `~/.claude/settings.json` | Base permissions are merged in. Your existing values win; lists are combined. |
| `~/.claude/agents/code-finder.md` | Search agent, available in every project |
| `<project>/CLAUDE.md` | Starter file with the detected layout and commands (only if none exists, unless `-Force`) |
| `<project>/.claude/settings.json` | Blocks reads of build output and dependencies for the detected stacks |
| `<repo>/.git/info/exclude` | Hides `CLAUDE.md`, `CLAUDE.local.md`, `.claude/` and `.mcp.json` from git (skipped with `-Share`) |

`~` is your user folder, for example `C:\Users\<you>`. The script finds it automatically.

Detected stacks: Node/JS/TS (`package.json`), Maven (`pom.xml`), Gradle (`build.gradle*`), Python (`pyproject.toml`, `requirements*.txt`), Go (`go.mod`), Rust (`Cargo.toml`), .NET (`*.sln`, `*.csproj`).

## Update

```powershell
cd claude-code-base
git pull
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

The base block is refreshed; everything else you changed is kept. Running it several times never duplicates anything.

## Undo

Every run backs up the files it touches to:

```
~/.claude/backups/base-<date-time>/
```

Copy the files back to restore. To remove the base rules only, delete the block between `<!-- claude-code-base:begin -->` and `<!-- claude-code-base:end -->` in `~/.claude/CLAUDE.md`.

## Customising

- **Personal rules for all projects**: add them to `~/.claude/CLAUDE.md`, outside the marked block.
- **Project rules** (architecture, conventions, commands): put them in the project `CLAUDE.md`. Keep it under about 150 lines, since it is loaded in every session.
- **Personal rules for one project**: `CLAUDE.local.md` in the project (not shared).
- **Extra permissions**: edit `~/.claude/settings.json` or `<project>/.claude/settings.json`. Check with `/status` and `claude doctor`.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `claude` is not recognized | Open a new terminal. If it persists, run `claude doctor` from `%USERPROFILE%\.local\bin\claude.exe` |
| "running scripts is disabled" | Use `powershell -ExecutionPolicy Bypass -File .\install.ps1` as shown above |
| "Invalid JSON in ...settings.json" | Fix or delete that file (a backup is in `~/.claude/backups`), then re-run |
| Project rules not loaded | Start `claude` from the project folder, then check `/context` under Memory files |
| The install is blocked on a managed PC | Ask your IT service desk to allow the Claude Code installer |

## Tips to save tokens

- One task per session, `/clear` before the next one.
- Point Claude at the exact file or method, or select the code in your IDE.
- Paste only the relevant part of a stack trace.
- `/context` shows what is filling the context; `/compact` shrinks a long session.

## Contributing

Changes to the base rules affect everyone who uses this repo: keep them generic (no team- or project-specific rules) and open a merge request describing why.