#!/usr/bin/env bash
#
# symlink_claude_config.sh
#
# Idempotent patch that mirrors this repo's agents/ and commands/ into
# ~/.claude/ via symlinks. Run after every `git pull` to pick up any
# newly added agent directories or command files.
#
# Layout:
#   agents/<subdir>/  ->  ~/.claude/agents/<subdir>   (one symlink per subdir)
#   commands/*.md     ->  ~/.claude/commands/*.md     (one symlink per file)
#
# Local-only items in ~/.claude/ are preserved — the script only touches
# names that have a matching source in this repo. Anything else (e.g.
# ~/.claude/agents/personas, ~/.claude/commands/README.md,
# ~/.claude/commands/git/) is left alone.
#
# Why a script and not a git .patch?
#   A .patch fails on any upstream line drift. This script is state-aware
#   and idempotent: rerun it anytime, it converges on the desired layout
#   without conflicts.
#
# Usage:
#   scripts/patches/symlink_claude_config.sh
#   scripts/patches/symlink_claude_config.sh --check   # dry-run, exit 2 on drift
#
# Env:
#   CLAUDE_HOME   override ~/.claude (default: $HOME/.claude)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"

CHECK=0
if [[ "${1:-}" == "--check" ]]; then
    CHECK=1
fi

drift=0

link_item() {
    local src="$1"
    local dest="$2"

    if [[ -L "$dest" ]]; then
        local current
        current="$(readlink "$dest")"
        if [[ "$current" == "$src" ]]; then
            echo "  ok       $dest"
            return
        fi
    fi

    if (( CHECK )); then
        echo "  would    $dest -> $src"
        drift=1
        return
    fi

    rm -rf -- "$dest"
    ln -s "$src" "$dest"
    echo "  linked   $dest -> $src"
}

echo "== agents =="
mkdir -p "$CLAUDE_HOME/agents"
for sub in "$REPO_ROOT"/agents/*/; do
    [[ -d "$sub" ]] || continue
    name="$(basename "$sub")"
    link_item "$REPO_ROOT/agents/$name" "$CLAUDE_HOME/agents/$name"
done

echo "== commands =="
mkdir -p "$CLAUDE_HOME/commands"
for file in "$REPO_ROOT"/commands/*.md; do
    [[ -f "$file" ]] || continue
    name="$(basename "$file")"
    link_item "$REPO_ROOT/commands/$name" "$CLAUDE_HOME/commands/$name"
done

if (( CHECK )) && (( drift )); then
    echo "drift detected"
    exit 2
fi

echo "done"
