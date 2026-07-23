# Privacy Summary

This is a plain-language summary of how Lorvex handles your data. It is
bundled with the app so it is always available offline. The full policy is
maintained at the link below.

## Local-first

Your tasks, calendar events, habits, daily reviews, and memory notes are
stored in a SQLite database on this device. Lorvex has no server of its own.

## iCloud sync (optional)

If you turn on sync, your data moves between your own devices via Apple's
CloudKit private database. Every field is stored encrypted — never as
plaintext. Whether that's full end-to-end encryption (only your own devices
hold the key) depends on your iCloud account's data protection level: with
Advanced Data Protection enabled, only your devices hold the key and Apple
cannot read or recover it; with standard data protection (Apple's default),
the fields are still encrypted at rest, but Apple retains the key material
needed to help you recover your account, so Apple can access this content as
part of that recovery process. Sync is tied entirely to your iCloud account,
not to any Lorvex-operated service.

## No analytics, no tracking, no ads

Lorvex has no analytics, telemetry, or third-party tracking SDKs, shows no
ads, and does not sell data. It does capture on-device crash/hang diagnostics
via Apple's MetricKit, kept only in a local log — most recent 2,000 entries,
pruned after 30 days. Lorvex never transmits this log anywhere. Separately, if
you have turned on Apple's system-level analytics sharing in your device
Settings, your device may send crash and usage data to Apple; that is
controlled by you in Settings, not by Lorvex.

## Local MCP server (optional)

You may connect external AI assistant clients (for example Claude Desktop) to
Lorvex over a local, on-device connection. Once you configure a client, it
can read and modify your Lorvex data. Anything that client does with your
data afterward is between you and that client — Lorvex itself never
transmits your data to any third party.

## Calendar and notifications

With your permission, Lorvex reads and writes Calendar events (EventKit) to
schedule your plans — by default into a dedicated "Lorvex" calendar it
creates, or another calendar you choose. Unless that calendar is an
on-device-only ("On My Mac"/local) one, its events are then synced by that
calendar's own provider (iCloud, Google, Exchange, or another CalDAV
account) across your devices — governed by that provider, not by Lorvex.
Reminders are delivered as local, on-device notifications only.

## Your control

On Mac, you can reset or delete this Mac's local data from Settings → Data at
any time — that is local to that Mac, and a copy already synced to iCloud is
not affected. On iPhone/iPad there is no in-app local-reset action;
uninstalling Lorvex is how you remove its local data on that device. Settings
also offers "Delete iCloud Data" (Settings → Data on macOS, Settings → Cloud
Sync on iPhone/iPad), which removes every Lorvex record from your iCloud
account for all devices that sync with it and turns sync off until you
re-enable it. iCloud-synced data remains governed by your iCloud account and
can also be managed from your device's iCloud settings.

## Full policy and contact

Read the complete policy at:
https://lorvex.app/privacy/

For support and contact, visit https://lorvex.app/support/ — no email address
is used.
