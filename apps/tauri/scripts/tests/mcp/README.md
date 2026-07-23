# MCP Runtime Harness

## Scope

`integration.test.ts` runs against the Rust MCP server process over stdio and a real SQLite database (`DB_PATH` set to a temp file). It validates:

1. Representative write tool persistence (`create_task` writes `tasks`)
2. `ai_changelog` entry creation
3. `sync_outbox` queue entry creation
4. `export_all_data` -> `import_data` roundtrip sanity (cross-DB)
5. Representative Rust-only write invariants for changelog and sync-outbox behavior

`contracts.test.ts` adds frozen runtime-surface guardrails:

5. Frozen MCP tool contract snapshot (fixture `schema_version`, tool name, top-level description hash, and input schema hash)
6. Golden behavior cases for representative tool output shapes

`benchmark.scale.ts` is a Rust-only benchmark/profiling harness for bounded payload and latency checks across larger seeded datasets.

`generate_tool_contract_fixture.ts` intentionally refreshes the frozen tool contract fixture after approved MCP contract changes.

## Run

From repository root:

```bash
npm run test:mcp:integration
```

To intentionally update the frozen tool-contract fixture after approved contract changes:

```bash
npm run test:mcp:contracts:update
```

To typecheck the Node/TypeScript harness itself:

```bash
npm run typecheck:mcp-tests
```

To run the Rust-only scale benchmark harness:

```bash
npm run benchmark:mcp:scale -- --dataset=1000,10000
```
