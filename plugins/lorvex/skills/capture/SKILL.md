---
name: capture
description: Turn notes, a brain dump, meeting notes, or a message into Lorvex tasks. Use when the user pastes text and asks to capture it, add it to Lorvex, or turn it into tasks or to-dos.
argument-hint: "<text to capture>"
---

# Capture into Lorvex

Text to capture: $ARGUMENTS

If that is empty, use the text the user pasted into the conversation.

## 1. Triage every item

Read the whole text first, then sort each actionable item:

- **Clear, and the user's**: create it.
- **Someone else's commitment** ("Sarah will send the numbers Thursday"): no
  task. Offer the user a follow-up dated just after the promise.
- **Vague** ("we should probably…", "maybe"): list it and ask.
- **Possibly tracked already**: check with `search_tasks` before creating
  anything that sounds familiar, and update the existing task instead of
  adding a duplicate.

## 2. Fill fields only when the text supports them

- `title`: starts with a verb and is specific enough to act on.
- `raw_input`: the exact words the item came from, so the user can check the
  parse.
- `list_id`: an existing list that matches by meaning (`get_lists`). When
  unsure, leave it out and the task lands in the Inbox.
- `due_date` only for a real deadline; `planned_date` for the day the user
  means to work on it.
- `estimated_minutes` only when you are fairly sure (a call is about 15, a
  piece of writing 60 to 120).
- `priority` expresses importance, not urgency; keep the default unless the
  text says otherwise.

## 3. Create

Create the clear items in one `batch_create_tasks` call (`create_task` for a
single item). Then call `set_task_ai_notes` on any task where you made a
judgment call, such as a buffer before a deadline or a guessed list.

## 4. Report

Reply with a compact list of what you created (title, list, date), the
questions about the vague items, and any follow-ups you offered.
