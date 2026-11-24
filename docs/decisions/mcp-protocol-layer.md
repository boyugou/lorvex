# Decision record: Lorvex's own MCP protocol layer

**Status:** Accepted 2026-11-24. `LorvexMCPHost` serves MCP over stdio with its
own JSON-RPC layer and keeps the official Swift SDK
(`modelcontextprotocol/swift-sdk`) for its data types only.

## Context

The helper's value is its 122 tools and the core behind them. Until this
change, the SDK's `Server` and `StdioTransport` carried every message between
a client and those tools, and the SDK cost Lorvex four things, measured on the
release helper over a temporary database on 2026-11-23:

- **Arguments changed in transit.** The SDK decodes every incoming string
  through `Value`, which turns a string whose whole value is a data URL
  (`data:,hello`) into binary data. `create_task` then rejected that title as
  empty. Results take the same path on the way out, so a task titled that way
  came back as a base64 data URL. Upstream issue 277; the fixes are unmerged.
- **Slow listing.** Each response was encoded, decoded into `Value` and
  encoded again, and that decode rebuilt a regular expression for every
  string. `tools/list` (122 tools, about 165 KB) took 80 ms every time.
- **Only the older protocol.** The SDK speaks the versions that open with
  `initialize` (2025-11-25 and earlier). Specification 2026-07-28 removes that
  handshake: each request carries its version and the client's capabilities
  in `_meta`, and servers must implement `server/discover`. Claude Code,
  Claude Desktop and Codex on the owner's Mac already contain the new version
  and fall back to `initialize` when a server does not answer the probe; a
  client that drops the fallback cannot use Lorvex.
- **Fragile upgrades.** Codex's object-valued experimental capabilities broke
  the SDK's `initialize` decoding (fixed in build 177 by filtering the
  request), and the SDK's main branch traps when stdin and stdout are Unix
  sockets, which is how Claude Code and Claude Desktop launch the helper.

Switching the helper to the Rust SDK was considered and not taken (ROADMAP,
"Decided, not open"): the protocol layer is a few hundred lines, and every
Rust route needs either an FFI bridge into the Swift core or a second
implementation of it.

## Decision

Lorvex owns the stdio transport, JSON-RPC framing and method dispatch. The
SDK's `Tool`, `Value`, `CallTool` and `Initialize` types stay: the tool
definitions, handlers, fencing and idempotency use them, and reusing
`Initialize.Result` and `CallTool.Result` keeps the older protocol's output
identical.

### Which protocol a request gets

A request's own `params._meta` decides, so one process can serve both eras:

- `initialize` always starts the older protocol for the connection. The
  version is negotiated as the SDK did: the client's version when Lorvex
  knows it, otherwise 2025-11-25. A second `initialize` is rejected.
- A request whose `_meta` holds any of the three per-request keys,
  `io.modelcontextprotocol/protocolVersion`, `.../clientCapabilities` or
  `.../clientInfo`, is a 2026-07-28 request. Its version must be present and
  be `2026-07-28`: a missing version gets -32602, another version gets error
  -32022 with `data.supported` and `data.requested`. Its capabilities must be
  an object, or the reply is -32602. Other `io.modelcontextprotocol/` keys
  (such as `related-task`) also occur in older-protocol requests, so they do
  not select the newer protocol.
- `server/discover` exists only in the newer protocol; without that metadata
  it gets -32602.
- Any other request without that metadata is served under the older protocol,
  whether or not `initialize` came first, as the SDK's lenient mode did.

`server/discover` advertises only `2026-07-28`. The older versions stay
reachable through `initialize`, which is how a client that does not know the
new version arrives. A client picks the first of its own preferred versions
that the server lists, so listing older versions there would invite inline
requests at an older version, which nothing needs.

### What each protocol's results look like

The older protocol's results are the SDK types' own encoding, byte for byte
the same objects as before.

A 2026-07-28 result also carries `resultType: "complete"` and
`_meta["io.modelcontextprotocol/serverInfo"]` (name, title, version), merged
with any `_meta` the result already has. `tools/list` and `server/discover`
also carry `ttlMs: 300000` and `cacheScope: "private"`. The catalog changes
only when the app updates, and five minutes bounds how long a client may show
the old catalog afterwards. `private` costs nothing on stdio, where there are
no shared caches.

Both protocols get `tools/list` and `tools/call`. `initialize` and
`server/discover` belong to one protocol each. `ping` belongs to the older
protocol; 2026-07-28 removed it, but Lorvex answers it there too, since that
costs nothing and keeps working for a client that still sends it. Every other
method gets -32601. Lorvex declares only tools, with `listChanged:
false`, and sends no requests or notifications of its own.

### Bytes on the wire

- Incoming JSON is decoded without guessing: a string stays a string. The
  decoding otherwise matches the SDK's (null, then Bool, Int, Double, String,
  array, object), so numbers reach the tools exactly as before.
- Each result is encoded once and placed into the response frame. The
  `tools/list` result for each protocol is encoded on first use and reused for
  the rest of the process.
- Frames are compact JSON with sorted keys and unescaped slashes, as before,
  followed by one newline. JSON encoding escapes newlines inside strings, so a
  frame is always one line.
- A parse failure gets -32700 without an id. A JSON value that is not a valid
  request, including a request with a null or fractional id, gets -32600,
  also without an id. MCP's error response leaves the id out when it cannot
  be read (`id?: RequestId`) where JSON-RPC writes `null`; a client that
  checks frames against MCP's schema can reject the `null`.
  Responses from the client are ignored, as are notifications other than
  `notifications/cancelled`.
- A JSON array is a batch, accepted for clients of 2025-03-26: its requests
  run in order and their responses go out as one array. An empty array gets
  -32600.

### Concurrency, cancellation and shutdown

- A dedicated thread reads stdin with `read(2)`, so pipes and sockets behave
  the same and nothing polls on a timer. The descriptors' flags stay as the
  client set them; one the client made non-blocking is waited on with
  `poll(2)`. Between reads the reader keeps only the unfinished line, so a
  session that runs for days does not hold everything it has read.
- Each request runs in its own task, so a slow tool call does not hold up a
  listing. A serial writer queue writes each frame whole and in the order
  frames are produced; a slow reader on the other end never blocks a Swift
  concurrency thread.
- `notifications/cancelled` cancels the named request's task. A cancelled
  request gets no response, even if its work finished anyway, as the
  2026-07-28 stdio binding requires. A client that needs to know whether a
  cancelled write happened retries it with the same idempotency key.
- At end of input the server stops reading, waits for the requests already
  running, writes their responses, and returns, so the process exits. Tool
  calls are bounded by the core's lock and busy timeouts, so the wait ends.
- The host ignores `SIGPIPE`. After a failed write the writer drops later
  frames, and the process ends when its input closes.
- `SIGINT` and `SIGTERM` keep their default action and end the process at
  once; Claude Code ends a session with `SIGINT`. A request still running
  then gets no response, which a client already handles as it does a lost
  connection. Each write is one SQLite transaction, so nothing is left half
  written, and an idempotency key makes the retry safe.

## Checked against the real clients

On 2026-11-24, on the owner's Mac, each client ran one headless session
against the development helper over a temporary database:

- **Claude Code 2.1.331** (`claude -p` with `--strict-mcp-config`) probed
  with `server/discover`, logged `protocolEra: "modern"` and
  `negotiatedProtocolVersion: "2026-07-28"`, listed 122 tools and called
  `get_overview` (14 ms by its log). The helper exited cleanly when the
  session ended.
- **Codex 0.170.0** (`codex exec`, its `lorvex` entry pointed at the
  development helper) sent `initialize` with 2025-06-18 and its experimental
  capabilities, and called `get_overview`.

Timed with the release build over a temporary database, the median of 20
launches after a first one: `initialize` 22.3 ms after launch (22 ms
before), `tools/list` 3.4 ms (80 ms before), `get_overview` 2.2 ms (7 ms
before). The listing is 165,482 bytes, and `MCPServerHostTests` checks that
it equals the SDK's own encoding of the catalog.

## Consequences

- The data-URL guess, the triple encoding and the `initialize` filter are
  gone, along with `ClientCapabilityTolerantTransport`.
- A client that speaks 2026-07-28 now uses it with Lorvex. Claude Code probes
  with `server/discover` first, so this changes the path its every request
  takes. The release is checked against the real clients on this Mac, not
  only the smoke test.
- Lorvex follows the protocol's changes itself. Its surface is tools only, so
  a protocol revision touches this layer and its tests, not the tools.
- The SDK stays pinned to one release. An upgrade can change how its types
  encode, which is now the only way it reaches the wire.
