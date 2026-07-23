# Connecting Your AI Assistant to Lorvex

Lorvex uses [MCP (Model Context Protocol)](https://modelcontextprotocol.io) over **stdio** to connect with AI assistants. Your assistant launches the Lorvex MCP server locally — no daemon, no network port.

This is the best automation experience on capable desktop runtimes. Lorvex still remains a strong standalone app even when MCP is unavailable or impractical on a given runtime.

## Quickest Setup (Any Platform)

**Option A: Lorvex CLI** (recommended if CLI is installed)

```bash
lorvex setup --install-mcp-for claude-code    # or: claude-desktop, codex, all
lorvex doctor                           # verify configuration
```

**Option B: Lorvex App**

1. Open **Lorvex** → **Settings** → **Assistant MCP**
2. Click **"Copy Setup Prompt"**
3. Paste it into your AI assistant (Claude, Codex, etc.)
4. The AI will configure itself automatically

Both paths produce the same functional result — a working Lorvex MCP integration.

They do **not** necessarily point to the same host shape:

- the **CLI path** typically configures `lorvex mcp serve`
- the **App path** typically configures the App's embedded/bundled MCP helper

Only one Lorvex MCP host should be active in a given client config at a time.
When both App and CLI are installed, the CLI is the preferred external MCP
host. When the CLI is absent and the App's embedded MCP helper is available,
Settings → Assistant MCP records the App as the active host for app-only
setups. If the CLI holds authority on disk, the App only reclaims it when
the recorded CLI executable path is gone, so custom CLI installs are not
overwritten by path-detection heuristics.

## Manual Setup

If you prefer to configure manually, click **"Show Manual Config"** in Settings → Assistant MCP, then copy the snippet for your specific client.

### Client Config File Locations

| Client | macOS | Windows | Linux |
|--------|-------|---------|-------|
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` | `%APPDATA%\Claude\claude_desktop_config.json` | `~/.config/Claude/claude_desktop_config.json` |
| Claude Code | `~/.claude.json` | `%USERPROFILE%\.claude.json` | `~/.claude.json` |
| Codex | `~/.codex/config.toml` | `%USERPROFILE%\.codex\config.toml` | `~/.codex/config.toml` |

### Config Format Examples

**Claude Desktop** (JSON — add to `mcpServers` object):
```json
{
  "mcpServers": {
    "lorvex": {
      "command": "<path from Lorvex Settings>",
      "args": ["<args from Lorvex Settings>"]
    }
  }
}
```

**Claude Code** (JSON — add to `mcpServers` object):
```json
{
  "mcpServers": {
    "lorvex": {
      "type": "stdio",
      "command": "<path from Lorvex Settings>",
      "args": ["<args from Lorvex Settings>"]
    }
  }
}
```

**Codex** (TOML — add `[mcp_servers.lorvex]` section):
```toml
[mcp_servers.lorvex]
command = "<path from Lorvex Settings>"
args = ["<args from Lorvex Settings>"]
startup_timeout_sec = 20
tool_timeout_sec = 120
```

### Verification

After configuring, run one read tool to verify:
```
get_overview
```
It should return your task lists and stats.

## Known Client Differences

- **Codex** supports `cwd` and timeout fields (`startup_timeout_sec`, `tool_timeout_sec`)
- **Claude Desktop** is tolerant and works well with absolute binary paths
- **Claude Code** can be stricter: prefer absolute MCP server binary path
- After any MCP config change, restart the assistant process/session
- If both App and CLI are installed, keep only one active Lorvex MCP registration in the client config

### MCP Client Compatibility

| Client | Status | Notes |
|--------|--------|-------|
| Claude Desktop | Verified | JSON `mcpServers` config with an absolute binary path |
| Claude Code | Verified | JSON config with `type: "stdio"`; prefer the absolute MCP server binary path |
| Codex | Verified | TOML config with startup/tool timeouts |
| VS Code MCP clients | Supported by contract | Use stdio MCP config if the client accepts a command plus args |
| Kimi Code CLI | Unverified | MCP-compatible in principle; validate with `get_overview` after setup |
| Tongyi Lingma | Unverified | MCP-compatible in principle; validate with `get_overview` after setup |
| Cherry Studio | Unverified | MCP-compatible in principle; validate with `get_overview` after setup |

## For Developers (Source Checkout)

If you're working from the source repo instead of the installed app:

```bash
# Build Rust MCP runtime binaries
npm run -w app prepare:mcp -- --debug

# Binary path:
# <repo>/mcp-server/bin/lorvex-mcp-server
```

Config for source checkout:
- **command**: absolute path to `<repo>/mcp-server/bin/lorvex-mcp-server`
- **args**: `[]`

## Tool Calling Input Shape

Prefer canonical JSON types:

- Numeric fields as JSON numbers: `priority: 1`, `target_count: 3`
- Arrays as JSON arrays: `tags: ["work", "urgent"]`
- Dates as ISO strings: `due_date: "2026-03-15"` (also accepts `today` / `tomorrow`)
- Boolean fields must be JSON booleans, numeric fields must be JSON numbers
- Type mismatches should be fixed in the calling client instead of relying on runtime-side coercion

## Retry and Idempotency

Retryable write tools may expose an optional `idempotency_key`. Generate a fresh opaque key for each intended mutation. If the assistant loses its session, times out, or sees another transient transport failure after sending the request, retry the same tool with the exact same payload and the same key.

Lorvex stores successful write responses in the local SQLite `mcp_idempotency` table for ~24h and replays the cached response for matching retries. Do not reuse an `idempotency_key` for an edited payload or a different tool call: the server compares `request_checksum` and rejects mismatched reuse instead of returning a stale response. See the generated [MCP tools reference](../design/MCP_TOOLS.md#write-retry-and-idempotency) for the tool-facing contract.

## Environment Variables

- **`LORVEX_AGENT_NAME`** (optional) — stamps the `initiated_by` column of `ai_changelog` for every write made through this process. Unset or empty defaults to `"ai"` for the MCP server and `"human"` for the CLI. When an AI agent (Claude Code, Codex, etc.) shells out to `lorvex capture`/`lorvex defer`/etc., set this in the environment (e.g. `LORVEX_AGENT_NAME=claude-code`) so the changelog attribution is accurate. Without it, agent-driven CLI writes are indistinguishable from direct human CLI writes.

## Notes

- Rust binary launch is the supported desktop baseline — the MCP server is a native Rust binary, not a Node.js process
- The app does **not** host a long-lived MCP daemon — clients launch MCP on demand
- Both app and MCP server share the same SQLite database:
  - macOS: `~/Library/Application Support/Lorvex/db.sqlite`
  - Windows: `%APPDATA%\Lorvex\db.sqlite`
  - Linux: `${XDG_DATA_HOME:-~/.local/share}/Lorvex/db.sqlite`
- Use absolute paths for reliability
- After changing MCP config, restart your assistant client to apply changes

## Naming Note

For terminology consistency across docs:

- `embedded MCP` = App-hosted MCP helper/runtime
- `CLI-hosted MCP` = `lorvex mcp serve`
- `Active MCP Host` = whichever one is currently configured for the client

See `docs/design/naming/AI_SURFACES.md` for the canonical naming model.
