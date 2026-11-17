---
name: aigw-orchestrate
description: Run a ticket or coding task with Claude as planner and reviewer and CERN AI Gateway models as workers that read and edit a disposable git worktree mirror. Use it without being asked when the task needs wide code reading (recon across many files or repos) or mechanical edits across about 3 or more files, once the design is clear. Do not use it for small fixes, single-file changes, or design and root-cause work.
argument-hint: <ticket key or task description>
---

# Orchestrate CERN AI Gateway workers

Goal: spend Claude tokens only on deciding, splitting and reviewing. Workers (free CERN gateway models) do the
reading and the editing. Workers never touch the user's working copy: they edit a mirror made of git worktrees,
and Claude applies the reviewed patch, uncommitted.

Script: `S=<this skill folder>/scripts/aigw.sh`, run with bash. Commands:
`prepare <workspace> <name>`, `pick`, `models`, `run <project> <model> <brief>...`, `status|diff|reset|apply|clean <mirror>`.
Env: `AIGW_MAX_PARALLEL` (default 3, more can exhaust RAM), `AIGW_DEADLINE` minutes (default 20),
`AIGW_MODELS` (preference order), `AIGW_HOME` (mirror root, default /tmp/aigw).

## 0. Input
- When started without the user typing the command, say so in one line first ("Using aigw-orchestrate: <why>").
- The argument is a ticket key or a task. Read `.claude/tickets/<key>.md` if it exists. There is no Jira access:
  if the ticket text is missing, ask the user to paste the description and decisions.
- Say in one line what will run (mirror name, model) and go.

## 1. Mirror and model
- `bash $S prepare <workspace root> <key>`: one worktree per repo at `$AIGW_HOME/<key>/<repo>`, starting from the
  current working copy (uncommitted changes and new files included), CLAUDE.md files copied, node_modules linked.
  It prints `PROJECT=<mirror>`: pass that folder as project to every worker.
- `MODEL=$(bash $S pick)`: first available of the preference order for this key.

## 2. Recon (worker)
Write a brief to `<mirror>/brief-recon.txt` and run it. Recon briefs ask for one line per item:
`<repo>/<path>:<line> | <symbol> | REMOVE / CHANGE / ADD / KEEP | <why, 10 words max>`, max 40 lines, only what was
seen in files, and must name look-alike features that must NOT change. After it: `bash $S status <mirror>`; if a
recon worker edited files, `bash $S reset <mirror>`.

## 3. Plan (Claude)
- Verify the recon: read only the risky line ranges it points to (shared methods, guards, state machine, texts).
  Grep for what recon may have missed (other callers, user texts, comments naming the feature).
- Decide. Root cause and design stay with Claude, never with a worker.
- Split into briefs that never overlap on a file: one per repo, or per disjoint file set. Max 3 in parallel.

Brief template (plain text, exact paths, no context the worker cannot see):
```
Ticket <key>. Edit ONLY files under <repo>/. Do not touch <other repos>. Do not run git commands. Do not build.
Goal: <one sentence>.
Tasks:
1. <path>: <exact change, symbol names>.
...
Keep: <symbols and look-alike features that must not change>.
Rules: follow the existing style, no new comments, remove imports that become unused, also update comments and
user texts that mention what changed.
Before finishing, grep <repo>/ for <old names>: no reference may remain.
Final answer: one line per file changed "<path>: <what changed>", max 15 lines.
```

## 4. Implement (workers)
`bash $S run <mirror> $MODEL <mirror>/brief-be.txt <mirror>/brief-fe.txt`. Each line reports exit code, time,
tokens and the answer file. Exit 0 ok, 2 bad input or config, 21 failed or incomplete, 22 deadline.
On failure: report it in one line. A rerun of the same brief with the next model of `pick`'s order is allowed once,
after telling the user. Never loop.

## 5. Review (Claude)
- Run the project's build, type check and tests inside the mirror (commands from the repo CLAUDE.md).
- `bash $S diff <mirror>` and read the patch files. Check against the plan: missing items, extra changes,
  unrelated reformatting, removed code still used, texts and comments left behind.
- Small fixes: edit the mirror directly. Bigger gaps: one more fix brief to a worker, then review again.

## 6. Hand over
- `bash $S apply <mirror>`: applies each repo patch to the real working copy, uncommitted. If a patch no longer
  applies, say so and keep the patch file.
- `bash $S clean <mirror>`: unlinks node_modules first, then removes the worktrees.
- Report: what changed per repo, what ran (build, tests) and what did not, worker models, times and gateway tokens.
  Nothing is committed or pushed.
