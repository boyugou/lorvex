// trust: tests intentionally use unwrap() / expect() for assertion clarity —
// panics there ARE the failure mode.
#![cfg_attr(test, allow(clippy::unwrap_used))]

//! `lorvex-cli` — agent-first CLI for Lorvex.
//!
//! Thin `main.rs` entry point that parses CLI args, applies DB-path
//! overrides + HLC guards, then routes to per-area handlers under
//! `commands/`. The CLI is a sibling write surface to the Tauri app
//! and MCP server: it shares the same `lorvex-workflow` operations,
//! the same outbox enqueue, and the same capability profile lookup
//! through `lorvex-runtime`.
//!
//! Output formatting is pluggable via `render` (table / json / tui).
//! `cli_rate_limit` gates write throughput per-process so a script
//! that fans out adjustments cannot starve the local outbox.

mod cli;
mod cli_rate_limit;
mod commands;
mod dispatch;
mod error;
mod format_override;
mod hlc_guard;
mod models;
mod render;
mod startup_maintenance;
mod tui;
mod verbosity;

use cli::CliArgs;

/// Entry point.
///
/// `apply_db_path_override` (which does `unsafe { env::set_var(...) }`)
/// from inside the now-running multi-threaded runtime. The comment
/// claimed "still single-threaded at this point" but `#[tokio::main]`
/// has already initialised worker threads by the time the body runs;
/// any `env::set_var` race against another thread reading
/// environment variables is undefined behavior on most platforms.
///
/// Fix: do the env munging in a sync `main()` BEFORE constructing the
/// runtime. The runtime is built explicitly via `tokio::runtime::Builder`
/// so we control exactly when worker threads exist relative to env
/// mutation.
fn main() {
    // Stage 1 (single-threaded): extract `--db-path` and stamp DB_PATH
    // BEFORE any tokio thread starts. `env::set_var` is sound here
    // because no other thread exists yet.
    let raw_args_with_db: Vec<String> = std::env::args().skip(1).collect();
    let raw_args = match apply_db_path_override(raw_args_with_db) {
        Ok(args) => args,
        Err(cli_error) => {
            // pre-clap arg failures classify through the typed
            // `CliError` exit-code machinery just like post-clap
            // failures do. The previous shape returned
            // `Box<dyn std::error::Error>`, which the surrounding
            // `exit_code_for_error` walker could not downcast to a
            // `CliError` — every `--db-path` rejection silently fell
            // back to exit 1 instead of EX_DATAERR (65). Returning
            // `CliError` directly closes that gap.
            eprintln!("Error: {cli_error}");
            std::process::exit(cli_error.exit_code());
        }
    };

    // Stage 2: build the tokio runtime and dispatch to async `run`.
    let runtime = match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    {
        Ok(rt) => rt,
        Err(e) => {
            eprintln!("Error: failed to build tokio runtime: {e}");
            std::process::exit(1);
        }
    };

    if let Err(e) = runtime.block_on(run(raw_args)) {
        let exit_code = e.exit_code();
        let kind = e.kind();
        // walk the error chain so users see the root
        // cause, not just the outermost wrapper. "Error: failed to
        // open db" with no continuation hides "sqlite: database is
        // locked" / "permission denied" / etc. The leading `[kind]`
        // tag gives shell consumers a stable, machine-readable error
        // class without substring-matching the message.
        eprintln!("Error [{kind}]: {e}");
        let mut source = std::error::Error::source(&e);
        while let Some(cause) = source {
            eprintln!("  caused by: {cause}");
            source = cause.source();
        }
        // Per-kind follow-up suggestion beneath the error chain.
        // `style_next_action` collapses to plain text under
        // `NO_COLOR=1` or non-TTY stderr, so piped output (and the
        // JSON error envelope, which doesn't reach this branch) stay
        // byte-clean. Hints are best-effort: transparent wrappers
        // (Sql / Io / etc.) return None, in which case the upstream
        // "caused by" chain is the most informative thing we can
        // surface and a generic suggestion would be noise.
        if let Some(hint) = e.next_action_hint() {
            eprintln!("{}", render::style_next_action(hint));
        }
        std::process::exit(exit_code);
    }
}

/// Async dispatch shell. Strips the global `-v`/`--verbose`/`-q`/`--quiet`
/// and `--format text|json` flags from argv (they are order-independent and
/// composable — each helper strips its flags and returns the rest), parses
/// the residual argv with clap, then hands the resulting [`CliArgs::command`]
/// off to the per-domain dispatchers in [`crate::dispatch`].
///
/// The global `--db-path <PATH>` flag is extracted in sync `main()` BEFORE
/// the tokio runtime spawns, so the `env::set_var` call lands single-threaded.
/// We receive the post-extract argv here and continue with the rest of the
/// global overrides.
async fn run(raw_args: Vec<String>) -> Result<(), error::CliError> {
    // Issues #2309 + #2328 introduced these extractions: `-v`/`--verbose`
    // (repeatable) and `-q`/`--quiet` for logging verbosity, and
    // `--format text|json` for the process-wide default output format.
    let (raw_args, log_level) = verbosity::extract_verbosity_override(raw_args);
    verbosity::set_level(log_level);
    let (raw_args, explicit_format) = format_override::extract_format_override(raw_args)?;
    if let Some(fmt) = explicit_format {
        format_override::set_default_output_format(fmt);
    }

    verbosity::cli_log!(Debug, "resolved log level = {log_level:?}");
    verbosity::cli_log!(
        Debug,
        "default output format = {:?}",
        format_override::default_output_format()
    );

    let args = CliArgs::parse(raw_args);
    // `--help`, `-h`, `--version`, `-V`, unknown subcommands, and bad args
    // are all handled by clap inside `CliArgs::parse`: clap prints the
    // rendered message and exits with 0 (help/version) or 2 (usage error)
    // before this dispatch runs. See #2316 (clap migration) +
    // #2167 (unknown-command exit 2).
    dispatch::dispatch_command(args.command).await
}

/// extract `--db-path <PATH>` (or `--db-path=<PATH>`) from
/// the arg list, validate that the target is a real file path (not a
/// directory / symlink), ensure its parent directory exists, and set
/// `DB_PATH` so `resolve_db_path()` picks it up. Returns the
/// remaining args with the flag stripped.
///
/// Precedence: CLI flag > existing env var > platform default. We
/// overwrite the env var so there's no ambiguity if the caller also
/// exported `DB_PATH`.
fn apply_db_path_override(args: Vec<String>) -> Result<Vec<String>, error::CliError> {
    let mut override_path: Option<String> = None;
    let mut remaining: Vec<String> = Vec::with_capacity(args.len());
    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        if let Some(value) = arg.strip_prefix("--db-path=") {
            override_path = Some(value.to_string());
        } else if arg == "--db-path" {
            let value = iter.next().ok_or_else(|| {
                error::CliError::Validation(
                    "--db-path requires a value: `lorvex --db-path /path/to/db.sqlite ...`"
                        .to_string(),
                )
            })?;
            override_path = Some(value);
        } else {
            remaining.push(arg);
        }
    }

    if let Some(path_str) = override_path {
        use std::path::Path;
        let path = Path::new(&path_str);
        // Reject non-file targets to avoid `/dev/null` footguns.
        if path.exists() {
            let meta = std::fs::symlink_metadata(path)?;
            if meta.file_type().is_symlink() {
                return Err(error::CliError::Validation(format!(
                    "--db-path '{path_str}' is a symlink; pass the resolved path instead"
                )));
            }
            if meta.is_dir() {
                return Err(error::CliError::Validation(format!(
                    "--db-path '{path_str}' is a directory"
                )));
            }
        } else if let Some(parent) = path.parent() {
            // M4. The previous branch silently
            // ran \`create_dir_all\` against the user-supplied parent,
            // which made the CLI happy to materialize directory trees
            // anywhere on the filesystem the process had write
            // permission. A typo (\`--db-path /tnp/db.sqlite\`) or a
            // hostile shell wrapper could plant a directory tree in
            // an unexpected location, and the resulting SQLite file
            // landed where no caller ever inspected it. Requiring
            // the parent to already exist closes that surface — a
            // legitimate operator who wants the CLI to write to a
            // non-default path can \`mkdir -p\` once and re-issue
            // the command, while a typo or hostile wrapper now fails
            // loudly at the trust boundary instead of silently
            // creating filesystem state.
            if !parent.as_os_str().is_empty() && !parent.exists() {
                return Err(error::CliError::Validation(format!(
                    "--db-path parent '{}' does not exist; create the directory first \
                     (lorvex will not auto-create arbitrary filesystem paths)",
                    parent.display()
                )));
            }
        }
        // SAFETY: env::set_var requires no concurrent reads of the
        // environment. This function is now called
        // from sync `main()` BEFORE the tokio runtime is built, so no
        // other thread exists at this point. The `tokio::runtime::Builder`
        // call in `main` is what spawns worker threads; that happens
        // after this function returns.
        // path violated the contract because the attribute had already
        // initialised the runtime by the time the body ran.
        unsafe {
            std::env::set_var("DB_PATH", path_str);
        }
    }

    Ok(remaining)
}

#[cfg(test)]
mod tests;
