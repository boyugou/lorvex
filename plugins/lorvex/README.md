# Lorvex for Claude Code

This plugin connects Claude Code to Lorvex, the Apple-native task manager,
and adds four skills for the workflows that span many tools: planning a day,
capturing notes as tasks, the weekly review, and tidying the assistant's
memory.

## Requirements

- A Mac running macOS 26 or later with Lorvex installed and opened at least
  once. The plugin starts the MCP helper that ships inside the app, and that
  helper reads and writes the same database the app shows.
- Claude Code. In Claude Desktop and other MCP clients, connect Lorvex through
  the app instead: Settings → Assistant → Setup Prompt → Copy.

## Install

```
/plugin marketplace add boyugou/lorvex
/plugin install lorvex@lorvex
```

Then start a new Claude Code session.

If you connected Lorvex to Claude Code by hand before (for example with
`claude mcp add`), remove that entry with `claude mcp remove lorvex`, so the
Lorvex tools are not listed twice.

## What it adds

| Component | What it does |
|-----------|--------------|
| MCP server `lorvex` | Every Lorvex tool: tasks, lists, habits, calendar, the Today page and its briefing, reviews, and memory. |
| `/lorvex:plan-day` | Keeps a realistic set of tasks on today, explains why in a short briefing, and can time them around your meetings. |
| `/lorvex:capture` | Turns pasted notes or a brain dump into tasks, and asks about anything vague. |
| `/lorvex:weekly-review` | Summarizes the week (wins, slipped work, stalled lists), suggests changes, and applies the ones you choose. |
| `/lorvex:tidy-memory` | Reviews the notes the assistant keeps about you and proposes corrections. |

The skills also start on their own when a request matches, for example "what
should I work on today?".

## How it behaves

The helper tells every assistant session how to work with Lorvex: gather the
context a request needs, confirm anything vague, and explain each change. The
full playbook is [`docs/design/AI_OPERATING_MODEL.md`](../../docs/design/AI_OPERATING_MODEL.md).

Everything stays on your Mac. The helper is a local process that talks to
Claude Code over standard input and output, and Lorvex syncs your data
between your devices through your own iCloud account. Changes the assistant
makes are listed in the app's AI activity log unless you turn that log off.

## Updates

The plugin has no pinned version: Claude Code versions it by the commit it was
installed from, so every published change is an update. Run
`claude plugin update lorvex@lorvex` to fetch it, or turn on automatic updates
for the `lorvex` marketplace under `/plugin` → Marketplaces. The Lorvex tools
themselves come from the installed app and update with it.

## Troubleshooting

If the `lorvex` server fails to start, the launcher (`scripts/lorvex-mcp`)
could not find the app. It looks in `/Applications`, then `~/Applications`, then
asks Spotlight for the app's bundle identifier (`com.lorvex.apple`). Install
Lorvex from [lorvex.app](https://lorvex.app), open it once, and start a new
session. Run `/mcp` in Claude Code to see the server's status.
