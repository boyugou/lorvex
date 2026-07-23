# First Run Without Network

Lorvex is designed to be **local-first**. You can install it, open it, and use
every core feature — create tasks, plan your day, capture notes, run habits,
attach files, search — without ever connecting to the internet.

## What lives on your device

- Your entire task database (SQLite, stored under your OS application-support
  directory).
- Full-text search indexes, calendar subscriptions cache, blob attachments.
- All preferences, lists, tags, habits, and AI changelog entries.

Nothing is sent to any remote server by default. There is no telemetry and no
account to create.

## What requires network (and is optional)

- **Filesystem-bridge sync** — only if you want to mirror your database through
  a folder backed by a provider such as Dropbox, Syncthing, or a network share.
  You can enable this any time from **Settings → Sync**.
- **ICS calendar subscriptions** — read-only imports from remote calendar URLs.
  Lorvex caches the last successful fetch, so offline runs still show previously
  synced events.
- **MCP assistant connections** — if you wire up an external AI assistant to
  Lorvex, that assistant may itself need network. Lorvex does not.

If you installed Lorvex offline, just dismiss the "you're offline" banner and
keep going. Sync can wait.
