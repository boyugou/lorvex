//! process-wide default output format, driven by a top-level
//! `--format text|json` flag extracted from raw args before clap
//! parses subcommands. Scripts that want JSON output pass the global
//! flag once instead of relying on command-local output options.
//!
//! Exit-code convention: queries always exit 0 regardless of row count
//! (no `grep`-style "no match → exit 1"). Runtime errors still exit 1
//! via `main.rs`. This is documented in `lorvex --help`.
//!
//! Flag parsing mirrors `apply_db_path_override` in `main.rs`: additive,
//! ahead of the positional parser, and happy to leave unknown args
//! untouched.

use std::sync::atomic::{AtomicU8, Ordering};

use crate::cli::OutputFormat;
use crate::error::CliError;

const TEXT: u8 = 0;
const JSON: u8 = 1;

static DEFAULT_FORMAT: AtomicU8 = AtomicU8::new(TEXT);

/// Parsed value of the global `--format` flag.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum FormatOverride {
    Text,
    Json,
}

/// Set the process-wide default output format. Called once from
/// `main.rs` after flag extraction.
pub(crate) fn set_default_output_format(format: FormatOverride) {
    let code = match format {
        FormatOverride::Text => TEXT,
        FormatOverride::Json => JSON,
    };
    DEFAULT_FORMAT.store(code, Ordering::Relaxed);
}

/// Read the process-wide default output format.
pub(crate) fn default_output_format() -> OutputFormat {
    match DEFAULT_FORMAT.load(Ordering::Relaxed) {
        JSON => OutputFormat::Json,
        _ => OutputFormat::Text,
    }
}

/// Extract `--format <text|json>` (or `--format=<value>`) from the
/// raw arg list. Returns the remaining args with the flag stripped and
/// the resolved format. Unknown values fail with a clear error. If the
/// flag is absent the caller's current default is preserved.
pub(crate) fn extract_format_override(
    args: Vec<String>,
) -> Result<(Vec<String>, Option<FormatOverride>), CliError> {
    let mut selected: Option<FormatOverride> = None;
    let mut remaining: Vec<String> = Vec::with_capacity(args.len());
    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        if let Some(value) = arg.strip_prefix("--format=") {
            selected = Some(parse_format_value(value)?);
        } else if arg == "--format" {
            let value = iter.next().ok_or_else(|| {
                CliError::Validation("--format requires a value: text | json".to_string())
            })?;
            selected = Some(parse_format_value(&value)?);
        } else {
            remaining.push(arg);
        }
    }
    Ok((remaining, selected))
}

// pre-clap arg validators must classify through `CliError`
// so the exit code matches the rest of the input-validation surface
// (EX_DATAERR = 65). Returning `String` fell off the
// downcast path inside `exit_code_for_error` and produced a generic
// exit 1 instead.
fn parse_format_value(raw: &str) -> Result<FormatOverride, CliError> {
    match raw.trim() {
        "text" => Ok(FormatOverride::Text),
        "json" => Ok(FormatOverride::Json),
        other => Err(CliError::Validation(format!(
            "--format '{other}' is not recognized; expected one of: text, json"
        ))),
    }
}

#[cfg(test)]
mod tests;
