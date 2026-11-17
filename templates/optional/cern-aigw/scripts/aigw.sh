#!/usr/bin/env bash
# Worker plumbing for the aigw-orchestrate skill. Workers only ever edit a disposable git worktree mirror.
# Usage: aigw.sh prepare <workspace> <name> | models | pick | run <project> <model> <brief>... |
#        status <mirror> | diff <mirror> | reset <mirror> | apply <mirror> | clean <mirror>
set -u
MAXPAR="${AIGW_MAX_PARALLEL:-3}"
DEADLINE="${AIGW_DEADLINE:-20}"
ORDER="${AIGW_MODELS:-GLM-5.3-FP8-VERTEX MIMO-V2.6-FLASH-MOPD-VERTEX glm-5.3-flash-int4}"
ROOT="${AIGW_HOME:-/tmp/aigw}"
HERE="$(cd "$(dirname "$0")" && pwd)"
die() { echo "aigw: $*" >&2; exit 2; }
command -v cern-aigw >/dev/null || die "cern-aigw not found: install CERN AI Gateway Agents first"

py() {
    local d; d="$(dirname "$(command -v cern-aigw)")"
    for p in "$d/python.exe" "$d/python"; do [ -x "$p" ] && { "$p" -I "$@"; return; }; done
    die "cern-aigw runtime python not found next to $(command -v cern-aigw)"
}
winpath() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else echo "$1"; fi; }
link_dir() { # junction on Windows, symlink elsewhere; removed with unlink_dir only
    if command -v cygpath >/dev/null; then cmd //c mklink //J "$(winpath "$2")" "$(winpath "$1")" >/dev/null; else ln -s "$1" "$2"; fi
}
unlink_dir() { if command -v cygpath >/dev/null; then cmd //c rmdir "$(winpath "$1")"; else rm "$1"; fi; }
rows() { [ -f "$1/.aigw-map" ] || die "$1 is not a mirror made by prepare"; cat "$1/.aigw-map"; }

cmd_prepare() {
    local ws name m src rel wt
    ws="$(cd "${1:?workspace folder}" && pwd)"; name="${2:?mirror name, e.g. the ticket key}"; m="$ROOT/$name"
    [ -e "$m" ] && die "$m already exists: run clean first"
    local repos=()
    if git -C "$ws" rev-parse --show-toplevel >/dev/null 2>&1 && [ -e "$ws/.git" ]; then repos=("$ws")
    else for d in "$ws"/*/; do [ -e "$d.git" ] && repos+=("${d%/}"); done; fi
    [ ${#repos[@]} -gt 0 ] || die "no git repo in $ws or its direct subfolders"
    mkdir -p "$m" || die "cannot create $m"
    for f in CLAUDE.md CLAUDE.local.md; do [ -f "$ws/$f" ] && [ "${repos[0]}" != "$ws" ] && cp "$ws/$f" "$m/"; done
    [ -d "$ws/.claude" ] && [ "${repos[0]}" != "$ws" ] && cp -r "$ws/.claude" "$m/"
    for src in "${repos[@]}"; do
        rel="$(basename "$src")"; wt="$m/$rel"
        git -C "$src" worktree add -q --detach "$wt" HEAD || die "worktree add failed for $src"
        # the mirror starts from the working copy, uncommitted changes and new files included
        git -C "$src" diff --binary HEAD | git -C "$wt" apply --whitespace=nowarn 2>/dev/null
        git -C "$src" ls-files --others --exclude-standard -z | while IFS= read -r -d '' f; do
            mkdir -p "$wt/$(dirname "$f")"; cp "$src/$f" "$wt/$f"; done
        git -C "$wt" add -A
        local base; base="$(git -C "$wt" write-tree)"
        for f in CLAUDE.md CLAUDE.local.md; do [ -f "$src/$f" ] && [ ! -e "$wt/$f" ] && cp "$src/$f" "$wt/"; done
        [ -d "$src/.claude" ] && [ ! -e "$wt/.claude" ] && cp -r "$src/.claude" "$wt/"
        local links=""
        for dep in node_modules; do
            if [ -d "$src/$dep" ] && [ ! -e "$wt/$dep" ]; then link_dir "$src/$dep" "$wt/$dep" && links="$links $dep"; fi
        done
        printf '%s\t%s\t%s\t%s\n' "$wt" "$src" "$base" "${links# }" >> "$m/.aigw-map"
        echo "mirror: $wt <- $src$( [ -n "$links" ] && echo " (linked:$links)")"
    done
    echo "PROJECT=$m"
}

cmd_models() { py "$HERE/aigw_models.py"; }

cmd_pick() {
    local have; have="$(cmd_models)" || exit 2
    for m in $ORDER; do grep -qx "$m" <<<"$have" && { echo "$m"; return 0; }; done
    die "none of [$ORDER] is available to this key"
}

cmd_run() {
    local proj="${1:?project folder}" model="${2:?model id}"; shift 2
    [ $# -gt 0 ] || die "no brief file given"
    for b in "$@"; do [ -f "$b" ] || die "brief not found: $b"; done
    for b in "$@"; do
        while [ "$(jobs -rp | wc -l)" -ge "$MAXPAR" ]; do wait -n; done
        (
            st=$(date +%s); out="${b%.*}.out"
            cern-aigw delegate --host opencode --project "$proj" --prompt-file "$b" --model "$model" \
                --effort configured --deadline-minutes "$DEADLINE" > "$out" 2>&1
            rc=$?
            echo "$(basename "$b") | exit=$rc | $(( $(date +%s) - st ))s | $(grep -o 'tokens=[^;]*' "$out" || echo 'no usage') | answer: $out"
        ) &
    done
    wait
}

cmd_status() { rows "${1:?mirror}" | while IFS=$'\t' read -r wt src base links; do
    git -C "$wt" add -A; echo "== $(basename "$wt"): $(git -C "$wt" diff --cached --shortstat "$base" | sed 's/^ //')"
    git -C "$wt" diff --cached --name-status "$base"; done; }

cmd_diff() { local m="${1:?mirror}"; rows "$m" | while IFS=$'\t' read -r wt src base links; do
    git -C "$wt" add -A
    git -C "$wt" diff --cached --binary "$base" > "$m/$(basename "$wt").patch"
    echo "== $(basename "$wt"): $(git -C "$wt" diff --cached --shortstat "$base" | sed 's/^ //') -> $m/$(basename "$wt").patch"
    done; }

cmd_reset() { rows "${1:?mirror}" | while IFS=$'\t' read -r wt src base links; do
    git -C "$wt" read-tree "$base" && git -C "$wt" checkout-index -a -f && git -C "$wt" clean -fdq && echo "reset: $wt"; done; }

cmd_apply() { local m="${1:?mirror}" p; cmd_diff "$m" >/dev/null
    rows "$m" | while IFS=$'\t' read -r wt src base links; do
        p="$m/$(basename "$wt").patch"
        [ -s "$p" ] || { echo "== $(basename "$wt"): nothing to apply"; continue; }
        if git -C "$src" apply --check --whitespace=nowarn "$p"; then
            git -C "$src" apply --whitespace=nowarn "$p" && echo "== applied to $src (uncommitted)"
        else echo "== $src: patch does not apply (working copy changed since prepare?), kept $p"; fi
    done; }

cmd_clean() { local m="${1:?mirror}"; rows "$m" | while IFS=$'\t' read -r wt src base links; do
    for l in $links; do [ -e "$wt/$l" ] && unlink_dir "$wt/$l"; done
    for l in $links; do [ -e "$wt/$l" ] && die "could not unlink $wt/$l, stopping before removal"; done
    git -C "$src" worktree remove --force "$wt" && echo "removed: $wt"; done
    rm -f "$m/.aigw-map" "$m"/*.patch; echo "kept briefs and answers in $m (delete the folder when done)"; }

c="${1:-}"; shift || true
case "$c" in
    prepare|models|pick|run|status|diff|reset|apply|clean) "cmd_$c" "$@" ;;
    *) sed -n '3,4p' "$0"; exit 2 ;;
esac
