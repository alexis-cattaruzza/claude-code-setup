# Base rules (all projects)

## Workflow
- Understand before changing: read the relevant code, ask when the request is ambiguous.
- For changes touching several files, give a short plan first.
- Root cause first, then the fix. No speculative fixes.

## Code
- Minimal diffs that follow the existing patterns and style of the project.
- Verify names, signatures and schemas in the source before using them. Never guess.
- No new dependency, framework or abstraction without asking.
- No unrelated refactoring or reformatting.
- Do not add comments that only restate the code.

## Verification
- Before saying done, run what the project has (build, tests, linter, type check) and say what ran and what did not.
- Review failure cases: empty or invalid input, timeouts, duplicates, missing config, and what the user sees.

## Tokens
- Locate code with grep/glob or the code-finder agent, then read only the needed line ranges.
- Never read build output, dependencies, lock files, generated code or logs in full.
- Answers short and direct, with exact file:line locations.

## Project files
- Project specifics live in the project CLAUDE.md. If it is missing or still has "(...)" placeholders, suggest running /project-setup.

## Git and safety
- Never commit, push or open a PR/MR without explicit approval. Leave changes uncommitted.
- Never print, copy or commit secrets (.env, keys, tokens, passwords).
- Never run destructive commands (rm -rf, force push, hard reset, dropping data) without approval.
