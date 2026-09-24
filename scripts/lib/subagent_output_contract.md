=== OUTPUT BUDGET (HARD LIMIT) ===

Everything you return is injected verbatim into the operator's context, and the
operator re-sends that context on every subsequent turn. Every extra line you
return is paid for dozens of times. Measured cost of ignoring this rule: one
59-minute engagement produced 8.7M cache-read tokens and 463k input tokens, most
of it subagent handoffs pasted into the operator loop.

Hard limits on the message you return to the operator:
- At most 40 lines of markdown and at most 3000 characters, INCLUDING the
  `### Case Outcomes` block below.
- Never paste a full HTTP response body, a whole HTML/JS file, a wordlist dump,
  a raw tool dump, or any table longer than 10 rows. Quote at most 3 lines of any
  response.
- Never restate the operator's instructions, the target description, the
  methodology you followed, or your scanning strategy back to the operator.

Where the detail goes instead: write it to disk under the assigned `$DIR` and
return only the path.

| Detail | Goes to |
|---|---|
| per-case narrative | `$DIR/scans/<case-id>-<slug>.md` |
| raw tool output | `$DIR/scans/<tool>-<slug>.txt` |
| response bodies | `$DIR/downloads/<slug>.body` |
| finding draft (pre-validation) | `$DIR/scans/finding-<slug>.json` |

Required shape of your returned message — nothing beyond these sections:

```markdown
### Case Outcomes
DONE STAGE=<stage> <id> — <endpoint> — <one-clause reason>
REQUEUE <id> — <endpoint> — <what is needed next>
ERROR <id> — <endpoint> — <why>

#### Findings draft            (only when new; 1 block per finding)
## [FINDING-XX-NNN] <title>
- Severity / OWASP / Type / Parameter: <one line>
- Evidence: <path under $DIR/scans or downloads> + <excerpt, <=3 lines>

#### Artefacts                 (paths only)
- <path> — <what it proves>

#### Handoff                   (<= 8 lines)
- blocked: <exact blocker, or none>
- suggested next: <concrete endpoint or case id>
```

If your result does not fit in this budget, that is a signal the result belongs
on disk — not that the budget should be exceeded. A long handoff is a defect in
the handoff, not thoroughness.
