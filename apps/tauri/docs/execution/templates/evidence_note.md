# Evidence Note Template

Use this template when the External Evidence Scan gate applies (new external dependency/API, platform-behavior assumptions, ecosystem/market strategy assumptions, non-trivial UI pattern changes, or perf/security/privacy uncertainty).

## External Evidence Scan Rules

- Timebox: 20 minutes, max 5 sources; one 15-minute extension allowed only for conflicting decision-critical sources.
- Source quality: primary sources first (official docs/specs/release notes/repo READMEs); community articles can supplement but not be sole basis.
- Record an `Evidence Note` on the linked issue before the first implementation commit.
- If coding starts >14 days after note creation, run a 5-minute freshness check and append only changed facts.

## Template

```md
### Evidence Note (timeboxed)

Question:
- <decision blocked by uncertainty>

Trigger:
- <dependency/API | platform behavior | UI pattern | perf/security/privacy>

Timebox:
- <20m> (+15m extension used: <yes/no>)

Sources (max 5, primary first):
1. <url> — <why relevant>

Confirmed facts:
- <fact + source>

Inferences (for Lorvex):
- <inference>

Non-facts / rejected assumptions:
- <assumption + rejection reason>

Decision for this issue:
- Approach: <chosen option>
- Guardrails: <tests/flags/metrics>
- Follow-up unknowns: <none or #issue>
```
