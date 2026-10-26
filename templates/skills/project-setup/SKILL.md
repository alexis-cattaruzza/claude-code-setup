---
name: project-setup
description: Create or refresh the Claude Code files of the current project (CLAUDE.md for the workspace and each repo, .claude/settings.json deny list) from the actual code. Use when the user asks to set up, complete or refresh the project CLAUDE.md or the Claude setup of a project.
---

# Project setup

Goal: CLAUDE.md files that tell Claude what it cannot quickly guess from the code, all verified in the source. Short beats complete.

## 1. Find the files
- The current folder is the project root. Read ./CLAUDE.md and .claude/settings.json if they exist.
- Workspace (no build file at the root, several repos below it): one CLAUDE.md at the root for cross-repo rules, plus one CLAUDE.md in each repo.
- Single repo: one CLAUDE.md at the root.

## 2. Explore cheaply
- Build files (pom.xml, package.json, build.gradle*, pyproject.toml, go.mod, Cargo.toml, *.csproj...) for stack, versions and scripts.
- Directory tree 2 to 4 levels deep, names only, to map the layout.
- Grep, do not read whole files: entry points, routing or controllers, response wrappers, exception handling, config and profile files (keys only, never values), migration folders and their naming, CI files, README.
- git log --oneline -15 in each repo for the ticket key and branch conventions.
- Never read dependencies, build output, vendored libraries, lock files or secrets.

## 3. Write or refresh
- Replace starter placeholders "(...)" with facts. Delete sections that stay empty.
- Keep existing hand-written lines unless the code proves them wrong; then fix them and say so.
- Repo file: one-line purpose and stack; layout map (folder: role); key flows and where they live; conventions with exact class and function names; environments and settings never to change without asking; database migration rule (folder, naming, how to pick the next number); commands as the repo really runs them (build, one test, run, lint); do-not-touch list.
- Workspace file: the repos and their roles, how they talk (API base path, shared models), the order of a full-stack change, running git with git -C <repo>.
- Aim for 30 to 80 lines per file. Exact names and paths, no generic advice (that lives in ~/.claude/CLAUDE.md), no secrets, no URLs with credentials.
- Write in the language of the existing files, English by default.

## 4. Settings
- If you found large generated or vendored folders that are not denied yet, list the Read(...) deny entries to add to .claude/settings.json and ask before editing it.

## 5. Report
- Files written, one line each.
- Open questions: what you could not verify in the code (team rules such as the deployment process, who applies database scripts, environment specifics). Ask them, then add the answers to the files.
