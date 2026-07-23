# Scale Resilience Checklist (1k / 10k Tasks)

Purpose: validate large-dataset behavior and keep AI-facing MCP responses bounded.

Related issue: `#92` (extreme-scale resilience + context-budget safeguards).

## 1. Prepare Dataset

```bash
DB="$HOME/Library/Application Support/Lorvex/db.sqlite"

# 1k dataset
sqlite3 "$DB" ".parameter init" ".parameter set @max_n 1000" ".read scripts/fixtures/seed_scale.sql"

# 10k dataset
sqlite3 "$DB" ".parameter init" ".parameter set @max_n 10000" ".read scripts/fixtures/seed_scale.sql"
```

Sanity checks:

```bash
sqlite3 "$DB" "SELECT COUNT(*) FROM tasks WHERE id LIKE 'scale-%';"
sqlite3 "$DB" "SELECT status, COUNT(*) FROM tasks WHERE id LIKE 'scale-%' GROUP BY status ORDER BY status;"
```

## 2. MCP Guardrail Checks

### Automated Guard Coverage

Automated in MCP integration tests:

- Test name: `high-cardinality query tools remain bounded and expose truncation metadata`
- Harness entrypoint: `scripts/tests/mcp/integration.test.ts`
- Guard source: `scripts/tests/mcp/integration/query_bounds_and_scale/bounded_query_cases/high_cardinality.ts`
- Command:

```bash
npm run test:mcp:integration -- \
  --test-name-pattern="high-cardinality query tools remain bounded and expose truncation metadata" \
  scripts/tests/mcp/integration.test.ts
```

What this guard validates:

1. `list_tasks` enforces `limit`, returns bounded payloads, and reports `total_matching` + `truncated`.
2. `search_tasks` enforces `limit`, returns bounded payloads, and reports `total_matching` + `truncated`.
3. `get_deferred_tasks` enforces `limit`, keeps deferred-only results, and reports `total_matching` + `truncated`.
4. `get_todays_tasks` enforces `limit_per_bucket` and keeps `summary`/`truncated` metadata aligned with returned bucket counts.
5. `get_upcoming_tasks` enforces `limit`, preserves `day_counts` consistency, and reports `total_matching` + `truncated`.

### Automated Benchmark Sweep (1k / 5k / 10k)

Run reproducible benchmark sweeps from the repository root:

```bash
npm run benchmark:mcp:scale -- --dataset 1000,5000,10000 \
  --out artifacts/manual-gates/benchmark-scale-rust.json
```

Expected output:
- Per-tool latency (ms)
- Per-tool payload size (bytes)
- Metadata contract checks (`limit/returned/total_matching/truncated`)
- Summary worst-case latency and payload for each run

Run manually as part of the pre-release checklist (not wired to automated CI):
- Command: `npm run benchmark:mcp:scale -- --dataset=1000,10000`

### Optional Operator MCP Spot Checks (Release Confidence)

Run these from an MCP client (for example, Claude/Codex/etc.) when release confidence requires interactive verification:

1. `list_tasks` with no filters:
- Expect: `total_matching` present and `truncated=true` when dataset exceeds limit.
2. `search_tasks` on broad query (for example `query="Scale"`):
- Expect: `total_matching` + `truncated`.
3. `get_deferred_tasks`:
- Expect: `total_matching` + `truncated`.
4. `get_todays_tasks`:
- Expect per-bucket truncation metadata (`overdue`, `due_today`, `high_priority_undated`).
5. `get_upcoming_tasks`:
- Expect `total_matching` + `truncated`.

Pass criteria:
- No unbounded payload dump.
- Every high-cardinality query returns explicit truncation observability.
- Automated checks are green before issue closure; optional spot checks are recommended before release promotion.

## 3. App-Side Smoke Checks

### Automated App-Side Smoke (Headless)

Automated in Rust app unit tests:

- `commands::tests::app_scale_smoke_queries_remain_responsive_at_1k_dataset`
- `commands::tests::app_scale_smoke_queries_remain_responsive_at_10k_dataset`
- File: `app/src-tauri/src/commands.rs`
- Command:

```bash
cd app/src-tauri && cargo test app_scale_smoke_queries_remain_responsive_at_ -- --nocapture
```

Coverage mapping:

1. Today/Overview data path (`get_overview` query shape)
2. Deferred data path (`get_deferred_tasks` query shape)
3. All Tasks data path (`get_all_tasks` query shape)
4. Calendar data path (`get_events_by_date_range` query shape)
5. Settings data path (`get_all_lists` + preferences query shape)
6. Focus and review data path (`get_current_focus` + review query shape)

Pass criteria:
- No crash/test error.
- Per-path query latency remains under 3000ms at both 1k and 10k datasets.
- Core view data paths return non-empty representative payloads.

### Optional Interactive UI Spot Check

For pre-release confidence, run one manual UI pass on seeded data:

1. Launch app and switch core views (Today/All Tasks/Calendar/Upcoming/Settings).
2. Open command palette and run common jumps.
3. Scroll large lists and open task detail panel.
4. Run Focus entry/exit flow once.

Use this to catch renderer/animation regressions that headless query smoke cannot observe.

## 4. Engineering Verification Gate

Before marking work complete:

```bash
npm run verify:ci-typecheck
npm run test:mcp:integration
npm run benchmark:mcp:scale -- --dataset=1000,10000
cargo check --manifest-path mcp-server/Cargo.toml
cargo clippy --manifest-path mcp-server/Cargo.toml -- -D warnings
cargo test --manifest-path mcp-server/Cargo.toml
npm run typecheck:mcp-tests
npm run -w app typecheck
cargo clippy --manifest-path app/src-tauri/Cargo.toml --all-targets -- -D warnings
```

## 5. Regression Notes Template

Use this structure in issue comments / PR notes:

- Dataset size: `1k` or `10k`
- MCP tools checked: `list_tasks`, `search_tasks`, `get_deferred_tasks`, `get_todays_tasks`, `get_upcoming_tasks`
- Result: pass/fail per tool
- UI smoke: pass/fail + any freeze/crash notes
- Next action: fix / follow-up issue link
