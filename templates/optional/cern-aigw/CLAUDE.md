## Delegation to CERN models (free, weaker)
Delegate with the delegate-cern-aigw skill only tasks that read a lot, return little and are easy to check:
- summarise long logs, stack trace dumps, test or build output
- first drafts of tickets, comments and messages; translations
- generate test data, sample JSON, SQL inserts from a given schema
- explain an unfamiliar library or generated file
- When you delegate (CERN worker or a subagent), start your answer with one line: "Delegated to <worker/agent> on <model>", taken from the command output, not guessed.

How:
- On the real working copy (read-only): cern-aigw delegate --host claude --access read-only --project <workspace root> --prompt-file <tmp file> --model glm-5.3-flash-int4 --effort configured --deadline-minutes 15
  (the only tested model that works with --host claude; other models need --host opencode on a disposable copy)
- Prompt: exact file paths, the question, "answer in under 20 lines".
- Non-zero exit code: report it in one line, then do the task yourself. Never retry automatically.
- Verify the worker's answer before using it.

Never delegate: root-cause analysis, design, state machine or guard logic, config or credentials, anything shipped without review.
Edits to source files only through /aigw-orchestrate below.

## CERN AI Gateway workers (optional module)
- `/aigw-orchestrate <ticket or task>`: Claude plans, splits and reviews; gateway models read and edit a disposable
  git worktree mirror; the reviewed patch is applied to the working copy, uncommitted. Edits never reach the working
  copy without Claude's review.
- Workers on a mirror always use `--host opencode`: `--host claude` adds about 37k tokens per call and fails with
  most gateway models. OpenCode has no read-only mode, so it only runs on a mirror or a disposable copy.
- Max 3 workers in parallel. One writer per repo or per disjoint file set.
- Worker model: `aigw.sh pick` (first available of GLM-5.3-FP8-VERTEX, MIMO-V2.6-FLASH-MOPD-VERTEX, glm-5.3-flash-int4).
  Small models (gemma-4-12b, gpt-oss-20b, hf-qwen3-32b-awq) only for short text tasks, never for code.
