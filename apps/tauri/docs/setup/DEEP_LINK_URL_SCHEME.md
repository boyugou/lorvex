# Lorvex Deep Link URL Scheme

Lorvex registers the `lorvex://` URL scheme, enabling launcher utilities and automation tools to open URLs.

## Supported URLs

### Navigation

| URL | Description |
|-----|-------------|
| `lorvex://today` | Open the Today view |
| `lorvex://search?q=<query>` | Open the All Tasks view (search for tasks) |
| `lorvex://quick-capture` | Open the quick-capture dialog |
| `lorvex://task/<task_id>` | Open a specific task by ID |

### Actions

| URL | Description |
|-----|-------------|
| `lorvex://add-task?title=<title>` | Opens Quick Capture prefilled for user review |
| `lorvex://complete-task?id=<task_id>` | Opens the task for manual completion confirmation |

## Parameter Reference

### `lorvex://add-task`

| Parameter | Required | Description |
|-----------|----------|-------------|
| `title` | Yes | Task title (percent-encoded) |
| `list` | No | List name to assign the task to (case-insensitive match) |
| `due` | No | Due date in `YYYY-MM-DD` format |
| `priority` | No | Priority level: `1` (highest) through `3` (lowest) |

`add-task` does not create the task until the user submits Quick Capture. The deep link is a review-first handoff: Lorvex validates the URL, opens Quick Capture, pre-fills the supported fields, and waits for an explicit user submit.

### `lorvex://complete-task`

| Parameter | Required | Description |
|-----------|----------|-------------|
| `id` | Yes | The task ID to open for completion review |

`complete-task` opens/selects the task for manual completion confirmation. It does not mark the task completed by itself.

### `lorvex://search`

| Parameter | Required | Description |
|-----------|----------|-------------|
| `q` | Yes | Search query (percent-encoded) |

## Automation Examples

### Quick Add Task

1. Open your automation or launcher tool
2. Create a new action or shortcut
3. Add a text input step (type: Text, prompt: "Task title")
4. Add an open-URL step with URL: `lorvex://add-task?title=[Provided Input]`
5. Review the prefilled Quick Capture form and submit it in Lorvex.

### Add Task to a Specific List

1. Create a new action or shortcut
2. Add a text input step (prompt: "Task title")
3. Add an open-URL step with URL: `lorvex://add-task?title=[Provided Input]&list=Work&priority=2`
4. Review the prefilled Quick Capture form and submit it in Lorvex.

### Quick Complete (from a launcher or notification)

1. Create a new action or shortcut
2. Add an open-URL step with URL: `lorvex://complete-task?id=<paste_task_id_here>`
3. Confirm completion manually in Lorvex.

### Morning Routine

1. Create a new action or shortcut
2. Add an open-URL step with URL: `lorvex://today`
3. This opens Lorvex directly to the Today view -- useful as a Shortcuts automation triggered at a specific time.

## Notes

- All parameter values must be [percent-encoded](https://developer.mozilla.org/en-US/docs/Glossary/Percent-encoding). Shortcuts.app handles this automatically for "Ask for Input" variables.
- If the app is not running, macOS will launch it and process the URL on startup.
- The `list` parameter in `add-task` performs a case-insensitive name match when the user submits Quick Capture. If no list matches, Lorvex falls back to the configured `default_list_id`; if no real default exists, task creation is rejected instead of creating an uncategorized active task.
- A fresh database's `default_list_id` may point at the schema-seeded `inbox` list. This is default-list bootstrap behavior, not an Inbox view or review workflow.
- Invalid `priority` values (outside 1-3 or non-numeric) reject the deep link with a validation error before Quick Capture opens.
- Apple-native App Intents belong to the Swift app under `apps/apple`; Tauri keeps only the URL scheme documented here.
