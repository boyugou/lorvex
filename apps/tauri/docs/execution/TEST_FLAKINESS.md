# Test-Flakiness Playbook

This playbook is the canonical entry point for diagnosing test-setup failures that surface as opaque IO errors (ENOSPC, EACCES, EBUSY) on CI runners. Origin issue: [#2544](https://github.com/boyugou/ai-native-todo/issues/2544) (closed; playbook lives on as the canonical reference).

## When to use this doc

Use this playbook when a test fails during *setup* — i.e., before its own assertions run — with one of these signatures:

- `rusqlite::Error("disk I/O error")` from a call inside `Connection::open()`, `PRAGMA journal_mode`, or migration application.
- `io::Error("Permission denied")` from `fs::create_dir_all` or `tempfile::tempdir()`.
- `io::Error("No space left on device")` from any write inside a test fixture.
- A `test-setup:` prefix in the panic message — this means the fix from #2544 is active and has already gathered context for you. Read the rest of the panic line: it contains the path attempted, free bytes remaining, writability probe result, and `$TMPDIR` value.

## Diagnostic helper

`lorvex_store::test_support::diag` (feature `test-support`) exposes:

| Helper                                  | Returns                                | Use when                                                                         |
| --------------------------------------- | -------------------------------------- | -------------------------------------------------------------------------------- |
| `open_test_db_with_diag()`              | `(Connection, DiagContext)`            | You want an in-memory SQLite with diagnostic metadata on failure.                |
| `open_test_db_at_temp_path_with_diag()` | `(Connection, PathBuf, DiagContext)`   | You need a real `.db` file (WAL tests, path-based opener tests).                 |
| `unique_test_dir_with_diag()`           | `(PathBuf, DiagContext)`               | Your test writes files (not SQLite) — e.g. widget snapshots, export fixtures.    |

All three return a `TestSetupError` whose `Display` impl includes:

- The attempted path
- `$TMPDIR` at attempt time (for spotting CI overrides onto slow network mounts)
- Free bytes on the backing filesystem (via `statvfs` on Unix; `None` on Windows/other)
- The writability probe result (a 1-byte create+remove against the parent)
- The underlying `io::Error` / `rusqlite::Error` + `errno`
- A pointer back to this playbook

## Failure modes and remediations

### ENOSPC on crowded runners

`/tmp` is typically tmpfs, RAM-backed, often 512 MB. Parallel test binaries can fill it mid-run.

- **Short-term:** set `TMPDIR=<repo>/target/tmp` on the CI job so tempfiles land in the workspace's disk quota.
- **Structural fix:** migrate the test to use `CARGO_TARGET_TMPDIR` (points to `target/tmp` on CI) when set. See `lorvex_store::test_support::diag::allocate_temp_path` for the canonical allocator.

### EACCES / Permission denied

Usually a leftover directory from a previous run owned by a different UID (rootless containers).

- Delete `$TMPDIR/lorvex-tests/` before the test run.
- Check that the runner's umask isn't 077 — the 1-byte writability probe in `probe_writability` will catch this at test-setup time.

### Noexec mount flag

Some hardened runners mount `/tmp` with `noexec`. SQLite WAL spillover can hit this.

- Fix by setting `TMPDIR` to a non-noexec path, typically `$HOME/.cache/lorvex-tests`.

### TMPDIR override onto slow NFS

If CI sets `TMPDIR` to a network mount for disk-space reasons, fsync-heavy SQLite tests become 100× slower and hit `PRAGMA busy_timeout`.

- The `DiagContext.tmpdir` field will show the unexpected path — that's your first clue.
- Revert to the default `/tmp` or use a local SSD scratch path.

## Simulating failures locally

The `fault` submodule exposes thread-local RAII guards so you can simulate ENOSPC / EACCES without actually filling the disk:

```rust
use lorvex_store::test_support::diag::{self, WritabilityProbe};

let _probe_guard = diag::fault::WritabilityGuard::new(WritabilityProbe::Rejected {
    reason: "No space left on device (simulated, errno: Some(28))".to_string(),
});
let _free_guard = diag::fault::FreeBytesGuard::new(Some(0));

let err = diag::unique_test_dir_with_diag("my-test").unwrap_err();
// err now renders with free_bytes=0 and the simulated reason.
```

The guards are thread-scoped (not global), so parallel tests won't interfere with each other.

## Migration status

Tracked under #2544. The helpers landed in the commit tagged `test-infra: add rich diagnostics to temp-DB setup helper (#2544)`. Migration of call sites is incremental — start with anything that touches `tempfile::tempdir()` + SQLite; the store crate's `connection.rs` tests and export/import persistence tests are the reference patterns.
