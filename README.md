# claude-code-setup

One command to set up [Claude Code](https://code.claude.com) on any Windows machine, and one command to set up any project (new or existing, any stack, single repo or workspace of several repos).

It gives you:
- **Global rules** that make Claude work carefully and spend fewer tokens: understand before changing, minimal diffs, verify before "done", targeted reads, no commits or pushes without your approval, no secrets.
- **Safe default settings**: asks before `git commit` and `git push`, blocks force-push, hard reset and reading `.env` or key files.
- **A cheap search agent** (`code-finder`, runs on Haiku) that locates code without filling your context.
- **A `/project-setup` skill** that lets Claude complete or refresh a project's `CLAUDE.md` files from the real code.
- **A `claude-setup` command** available in every terminal, so you can run the setup from anywhere.

Nothing is overwritten blindly: files are only written when their content changes, the old version is backed up, your own `CLAUDE.md` lines are kept, and settings are merged.

## Quick start

```powershell
# 1. New machine (once): installs Git and Claude Code if missing, then the global setup
irm https://raw.githubusercontent.com/alexis-cattaruzza/claude-code-setup/main/bootstrap.ps1 | iex

# 2. Open a NEW terminal, then set up a project (once per project)
claude-setup -Project C:\path\to\project -Complete

# 3. Later: get the latest version of this setup
claude-setup -Update
```

That is all most people need. The rest of this page explains each step and every option.

## Requirements

- Windows 10/11 with PowerShell 5.1 (built in) or PowerShell 7
- A Claude Pro, Max, Team or Enterprise account
- Git (installed automatically with winget by the bootstrap if missing)

No admin rights are needed. If Claude Code is not installed, the script installs it with the official installer.

## 1. Set up a machine

```powershell
irm https://raw.githubusercontent.com/alexis-cattaruzza/claude-code-setup/main/bootstrap.ps1 | iex
```

This clones the repo to `~/.claude-setup` (or updates it if it is already there) and runs `install.ps1`. Then open a **new** terminal: `claude` and `claude-setup` now work everywhere. Check with `claude doctor`.

The one-liner cannot take options. Add them afterwards with `claude-setup`, for example `claude-setup -NoAttribution -Rules C:\path\my-rules.md`.

Manual alternative (or to work on the setup itself):

```powershell
git clone https://github.com/alexis-cattaruzza/claude-code-setup.git $HOME\.claude-setup
powershell -ExecutionPolicy Bypass -File $HOME\.claude-setup\install.ps1
```

`claude-setup` always points to the copy of the repo that ran last.

## 2. Set up a project

```powershell
claude-setup -Project C:\path\to\project -Complete
```

1. The script detects the stack, writes starter `CLAUDE.md` files, blocks reads of build and dependency folders, and hides Claude files from git.
2. `-Complete` then opens Claude in the project and runs `/project-setup`: Claude explores the code, fills the `CLAUDE.md` files with verified facts, and asks you what it could not find (deployment process, team rules...).

Workspaces are handled: if the folder has no build file but its subfolders do (for example `backend/` and `frontend/`), you get one workspace `CLAUDE.md` for cross-repo rules plus one `CLAUDE.md` per repo. Always start `claude` from the workspace folder.

Without `-Complete`, run `/project-setup` yourself later inside Claude Code. Run it again anytime to refresh the files after big changes.

## 3. Update

```powershell
claude-setup -Update
```

Pulls the latest version of this repo and re-applies it with your remembered options. Only what changed is rewritten.

## How existing files are updated

The generic rules live only in the global `~/.claude/CLAUDE.md`, which Claude Code loads in every project. They are never copied into project files.

| File | First run | Later runs |
| --- | --- | --- |
| `~/.claude/CLAUDE.md` | Your content is kept. The base rules are appended between `<!-- claude-code-setup:base:begin -->` and `<!-- claude-code-setup:base:end -->`. | Only the text between the markers is replaced with the latest rules. Everything outside them stays as you wrote it. Same for the `personal` block with `-Rules`. |
| `~/.claude/settings.json` | Base permissions are merged in. | Same merge: your existing values win, lists are combined, nothing is removed. |
| `~/.claude/agents/code-finder.md`, `~/.claude/skills/project-setup/SKILL.md` | Created. | Replaced by the latest version (old one backed up). Do not edit them, edit `templates/` instead. |
| `<project>/CLAUDE.md` | Starter written only if the file does not exist. | Never touched, unless `-Force` (replaced by the starter, backup kept). Use `/project-setup` to update it from the code: it keeps your hand-written lines. |
| `<project>/.claude/settings.json` | Read blocks for build and dependency folders merged in. | Same merge, your entries are kept. |

## All options

```
claude-setup [-Project <folder>] [-Complete] [-Rules <file or URL>] [-NoAttribution]
             [-Force] [-Share] [-Update] [-SkipClaudeInstall]
```

Before `claude-setup` exists, use `powershell -ExecutionPolicy Bypass -File install.ps1` with the same options.

| Option | Effect | Remembered |
| --- | --- | --- |
| *(none)* | Global setup only: installs or refreshes the global rules, settings, agent, skill and the `claude-setup` command | |
| `-Project <folder>` | Also set up that project or workspace. `.` means the current folder | |
| `-Complete` | With `-Project`: afterwards, open Claude in the project and run `/project-setup` | |
| `-Rules <file or URL>` | Install your personal rules (any `.md` file) in a `personal` block of `~/.claude/CLAUDE.md`. Later runs re-read the file, so edit the file and run `claude-setup` | yes |
| `-NoAttribution` | No "Co-Authored-By: Claude" in commits and PRs | yes |
| `-Force` | With `-Project`: replace existing project `CLAUDE.md` files with the starter (a backup is kept) | |
| `-Share` | With `-Project`: do not hide Claude files from git, for teams that commit them | |
| `-Update` | `git pull` this repo first, then run with the other options given | |
| `-SkipClaudeInstall` | Do not install Claude Code if it is missing | |

Remembered options are stored in `~/.claude/claude-code-setup.json`. To forget one, delete its line there.

### Examples

```powershell
claude-setup                                           # refresh the global setup
claude-setup -Project .                                # set up the current folder, complete it later with /project-setup
claude-setup -Project C:\code\shop -Complete           # set up and let Claude complete the files now
claude-setup -Project C:\code\shop -Force -Complete    # restart a project's CLAUDE.md files from scratch
claude-setup -Project C:\code\team-app -Share          # team repo where CLAUDE.md is committed
claude-setup -Rules C:\Users\me\OneDrive\claude-rules.md -NoAttribution   # personal rules, no Claude trace in commits
claude-setup -Update                                   # latest version of this setup
```

## What it changes

| File | What happens |
| --- | --- |
| `~/.claude/CLAUDE.md` | `base` block (and `personal` block with `-Rules`) added or refreshed |
| `~/.claude/settings.json` | Base permissions merged in |
| `~/.claude/agents/code-finder.md` | Search agent, available in every project |
| `~/.claude/skills/project-setup/SKILL.md` | The `/project-setup` skill |
| `~/.claude/claude-code-setup.json` | Remembered options |
| `~/.local/bin/claude-setup.cmd` | The `claude-setup` command (folder added to your user PATH) |
| `<project>/CLAUDE.md` (and `<repo>/CLAUDE.md` in a workspace) | Starter files, only if none exist |
| `<project>/.claude/settings.json` | Blocks reads of build output and dependencies of the detected stacks |
| `<repo>/.git/info/exclude` | Hides `CLAUDE.md`, `CLAUDE.local.md`, `.claude/` and `.mcp.json` from git (skipped with `-Share`) |

`~` is your user folder, for example `C:\Users\<you>`.

Detected stacks: Node/JS/TS, Maven, Gradle, Python, Go, Rust, .NET, PHP, Ruby. Other stacks still get starter files; `/project-setup` fills them in.

## Customising

- **Generic rules for everyone**: edit `templates/` in this repo, then `claude-setup`.
- **Your personal rules** (company tools, names, language preferences): keep them in a private file and pass `-Rules <file>`, or write them in `~/.claude/CLAUDE.md` outside the marked blocks. Never put them in this public repo.
- **Project rules**: in the project `CLAUDE.md`, kept short since it is loaded in every session.
- **Personal rules for one project**: `CLAUDE.local.md` in the project.

## Undo

Every changed file is backed up to `~/.claude/backups/claude-code-setup-<date-time>/`, with an `index.txt` giving each file's original path. Copy the files back to restore. To remove the rules only, delete the blocks between the `<!-- claude-code-setup:...:begin -->` and `...:end -->` markers in `~/.claude/CLAUDE.md`.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `claude` or `claude-setup` is not recognized | Open a new terminal. If it persists, check that `%USERPROFILE%\.local\bin` is in your user PATH |
| "running scripts is disabled" | Use `claude-setup`, or `powershell -ExecutionPolicy Bypass -File install.ps1` |
| "Invalid JSON in ...settings.json" | Fix or delete that file (a backup is in `~/.claude/backups`), then re-run |
| Project rules not loaded | Start `claude` from the project folder, then check `/memory` |
| `/project-setup` not found | Run `claude-setup` once, then restart Claude Code |
| `-Update` fails | You have local changes in the setup repo: commit or discard them, then retry |

## Tips to save tokens

- One task per session, `/clear` before the next one.
- Point Claude at the exact file or method, or select the code in your IDE.
- Paste only the relevant part of a stack trace.
- `/context` shows what is filling the context; `/compact` shrinks a long session.
