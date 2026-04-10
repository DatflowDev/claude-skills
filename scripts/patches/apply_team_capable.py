#!/usr/bin/env python3
"""
apply_team_capable.py

Idempotent patch that brings every cs-* orchestration agent under
agents/ into the expected state for team participation:

  1. tools array set to the teammate tool set (no coordinator tools)
  2. team_capable: true flag present in frontmatter

Files whose frontmatter declares `subagent: true` are skipped — they
are read-only or narrow-utility agents that should not participate
as first-class teammates.

Why a Python script and not a git .patch file?
-----------------------------------------------
A .patch fails if upstream touches the same lines. This script is
line-aware and idempotent: rerun it after any `git pull` from the
source repo and it will re-converge on the expected state without
conflicts. Files already correct are left untouched.

Usage
-----
    python scripts/patches/apply_team_capable.py            # apply
    python scripts/patches/apply_team_capable.py --check    # dry-run

Exit codes
----------
    0  all files converged (patched or already correct)
    1  error
    2  --check mode found files that would be modified
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
AGENTS_DIR = REPO_ROOT / "agents"

EXPECTED_TOOLS = (
    "[Read, Write, Edit, Bash, Grep, Glob, "
    "SendMessage, TaskList, TaskGet, TaskUpdate]"
)
EXPECTED_TOOLS_LINE = f"tools: {EXPECTED_TOOLS}"
EXPECTED_TEAM_CAPABLE_LINE = "team_capable: true"

TOOLS_LINE_RE = re.compile(r"^tools:\s*\[.*\]\s*$")
TEAM_CAPABLE_RE = re.compile(r"^team_capable:\s*\S+\s*$")
SUBAGENT_RE = re.compile(r"^subagent:\s*true\s*$", re.IGNORECASE)
FRONTMATTER_DELIM = "---"


def split_frontmatter(text: str):
    """Return (frontmatter_lines, body_lines) or None if no frontmatter."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != FRONTMATTER_DELIM:
        return None
    for i in range(1, len(lines)):
        if lines[i].strip() == FRONTMATTER_DELIM:
            return lines[1:i], lines[i + 1:]
    return None


def is_subagent(fm_lines):
    return any(SUBAGENT_RE.match(line) for line in fm_lines)


def patch_frontmatter(fm_lines):
    """
    Return (new_fm_lines, changed_bool).

    - Replace or append the `tools:` line so it matches EXPECTED_TOOLS_LINE.
    - Ensure `team_capable: true` is present.
    """
    new_fm = list(fm_lines)
    changed = False

    # Normalize tools line
    tools_idx = next(
        (i for i, ln in enumerate(new_fm) if TOOLS_LINE_RE.match(ln)),
        None,
    )
    if tools_idx is None:
        new_fm.append(EXPECTED_TOOLS_LINE)
        changed = True
    elif new_fm[tools_idx].strip() != EXPECTED_TOOLS_LINE:
        new_fm[tools_idx] = EXPECTED_TOOLS_LINE
        changed = True

    # Ensure team_capable: true
    tc_idx = next(
        (i for i, ln in enumerate(new_fm) if TEAM_CAPABLE_RE.match(ln)),
        None,
    )
    if tc_idx is None:
        new_fm.append(EXPECTED_TEAM_CAPABLE_LINE)
        changed = True
    elif new_fm[tc_idx].strip() != EXPECTED_TEAM_CAPABLE_LINE:
        new_fm[tc_idx] = EXPECTED_TEAM_CAPABLE_LINE
        changed = True

    return new_fm, changed


def process_file(path: Path, check_only: bool):
    text = path.read_text(encoding="utf-8")
    parsed = split_frontmatter(text)
    if parsed is None:
        return "no-frontmatter"
    fm, body = parsed

    if is_subagent(fm):
        return "skipped-subagent"

    new_fm, changed = patch_frontmatter(fm)
    if not changed:
        return "already-patched"

    if check_only:
        return "would-patch"

    new_text = "\n".join(
        [FRONTMATTER_DELIM, *new_fm, FRONTMATTER_DELIM, *body]
    )
    if text.endswith("\n"):
        new_text += "\n"
    path.write_text(new_text, encoding="utf-8")
    return "patched"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Dry-run. Exit 2 if any file would be modified.",
    )
    args = parser.parse_args()

    if not AGENTS_DIR.is_dir():
        print(f"ERROR: agents dir not found: {AGENTS_DIR}", file=sys.stderr)
        return 1

    files = sorted(AGENTS_DIR.rglob("cs-*.md"))
    if not files:
        print("ERROR: no cs-*.md files found under agents/", file=sys.stderr)
        return 1

    results: dict[str, list[Path]] = {}
    for f in files:
        status = process_file(f, check_only=args.check)
        results.setdefault(status, []).append(f.relative_to(REPO_ROOT))

    for status in sorted(results):
        paths = results[status]
        print(f"{status}: {len(paths)}")
        for p in paths:
            print(f"  {p}")

    if args.check and "would-patch" in results:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
