#!/usr/bin/env bash
#
# sync_from_upstream.sh
#
# One-shot sync for this fork: pull upstream changes, reapply our
# customization patches idempotently, commit, and push to origin.
#
# Remote layout assumed:
#   upstream  ->  alirezarezvani/claude-skills  (source of truth for the
#                                                community library)
#   origin    ->  DatflowDev/claude-skills      (this fork, pulled by
#                                                every machine we run on)
#
# Flow:
#   1. git fetch upstream
#   2. git merge --no-edit upstream/<branch> (current branch)
#      - conflicts fail loudly; resolve by hand if that happens
#   3. scripts/patches/apply_team_capable.py
#      - reapplies `team_capable: true` and the teammate tool set on
#        every cs-* agent, in case the upstream merge reverted them
#   4. scripts/patches/symlink_claude_config.sh
#      - reconverges ~/.claude/{agents,commands} symlinks so any newly
#        added agent dir or command file is picked up automatically
#   5. if the patches produced any diff, commit it
#   6. git push origin HEAD
#
# Safe to rerun. On a clean already-synced tree every step is a no-op.
#
# Usage:
#   scripts/patches/sync_from_upstream.sh
#   scripts/patches/sync_from_upstream.sh --no-push   # skip the push step
#   scripts/patches/sync_from_upstream.sh --dry-run   # fetch + status only
#
# Env:
#   UPSTREAM_BRANCH   override default upstream branch (default: main)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
DO_PUSH=1
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --no-push)  DO_PUSH=0 ;;
        --dry-run)  DRY_RUN=1 ;;
        *) echo "unknown flag: $arg"; exit 2 ;;
    esac
done

require_remote() {
    local name="$1"
    if ! git remote get-url "$name" >/dev/null 2>&1; then
        echo "ERROR: git remote '$name' not configured" >&2
        echo "  run:  git remote add $name <url>" >&2
        exit 1
    fi
}

require_clean_tree() {
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "ERROR: working tree has uncommitted changes" >&2
        git status --short >&2
        exit 1
    fi
}

require_remote upstream
require_remote origin
require_clean_tree

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo "== branch: $BRANCH =="

echo "== fetch upstream =="
git fetch upstream

if (( DRY_RUN )); then
    echo "== dry-run: upstream/$UPSTREAM_BRANCH vs HEAD =="
    git log --oneline "HEAD..upstream/$UPSTREAM_BRANCH" || true
    exit 0
fi

echo "== merge upstream/$UPSTREAM_BRANCH =="
if ! git merge --no-edit "upstream/$UPSTREAM_BRANCH"; then
    echo "ERROR: merge conflicts — resolve manually, then rerun this script" >&2
    exit 1
fi

echo "== reapply: apply_team_capable.py =="
python3 "$SCRIPT_DIR/apply_team_capable.py"

echo "== reapply: symlink_claude_config.sh =="
"$SCRIPT_DIR/symlink_claude_config.sh"

if ! git diff --quiet; then
    echo "== commit reapplied fork patches =="
    git add -A
    git commit -m "chore(fork): reapply customization patches after upstream sync"
else
    echo "== no patch drift to commit =="
fi

if (( DO_PUSH )); then
    echo "== push origin/$BRANCH =="
    git push origin "$BRANCH"
fi

echo "done"
