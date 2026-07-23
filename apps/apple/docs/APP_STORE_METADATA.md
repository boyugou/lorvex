# App Store Listing Metadata (draft)

Draft copy for the Lorvex App Store Connect listing (macOS, iOS/iPadOS, and,
when submitted, visionOS). This is repo-side draft material the owner pastes
into App Store Connect; it is not itself submitted by any script. Keep it
factual — App Review reads the listing against the app's actual behavior, and
the product deliberately avoids promotional superlatives.

Product facts this copy must stay consistent with: Lorvex is an AI-first,
MCP-hosted task/calendar/habit/memory planner; it is local-first with optional
iCloud (CloudKit private database) sync; it contains no embedded AI model and
no analytics, tracking, ads, or accounts; public support routes through
`https://lorvex.app/support/` (no public email).
See `../../PRIVACY.md`, `docs/vision/DESIGN_PHILOSOPHY.md`, and
`docs/reference/FEATURES.md`.

Companion release materials: `APP_STORE_PRIVACY_ANSWERS.md` (the exact App
Privacy questionnaire answers) and `APP_STORE_SCREENSHOTS.md` (the screenshot
sizes and shot list). Account-only submission steps live in
`docs/finalization/RELEASE_ACCOUNT_CHECKLIST.md` at the repo root.

## Field length limits (App Store Connect)

| Field | Limit | Editable without a new binary? |
|---|---|---|
| App name | 30 chars | With a new version |
| Subtitle | 30 chars | With a new version |
| Promotional text | 170 chars | Yes, any time |
| Keywords | 100 chars total (comma-separated, spaces count) | With a new version |
| Description | 4000 chars | With a new version |
| What's New (release notes) | 4000 chars | With each version |
| Support URL / Marketing URL / Privacy Policy URL | standard URL | Yes (support/marketing) |

Verify the current limits in App Store Connect at submission — Apple changes
them independently of this repo.

## App name

```
Lorvex
```

## Subtitle (<=30 chars)

Primary (24 chars):

```
AI-first planner via MCP
```

Alternates, all within 30 chars:

- `Local-first, AI-run planner` (27)
- `Tasks, calendar, habits, AI` (27)

## Keywords (<=100 chars, comma-separated, no spaces)

```
task,todo,planner,calendar,habits,MCP,AI,GTD,focus,reminders,schedule,agenda,someday,tags
```

89 characters. Notes for tuning:

- Do not include the app name (`Lorvex`) or the category name
  (`Productivity`) — the store already indexes the app on both, so spending
  keyword budget on them is wasted.
- Roughly 11 characters of headroom remain for the owner to add a term.
- Singular/plural and comma-separated synonyms are indexed independently; no
  need to repeat both `task` and `tasks`.

## Promotional text (<=170 chars)

```
Your AI assistant runs the planner through MCP: it captures, prioritizes, and schedules tasks; you review and execute. Local-first, with optional iCloud sync.
```

158 characters.

## Description (<=4000 chars)

```
Lorvex is an AI-first planner for people who want an assistant to run their
task, calendar, and habit system instead of maintaining it by hand.

The model is inverted from a traditional to-do app. Rather than you creating,
organizing, prioritizing, and scheduling every item, an AI assistant does that
work through Lorvex's built-in MCP (Model Context Protocol) server, and you
review, correct, and execute. Lorvex ships no AI model of its own: the
intelligence comes from an external MCP-capable client you choose and connect
(for example Claude Desktop, Claude Code, or Codex). The connection is local
and off by default; you turn it on by pointing a client at Lorvex on your
device.

Lorvex is also a complete planner on its own, without any assistant connected:

- Tasks with priority, due date, duration estimate, tags, checklists,
  reminders, and recurrence.
- Lists as lightweight projects, with task dependencies.
- A Today view that surfaces a small, curated focus set instead of a raw
  backlog.
- A calendar that reads your existing events (with permission) and writes
  planning blocks into a dedicated Lorvex calendar or one you pick.
- Habits tracked by streaks and consistency, kept separate from recurring
  tasks.
- Daily reviews and a memory space for the context behind your work.

Built natively for Apple platforms — macOS, iPhone, and iPad — with widgets,
App Intents and Shortcuts, Spotlight, an Apple Watch companion, and system
light/dark appearance. Every AI change is recorded in a changelog you can read,
and any field the AI writes you can correct.

Privacy by design:

- Local-first. Your data lives in a database on your device. Lorvex operates
  no server of its own.
- Optional iCloud sync moves your data only between your own devices, stored
  encrypted in Apple's CloudKit private database.
- No analytics, no tracking, no ads, and no account or sign-in.

Support is handled through the public Lorvex support page. Lorvex is open
source under Apache-2.0.
```

Approximately 1,900 characters — well under the 4,000 limit; the owner can
extend it. Keep the "no embedded AI model" and "no analytics/tracking/ads"
statements accurate: they must match the privacy manifests, `PRIVACY.md`, and
App Store Connect's App Privacy answers (see `RELEASE_ACCOUNT_CHECKLIST.md`).

## What's New (version 1.0.0, initial release)

```
First public release of Lorvex.

- AI-first planning through a built-in local MCP server, so an MCP-capable
  assistant you connect can manage your tasks, calendar, habits, and notes.
- Native macOS, iPhone, and iPad apps, with widgets, App Intents/Shortcuts,
  Spotlight, and an Apple Watch companion.
- Local-first storage with optional, encrypted iCloud sync across your own
  devices.
- No analytics, tracking, ads, or account.
```

For later versions, replace this with the actual change list for that build.

## URLs and other listing fields

- **Privacy Policy URL:** `https://lorvex.app/privacy/`
  (matches the in-app policy link in `PrivacyPolicySummary.swift`).
- **Support URL:** `https://lorvex.app/support/` — the public support/contact
  page.
- **Marketing URL (optional):** `https://lorvex.app/`, or omit.
- **Primary category:** Productivity. **Secondary category (optional):** Utilities
  is the closest honest fit for a task/calendar/habit manager; it is optional and
  can be left empty without affecting the listing.
- **Copyright:** e.g. `2026 Boyu Gou` (owner sets the legal string).
- **Age rating:** answer the current age-rating questionnaire in App Store
  Connect. Lorvex has no mature content; the expected outcome is the lowest
  rating, but the questionnaire is mandatory and must be completed per platform
  (see `RELEASE_ACCOUNT_CHECKLIST.md`).

## App Review notes (paste into App Review Information)

App Review reads these to test the app. Draft:

```
Lorvex is a local, single-user planner. No account or sign-in is required;
launch the app and it works immediately against on-device storage.

Lorvex contains no embedded AI model. Its "AI-first" design means the app
hosts a local MCP (Model Context Protocol) server that an external,
user-configured MCP client (e.g. Claude Desktop) can connect to over an
on-device connection to read and modify the user's planner data. This
connection is off by default and requires the user to configure a client;
Lorvex itself transmits no user data to any third party. This satisfies the
third-party-AI disclosure expectation in Guideline 5.1.2 — the app does not
call any AI service on its own.

Optional iCloud sync uses the CloudKit private database and is off until the
user enables it. There is no analytics, tracking, or advertising.

The CarPlay capability is present in code but its entitlement is not included
in this build; CarPlay is not activated pending Apple approval.
```

Adjust to match the exact submitted build (for example, whether iCloud sync is
enabled in that binary's entitlements).
