//! Thin re-export wrapper around the consolidated recurrence primitives in
//! `lorvex_store::calendar_timeline::recurrence`.
//!
//! This module held a full local copy (including a buggy 2-arg
//! `add_months_clamped`). It now delegates to the single source of truth in
//! `lorvex-store`.

#[cfg(test)]
mod tests;
