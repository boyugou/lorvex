# App Store Screenshot Plan

The plan for the App Store Connect screenshot sets. This file specifies *what to
shoot* and *at what sizes*; it deliberately does **not** try to capture anything
— App Store screenshots need a running app on a real device or simulator, which
is an owner/local step, not a repo artifact.

Companion material:

- Listing copy (captions can echo it): `APP_STORE_METADATA.md`.
- App Privacy answers: `APP_STORE_PRIVACY_ANSWERS.md`.
- Account-only submission steps: `docs/finalization/RELEASE_ACCOUNT_CHECKLIST.md`
  (repo root) §11.
- Per-platform surface truth this shot list maps to: `docs/SURFACE_DESIGN.md`,
  `docs/reference/FEATURES.md`.

## Ground rules

- **Truthful.** Every shot is a real Lorvex surface listed in
  `docs/reference/FEATURES.md` as `[SHIPPED]`. Do not stage a screen the app does
  not render. In particular, do **not** screenshot CarPlay, the Eisenhower
  matrix, or the dependency-graph "workspaces": CarPlay is provisioning-gated and
  not active in the shipped build, and the latter two are MCP-data-only with no
  human surface (they redirect to Today).
- **No personal data.** Capture against seeded demo content, not a real user's
  planner. `LorvexPreviewCoreFactory.makeSeeded()` produces clean sample data;
  the iOS surface has `MobileStoreDebugSeed` for the simulator. Use neutral,
  believable task/list/habit names — no real names, emails, or private notes.
- **Light and dark.** Lorvex follows system appearance. Prefer one coherent
  appearance across a device's set (usually light for the hero, or a deliberate
  light/dark split); do not mix randomly shot to shot.
- **Clean chrome.** On iOS/iPadOS/watchOS simulators, set a clean status bar
  before capturing (`xcrun simctl status_bar <udid> override --time 9:41
  --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3`).
- **No overclaiming captions.** Optional text overlays must describe what the
  screen actually does. The differentiator to lean on is honest: an AI assistant
  you connect drives the planner through a local MCP server; you review and
  execute. Do not imply an in-app AI model — there is none.

## How to capture (owner/local step)

- **macOS:** the Mac app runs on the host (no simulator). Launch a seeded build
  and capture windows with `⌘⇧4` + Space (window shot) or `screencapture -o -l
  <windowid>`. Note: `swift run LorvexApple --dump-snapshots <dir>` is a
  DEBUG *component* renderer for design QA (task row, metric card, habit ring),
  **not** an App Store screenshot path — it renders atoms, not whole workspaces.
- **iOS / iPadOS / visionOS / watchOS:** build and install onto the matching
  simulator (the `script/verify_mobile_simulator.sh`,
  `verify_vision_simulator.sh`, `verify_watch_simulator.sh` flows already boot,
  install, and launch the app), navigate to each surface, and capture with
  `xcrun simctl io <udid> screenshot <file>.png`. Simulator captures are already
  at the device's native pixel size, which is what App Store Connect expects.

## Required sizes

App Store Connect currently accepts a single largest-device set per family and
scales it to smaller devices; you no longer must upload every historical size.
Confirm the exact required/accepted pixel dimensions in App Store Connect at
submission — **Apple changes these independently of this repo.**

| Platform | Device class to shoot | Portrait pixels (confirm in ASC) | Count |
|---|---|---|---|
| iOS (iPhone) | 6.9" (e.g. iPhone 16 Pro Max) | 1290 × 2796 | up to 10 (min 1) |
| iPadOS | 13" iPad Pro | 2064 × 2752 (2048 × 2732 also accepted) | up to 10 (min 1) |
| macOS | Mac display | 2880 × 1800 (or 1280×800 / 1440×900 / 2560×1600) | up to 10 (min 1) |
| visionOS | Apple Vision Pro | 3840 × 2160 (landscape) | up to 10 (min 1) |
| watchOS | largest current watch (e.g. Series 10 46mm / Ultra) | ~410 × 502 (device-specific) | up to 10, optional |

Notes:

- Shoot the **largest** iPhone and iPad class; App Store Connect down-scales for
  smaller devices, so a single 6.9" iPhone set and a single 13" iPad set cover
  those families.
- The watch app is embedded in the iOS app. Watch screenshots are optional; add
  a small set only if you want the watchOS section of the product page populated.
- Aim for 3–5 strong shots per platform (the first two carry the most weight in
  search results and on the product page); the table's "up to 10" is the ceiling.

## Shot lists (mapped to real surfaces)

Order matters: the first shot is the hero. Lead with the surface that best tells
the "assistant-run planner you review" story, then the everyday planner surfaces.

### macOS — the command center

1. **Today** — the focus plan + time-blocked schedule (the daily driver). Hero.
2. **Assistant / AI changelog** — Settings → Assistant (MCP client wiring) or a
   Today/Tasks view showing the AI-changelog entries. This is the honest way to
   show the "AI runs it, you review" model without faking an in-app chat.
3. **Tasks** workspace — priority-sorted list with tags, due dates, checklist.
4. **Calendar** — week view with Lorvex planning blocks interleaved with
   EventKit events.
5. **Habits** — streak metrics + calendar heatmap + a milestone progress bar.
6. *(optional)* **Command Palette (⌘K)** or the **menu-bar Today HUD** to show
   keyboard-first / glanceable macOS ergonomics.

### iOS (iPhone) — capture, glance, focus

1. **Today** tab — current focus + day plan. Hero.
2. **Quick capture** sheet (the global ＋) — one-tap capture.
3. **Tasks** tab — list with priority/tags; optionally a task detail sheet.
4. **Calendar** tab — day/agenda with planning blocks.
5. **Habits** tab — streaks and progress.
6. *(optional)* A **Home Screen with widgets** (Focus / Today / Habits /
   progress-ring) to show the WidgetKit surfaces.

### iPadOS — the middle instrument

1. **Tasks split** workspace — persistent list + detail panes at regular width.
   Hero (this is the surface that reads as "more than a big phone").
2. **Calendar agenda** — 3-day time grid with the pinned agenda inspector.
3. **Today** with the full sidebar (NavigationSplitView) visible.
4. *(optional)* **Habits** or **Memory** split workspace.

### visionOS — spatial planner

1. **Today** or **Tasks** in the main window, framed per Apple's visionOS
   screenshot guidance (3840 × 2160). Only include if visionOS is in the
   submission for this cut.

### watchOS — wrist glance (optional)

1. **Root focus view** — current focus task + one-tap complete.
2. *(optional)* A **complication** on a watch face.

## Localization and preview videos

- Screenshots are per-localization. Lorvex ships English first; add localized
  sets only for locales whose listing you localize.
- App preview videos are optional. If added, they follow the same truthfulness
  bar and Apple's per-device video specs (confirm in App Store Connect).
