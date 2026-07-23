# Settings Regression Checklist

Purpose: prevent silent breakage in high-frequency Settings interactions.

## General UX
- [ ] Settings opens without crash on macOS signed build and dev build.
- [ ] Default scope opens to `General` with readable hierarchy.
- [ ] Scroll container does not expose off-content blank space when reaching top/bottom.

## Auto-Save Reliability
- [ ] Working hours save automatically after edit.
- [ ] Focus limit save automatically after edit.
- [ ] Advanced controls (timezone, review cadence, briefing time) save automatically.
- [ ] Auto-save status indicator transitions correctly: saving -> saved (or error).

## Immediate Controls
- [ ] Theme change applies instantly.
- [ ] Language change applies instantly.
- [ ] Sidebar module toggles apply instantly and persist after app restart.
- [ ] Sidebar module visibility controls are hidden on mobile runtime.
- [ ] Menu bar icon visibility toggle applies instantly (no restart).

## Sync + Diagnostics
- [ ] Sync status refresh button updates status and badge state.
- [ ] Error log list loads and supports copy.
- [ ] Clear error logs actually clears data and updates UI.
- [ ] Recent logs include calendar/frontend errors when reproduced.

## MCP Setup Surface
- [ ] Assistant snippets render for Claude Desktop, Claude Code, and Codex.
- [ ] Setup guide/fallback instructions remain visible even when assistant snippets are unavailable.
- [ ] Copy actions work and show clear success feedback.
- [ ] Wording uses locale-appropriate terminology (`AI assistant` / `AI 助理`).

## Sync Error Recovery
- [ ] Sync bridge auto-save error CTA uses retry wording (not save wording).

## Reusable Evidence Template

Settings and Menu Bar regressions are reported together for the current manual gate evidence target.
Generate the shared scaffold once, then fill both checklist sections.

- Template: `docs/execution/templates/manual-gate-ui-regression.md.tmpl`
- Generate a local report scaffold:

```bash
npm run docs:manual-gate:report -- --template ui-regression --date YYYY-MM-DD --issue <current-issue> --commit <git-sha>
```

Use exactly one current evidence target: `--issue <current-issue>`, `--pr <current-pr>`, or `--release-target <release-target>`.

- Verify evidence contract before posting:

```bash
npm run verify:manual-gate-evidence
```

- Evidence freshness window is 14 days; release CI enforces strict freshness with:

```bash
npm run verify:manual-gate-evidence -- --enforce-release
```

Default output path:
`artifacts/manual-gates/ui-regression/YYYY-MM-DD/<target-slug>.md`

Do not commit generated evidence. Summarize the run in the linked issue/PR and keep attachments alongside the local artifact bundle. Fill `Evidence permalink` with the posted GitHub issue/PR comment URL before treating the gate as complete.

## Contract Mapping (#112)

This checklist carries the settings-side durable acceptance contract for #112. Keep the AC mapping here instead of pointing to a dated execution note.

- `AC-112-09`: validate menu bar icon toggle behaves as optimistic UI with rollback on runtime/persistence failure.
- `AC-112-10`: validate desktop-only controls remain correctly gated on mobile runtime.
- `AC-112-11`: settings evidence must include AC ID references in the current report artifact.

### Required Validation Notes

For each run, record:

1. runtime apply result for menu bar icon visibility (`set_tray_icon_visibility`)
2. persisted preference result (`menu_bar_icon_visible` round-trip after restart)
3. observed rollback behavior if either step fails

## Automation Bridge Coverage (#224)

Automated subset (non-interactive guards):

```bash
npm run manual-gate:smoke
```

This command automates deterministic settings regression checks:
- static settings/navigation/module wiring guards
- app TypeScript compile smoke

Still manual by design:
- interactive auto-save timing and indicator transition UX
- copy/snippet feedback visibility and wording clarity in UI
- signed-build runtime behavior verification on real operator environment
