# Privacy Policy

Lorvex is a local-first task, calendar, habit, and memory planner. This policy
describes what data Lorvex stores, where it goes, and who can see it.

## Summary

- Your data lives on your device, in a local database. Lorvex has no server
  of its own and no backend that Lorvex operates.
- Optional iCloud sync moves your data between your own devices only, and
  every field is stored encrypted on Apple's servers, never as plaintext.
  Whether that encryption is end-to-end (only your own devices hold the key)
  depends on your iCloud account's data protection level — see
  [iCloud sync](#icloud-sync-optional) below.
- Lorvex collects no analytics or advertising data, and does not sell data.
  It does capture on-device crash/hang diagnostics via Apple's MetricKit, kept
  only in a local log that Lorvex itself never transmits anywhere. Separately,
  Apple's own OS-level channels (system analytics sharing, and TestFlight's
  automatic crash sharing) can send crash/usage data to Apple independently of
  Lorvex — see
  [No analytics, no tracking, no advertising](#no-analytics-no-tracking-no-advertising).
- If you connect an external AI assistant to Lorvex's local MCP server, that
  assistant can read and modify your Lorvex data, governed by its own privacy
  practices — Lorvex serves your data only locally, over an on-device
  connection, to the client you chose.

## What data Lorvex stores

Lorvex stores the content you create: tasks, lists, calendar events, habits,
daily reviews, memory notes, tags, and your app preferences. All of this is
stored in a SQLite database on your device. Lorvex does not require an
account, a sign-in, or any personal information to be used.

## iCloud sync (optional)

If you turn on iCloud sync in Settings, Lorvex uses Apple's CloudKit **private
database** to copy your data between your own devices signed into the same
iCloud account. Every task, calendar, habit, and memory field Lorvex writes
goes through CloudKit's encrypted-record-field API, so Apple's iCloud/CloudKit
servers always store that content encrypted — never as readable plaintext.

Who can decrypt it depends on your iCloud account's data protection level,
which you control from your device's iCloud settings, not from Lorvex:

- **With Advanced Data Protection turned on**, only your own signed-in devices
  hold the decryption key. This is full end-to-end encryption: Apple cannot
  read this content, and cannot recover it for you if you lose access to your
  account.
- **With standard data protection (Apple's default)**, the fields are still
  encrypted at rest, but Apple retains the key material needed to help you
  recover your account and data, so Apple can access this content as part of
  that recovery process.

Turning on Advanced Data Protection for your iCloud account is done in your
device's Settings, not in Lorvex; see Apple's documentation for how.

Sync is entirely tied to your iCloud account: Apple, not Lorvex, operates the
iCloud service, and Lorvex has no separate server that receives or stores a
copy of your data. If you turn sync off, or are not signed into iCloud, all
data simply stays local to that device.

## No analytics, no tracking, no advertising

Lorvex does not include any analytics, telemetry, or third-party tracking
SDKs, and it does not show ads. There is no data collection to sell or share
beyond the on-device diagnostics described next.

Lorvex uses Apple's on-device MetricKit framework to capture crash, hang, and
performance diagnostics for this device. These are written only to a local
diagnostic log — capped at the 2,000 most recent entries and pruned after 30
days, and this log is never transmitted anywhere by Lorvex's own code: not to
a Lorvex server (Lorvex has none), not to Apple, and not to any third party.
You can review it yourself in Settings → Diagnostics.

Separately, if you have turned on Apple's system-level analytics sharing in
your device Settings, your device may send crash and usage data to Apple
independently of Lorvex's own log above; the same is true automatically for
TestFlight builds, which share crash reports with the developer even when
that Settings toggle is off. Both of these are Apple OS/App Store channels
controlled by you in Settings (or, for TestFlight, by Apple's distribution
defaults) — not by Lorvex, and not through Lorvex's own code.

## The MCP server (optional, local, user-directed)

Lorvex can run a local MCP (Model Context Protocol) server that lets you
connect external AI assistant clients (for example, Claude Desktop, Claude
Code, or Codex) to your Lorvex data. This connection:

- Is off by default and only exists if you configure a client to use it.
- Runs entirely on your device over a local (stdio) connection — no network
  port, no remote server.
- Gives the client you configured the ability to read and modify your Lorvex
  data (tasks, calendar events, habits, memory notes, and related content),
  because that is the feature's purpose: letting your AI assistant manage
  your planner on your behalf.

Any data your connected assistant sends elsewhere is governed by that
assistant's own privacy practices and your configuration of it — Lorvex has
no visibility into, and does not control, what a third-party client does with
data it reads. Lorvex itself does not transmit your data to any third party;
it only serves it, locally, to the client you chose to connect.

## Calendar access

With your permission (via Apple's EventKit), Lorvex reads and writes calendar
events so it can show and schedule your planning blocks. Lorvex writes those
events into a calendar in your device's Calendar accounts:

- By default, a dedicated "Lorvex" calendar that Lorvex creates the first
  time it needs one, in whichever account is configured for new calendars
  (iCloud, if you're signed in).
- Or, if you pick a different target from Lorvex's calendar picker, any
  other calendar you can write to — an iCloud, Google, Exchange, or other
  CalDAV calendar, or an on-device-only ("On My Mac"/local) calendar.

Once an event is written into one of these calendars, its title, time,
location, notes, and recurrence are then synced across your devices by that
calendar's own provider (iCloud, Google, Exchange, or whichever account owns
it) — the same as any other event in that calendar, governed by that
provider's own sync and privacy practices, not by Lorvex. Only an
on-device-only calendar keeps those events local to that one device.

This access is governed by the macOS/iOS Calendar permission you grant, not
by Lorvex. Beyond that provider sync, Lorvex itself transmits calendar data
only through Lorvex's own iCloud sync of its internal record of your
calendar events (see [iCloud sync](#icloud-sync-optional) above) and the MCP
path described above.

## Notifications

Lorvex uses local, on-device notifications for reminders (tasks, habits,
etc.). These are scheduled and delivered entirely on your device; Lorvex does
not use a push-notification service to deliver reminder content.

## Your control over your data

- **On Mac**, you can reset or delete this Mac's local Lorvex data at any time
  from within the app (Settings → Data → Reset → "Reset This Device…"). This
  is local to that Mac; a copy already synced to iCloud is not affected.
- **On iPhone/iPad**, Lorvex does not currently offer an in-app local-reset
  action; uninstalling the app (see below) is how you remove its local data
  on that device, or use "Delete iCloud Data" (below) to remove the synced
  copy.
- You can delete Lorvex's iCloud data from within the app ("Delete iCloud
  Data" — Settings → Data on macOS, Settings → Cloud Sync on iPhone/iPad).
  This removes every Lorvex record from your iCloud account, for all devices
  that sync with it, and turns sync off until you explicitly re-enable it
  (re-enabling re-uploads that device's local data). The local data on the
  device stays intact.
- Data synced via iCloud is governed by your iCloud account. You can also
  manage or remove it using your device's iCloud/Apple ID settings, or turn
  off sync in Lorvex, which stops further syncing for that device.
- Uninstalling Lorvex removes its local database from that device.

## Children's privacy

Lorvex does not knowingly collect data from anyone, including children, since
it collects no data in the first place — everything described above is
generated by you and stored on your own device or your own iCloud account.

## Changes to this policy

If Lorvex's data handling changes, this document will be updated to reflect
it. The authoritative, current version always lives at
`https://github.com/boyugou/lorvex/blob/main/PRIVACY.md`.

## Contact

Lorvex is an open-source project with support handled entirely through
GitHub — there is no separate support email. For questions about this policy
or to report an issue, open an issue at
[github.com/boyugou/lorvex](https://github.com/boyugou/lorvex/issues).

*Last updated: reflects the current shipping version of Lorvex.*
