#!/usr/bin/env python3
"""Regression guard for the subagent output-budget contract.

Every subagent handoff is injected verbatim into the operator's context and is
re-sent on every later turn, so an unbounded handoff is a cost multiplier, not a
style issue. On engagements/2026-09-23-235052-172-20-0-2 five subagent handoffs
of 20k-30k characters each pushed the run to 8.7M cache-read tokens.

Run after editing prompts with:
    scripts/apply_subagent_output_contract.sh

Written as a plain script (no pytest) so auditor cycles can run it with the
system Python, matching check_operator_prompt_contract.py.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
PROMPT_DIR = ROOT / ".opencode" / "prompts" / "agents"

BEGIN_MARK = (
    "<!-- BEGIN subagent-output-contract "
    "(managed by scripts/apply_subagent_output_contract.sh) -->"
)
END_MARK = "<!-- END subagent-output-contract -->"

# Rendered from operator-core.md, not managed by apply_subagent_output_contract.sh.
OPERATOR_PROMPTS = {"operator.txt"}

REQUIRED_IN_SUBAGENT = [
    "=== OUTPUT BUDGET (HARD LIMIT) ===",
    "At most 40 lines of markdown and at most 3000 characters",
    "### Case Outcomes",
    "$DIR/scans/<case-id>-<slug>.md",
    "A long handoff is a defect in",
]

REQUIRED_IN_OPERATOR = [
    "Subagent Output Budget",
    "8.7M cache-read tokens",
    "A subagent handoff longer than 40 lines is a contract violation",
]


def iter_prompts() -> list[Path]:
    return sorted(p for p in PROMPT_DIR.glob("*.txt"))


def main() -> int:
    if not PROMPT_DIR.is_dir():
        print(f"prompt dir missing: {PROMPT_DIR.relative_to(ROOT)}", file=sys.stderr)
        return 1

    failures: list[str] = []
    prompts = iter_prompts()
    if not prompts:
        print("no subagent prompt files found", file=sys.stderr)
        return 1

    for path in prompts:
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)
        if path.name in OPERATOR_PROMPTS:
            for snippet in REQUIRED_IN_OPERATOR:
                if snippet not in text:
                    failures.append(f"{rel} missing operator-side snippet {snippet!r}")
            continue

        if BEGIN_MARK not in text or END_MARK not in text:
            failures.append(
                f"{rel} missing managed contract block "
                f"(run scripts/apply_subagent_output_contract.sh)"
            )
            continue
        if text.index(BEGIN_MARK) > text.index(END_MARK):
            failures.append(f"{rel} contract markers are inverted")

        for snippet in REQUIRED_IN_SUBAGENT:
            if snippet not in text:
                failures.append(f"{rel} missing contract text {snippet!r}")

    if failures:
        print("subagent output contract failures:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("subagent output contract ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
