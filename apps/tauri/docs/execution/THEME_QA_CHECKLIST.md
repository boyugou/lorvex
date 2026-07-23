# Theme QA Checklist

Purpose: block release candidates with theme regressions in readability, desktop chrome, and overlay surfaces.

## Release Gate
- [ ] Execute this checklist on a signed macOS build and local dev build.
- [ ] Run all checks in: `paper`, `light`, `dark`, `ember`, `midnight`, `liquid`, `liquid_light`, `mica`, `mica_light`, `adwaita`, `adwaita_light`, `system` (with macOS both light and dark).
- [ ] Run profile sweep in: `clarity`, `studio`, `focus_compact`, `liquid_glass`.
- [ ] Do not mark the release candidate theme-ready unless every checkbox passes.

## Contrast and Readability
- [ ] Primary/secondary text remains readable in Today, All Tasks, List, and Settings views.
- [ ] Text on elevated surfaces (cards, chips, banners, toasts) remains readable in every theme.
- [ ] Interactive controls (buttons, inputs, toggles, tabs) keep visible boundaries and readable labels.
- [ ] Disabled states, placeholder text, and helper text remain distinguishable from active content.
- [ ] Status semantics (success/warning/danger/accent) stay visually distinct without relying on color alone.

## Desktop Chrome Consistency
- [ ] Native titlebar/chrome appearance matches the selected in-app theme intent.
- [ ] Window controls (traffic lights) remain visible and legible in all themes.
- [ ] Minimize/restore, refocus, and workspace switching do not cause native chrome/theme drift.
- [ ] Main window and auxiliary windows stay visually consistent after prolonged runtime.

## Overlay Surfaces
- [ ] Overlay UI (command palette, dialogs, popovers, drawers, toasts) uses the active theme without mixed tokens.
- [ ] Overlay surfaces preserve visible focus states for keyboard users.

## Theme Switching Regression Sweep
- [ ] Switching themes in Settings updates all visible surfaces immediately without stale colors.
- [ ] Rapid theme toggling does not break layout, spacing, or interaction states.
- [ ] `system` mode follows macOS appearance changes at runtime (light <-> dark) across app surfaces.
- [ ] Theme preference persists correctly across full app restart.
- [ ] Ongoing interactions (open overlays, in-progress edits) remain stable after theme switch.

## Liquid Material Policy
- [ ] Liquid Glass themes and the Liquid Glass appearance profile remain user-selectable options and never become defaults without explicit decision + gate evidence.
- [ ] Direct desktop channel visuals remain correct without private-API-only presentation paths.

## Bounded-Surface Liquid Visual Evidence
- [ ] Bounded-surface liquid visual checks live here; do not create separate issue-bound execution docs for them.
- [ ] When `liquid`, `liquid_light`, or `liquid_glass` is selected, capture before/after screenshots for the sidebar shell, Settings panel, and popover panel.
- [ ] Record continuous scroll smoothness, quick action latency, and theme-switching responsiveness for those bounded surfaces.
- [ ] Record text contrast, focus ring visibility, and mixed-background readability for those bounded surfaces.
- [ ] Store captures and notes under `artifacts/manual-gates/theme-qa/YYYY-MM-DD/` or equivalent issue/PR attachments; do not commit generated evidence.

## Appearance Profile Regression Sweep
- [ ] Switching appearance profiles in Settings updates bounded surfaces immediately without stale material treatment.
- [ ] Dense task/editor surfaces (Today, All Tasks, List, Task Detail) remain clarity-first across all profiles.
- [ ] `focus_compact` profile preserves legible text and keyboard focus visibility at higher visual density.
- [ ] `liquid_glass` remains an optional user-selected profile and does not degrade baseline profiles.
- [ ] Appearance profile preference persists correctly across full app restart.

## Failure Reporting
For every failed checkbox, capture:
- build commit hash
- selected theme and macOS appearance
- reproduction steps
- expected vs actual behavior
- screenshot or short recording
