# Menu Bar Regression Checklist

Purpose: catch tray icon + popover regressions before release.

## Interaction Matrix

Run all cases on macOS light and dark appearance.

### Open/Close Behavior
- [ ] Left-click tray icon opens popover from hidden state.
- [ ] Left-click tray icon while popover is focused closes popover.
- [ ] Left-click tray icon while popover is visible-but-unfocused refocuses/repositions popover.
- [ ] Clicking outside popover hides it.
- [ ] Rapid repeated clicks do not produce flash-then-disappear behavior.

### Window Lifecycle Edge Cases
- [ ] Main window hidden via Cmd+W, tray icon still opens popover.
- [ ] Main window restored after tray interactions with no dead state.
- [ ] Popover still opens correctly after switching Spaces/desktops.
- [ ] Popover behavior remains stable after entering/exiting fullscreen app windows.

### Icon Rendering
- [ ] Menu bar icon is crisp on Retina displays.
- [ ] Menu bar icon remains legible in light appearance.
- [ ] Menu bar icon remains legible in dark appearance.
- [ ] Dock icon quality remains unchanged.

## Failure Reporting Template

When any check fails, log:
- build commit hash
- display scale and monitor setup
- macOS appearance mode (light/dark)
- reproduction steps
- expected vs actual
- screenshot or short recording

## Reusable Evidence Template

Menu bar and settings gates share one current evidence target. Generate one combined report scaffold,
then fill the Menu Bar section from this checklist and the Settings section from
`docs/execution/SETTINGS_REGRESSION_CHECKLIST.md`.

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

## Release Gate Rule

Do not mark release candidate as menu-bar-ready unless every checkbox above passes.

## Contract Mapping (#112)

This checklist carries the durable acceptance contract for #112. Keep the AC mapping here instead of pointing to a dated execution note.

- `AC-112-01`: validate Dock click from hidden/minimized states always ends with main focused.
- `AC-112-03`: validate strict tray toggle branches (`hidden->open`, `focused->close`, `visible-unfocused->refocus`).
- `AC-112-04`: validate popover placement clamps into monitor bounds.
- `AC-112-05`: validate popover open failure falls back to main focus.
- `AC-112-11`: ensure Menu Bar evidence is posted with AC IDs in the current manual gate report.
- `AC-112-12`: execute stress loop below and confirm no dead state.

### State-Transition Stress Loop (Required)

Run 5 full loops and record pass/fail for each step:

1. hide main (`Cmd+H`) -> click Dock icon
2. minimize main -> click Dock icon
3. open tray popover -> switch Spaces/desktops -> click tray icon
4. fullscreen another app -> click tray icon -> click Dock icon

Pass condition:
- No flash-then-disappear behavior
- No unreachable hidden window state
- Main window can always be recovered via Dock click

## Automation Bridge Coverage (#224)

Automated subset (non-interactive guards):

```bash
npm run manual-gate:smoke
```

This command automates deterministic UI regression checks:
- static UI wiring/module-contract assertions
- TypeScript compile smoke for app surfaces
- desktop auxiliary-window fullscreen/cross-space contract guard
- dock/window restore state-machine regression test

Still manual by design:
- tray popover tactile behavior and visual correctness in real menu bar surface
- Retina/light/dark icon legibility checks
- stress-loop interaction checks requiring repeated physical click/open/close actions
