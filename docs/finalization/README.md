# docs/finalization — autonomous finalization loop state

Working state for the autonomous review→fix→re-audit convergence loop on the Lorvex
**Apple** app. This directory is **dev-process state, not public documentation** — it is
deleted as the last step before the public repo cut.

- **`FINDINGS_BACKLOG.md`** — the single source of truth for OPEN work: the live queue with each
  item's verified status (still-open / owner-decision), plus the guard rails (known flake,
  build-artifact and gate/push lessons) and the "proven sound — do not re-litigate" list. Start here.
- **`FINDINGS_ARCHIVE.md`** — the settled record: fixes that landed (each with its commit), findings
  verified NOT to be bugs, and accepted/won't-fix/deferred items. Kept (not deleted) so a later audit
  pass doesn't re-flag a solved thing; the backlog stays lean by moving items here as they close out.
- **`RELEASE_ACCOUNT_CHECKLIST.md`** — the owner runbook for actions that genuinely need the Apple
  account or a human (identifiers/certs/profiles, CloudKit production promotion, App Privacy
  answers, age rating, screenshots, signed-RC validation, TestFlight, trademark). Nothing here is
  code-fixable.
- **`gate.sh`** — the combined full gate (app build, core + app test suites, all verifiers,
  schema/migration parity, iOS Release build). Exits non-zero with the count of failed steps.

The point-in-time audit logs (the ACF cross-cutting registry, the wrap-up re-audit, the wave-by-wave
deep-audit log, and the round-2 findings dump) were folded into the backlog / archive and deleted —
their findings are all landed or captured across those two files, and git history / PR descriptions
are their proper home. Consolidating open work into one file and its settled record into another is
deliberate: scattered per-pass docs let real to-do items slip through the cracks.
