# Calendar Behavior

Canonical location: [`docs/design/CALENDAR_BEHAVIOR.md`](../../../../docs/design/CALENDAR_BEHAVIOR.md)

`calendar_events` are Lorvex-owned canonical events. Users can create, edit, delete, link, and export canonical events from Lorvex surfaces.

`provider_calendar_events` are read-only external provider mirrors. Provider events stay read-only; Lorvex can display and link them, but direct mutation stays on the canonical event surface.
