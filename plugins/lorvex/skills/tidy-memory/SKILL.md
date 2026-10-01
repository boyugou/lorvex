---
name: tidy-memory
description: Review and tidy the notes the assistant keeps about the user in Lorvex memory. Use when the user asks what you remember about them, asks to update or clean up your notes or memory, or when memory looks stale or duplicated.
---

# Tidy Lorvex memory

Lorvex memory holds the assistant's notes about the user. The user can read,
edit, and delete every entry on the app's Memory page, so write each entry as
if they will read it, because they will.

## 1. Read

Call `read_memory` with no key to get every entry. While `truncated` is true,
page with `limit` and `offset`.

## 2. Review each entry

The standard sections are `user_profile`, `list_summaries`,
`behavioral_patterns`, `recent_activity`, and `pending_followups`. Look for:

- **Stale facts**: a finished project in `list_summaries`, an old item in
  `pending_followups`. Check against `get_lists` or `search_tasks` before
  removing anything.
- **Duplicates**: the same fact under two keys. Keep it in the section it
  belongs to.
- **Misplaced notes**: a one-off event in `user_profile`, a lasting
  preference in `recent_activity`.
- **Unkind or speculative wording**: rewrite it in neutral, factual language
  and mark guesses as guesses.

## 3. Propose, then apply

Show the proposed changes as a short before-and-after list, and apply them only
after the user agrees:

- `write_memory` rewrites a section. It replaces the content, so send the full
  new text.
- `rename_memory` moves an entry to a better key (`old_key`, `new_key`).
- `delete_memory` removes an entry, only when the user agreed.

Keep each section brief: a few short paragraphs or bullets. Assistants read
memory at the start of sessions, so its length costs every later conversation.
