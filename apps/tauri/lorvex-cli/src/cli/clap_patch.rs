//! Small `Option`/`Vec`-juggling combinators that bridge clap-derive
//! field shapes into the typed `Patch<T>` / `Option<Vec<T>>` shapes
//! that downstream mutation translators expect.

pub(super) fn tri_state_clearable<T>(value: Option<T>, clear: bool) -> lorvex_domain::Patch<T> {
    if clear {
        lorvex_domain::Patch::Clear
    } else {
        match value {
            Some(v) => lorvex_domain::Patch::Set(v),
            None => lorvex_domain::Patch::Unset,
        }
    }
}

pub(super) fn optional_vec_patch(value: Vec<String>) -> Option<Vec<String>> {
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}

/// Resolve a clap-style `(positive, negative)` mutually-exclusive
/// flag pair into the user's intent: `Some(true)` if the positive
/// flag was set, `Some(false)` if the negative flag was set, `None`
/// when neither (or both) was supplied. Used both for filter
/// predicates (`--has-x` / `--no-x`) and policy-toggle flag pairs
/// (`--enable` / `--disable`); the shape is identical so they share
/// one helper.
pub(super) const fn mutually_exclusive_bool(positive: bool, negative: bool) -> Option<bool> {
    match (positive, negative) {
        (true, false) => Some(true),
        (false, true) => Some(false),
        _ => None,
    }
}
