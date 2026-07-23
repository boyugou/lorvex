//! Bulk Spotlight reindexing — list-scoped, by-id batches, and the
//! full two-phase delete-by-domain → index-batch sweep gated by the
//! `REINDEX_IN_FLIGHT` / `REINDEX_RERUN_REQUESTED` coordination
//! state declared in the parent module.

use std::sync::atomic::Ordering;

use objc2_core_spotlight::{CSSearchableIndex, CSSearchableItem};
use objc2_foundation::{NSArray, NSString};

use super::attributes::{build_attribute_set, build_searchable_item, log_error_block};
use super::per_task::{index_task, remove_all_tasks};
use super::query::read_spotlight_rows;
use super::SPOTLIGHT_DOMAIN;
use super::{spotlight_io_enabled, REINDEX_IN_FLIGHT, REINDEX_RERUN_REQUESTED, REINDEX_STATE_LOCK};

/// Reindex Spotlight entries for all open/someday tasks in a given list.
/// Call after list rename or task reassignment to update the `list_name`
/// in indexed task descriptions.
pub fn reindex_tasks_for_list(conn: &rusqlite::Connection, list_id: &str) {
    if !spotlight_io_enabled() {
        return;
    }
    // collapse the prepare/query_map/collect
    // boilerplate into the shared `read_spotlight_rows` helper.
    let Some(rows) = read_spotlight_rows(
        conn,
        &super::super::queries::select_by_list_id_sql(),
        rusqlite::params![list_id],
        "reindex_tasks_for_list",
    ) else {
        return;
    };

    for row in &rows {
        index_task(
            &row.id,
            &row.title,
            row.body.as_deref(),
            row.list_name.as_deref(),
            row.due_date.as_deref(),
        );
    }
}

/// Reindex Spotlight entries for specific tasks by their IDs.
/// Used after list-scoped writes that may change list metadata or task membership.
///
/// Batched against the OS layer: one SELECT with `WHERE id IN
/// (?...)` for the whole batch, one `indexSearchableItems` call for
/// the rows that still qualify, and one `deleteSearchableItems` call
/// for the IDs that disappeared (completed/cancelled or removed). A
/// per-task SELECT + CoreSpotlight call fan would turn a 500-task
/// manual sync into 1000 OS calls and a visible UI hitch.
pub fn reindex_tasks_by_ids(conn: &rusqlite::Connection, task_ids: &[String]) {
    if !spotlight_io_enabled() {
        return;
    }
    if task_ids.is_empty() {
        return;
    }

    // shared placeholder + projection helper.
    let sql = super::super::queries::select_by_id_batch_sql(task_ids.len());
    let params = super::super::queries::ids_as_params(task_ids);
    let Some(rows) = read_spotlight_rows(
        conn,
        &sql,
        rusqlite::params_from_iter(params),
        "reindex_tasks_by_ids",
    ) else {
        return;
    };

    // IDs that no longer qualify (not returned) should be removed
    // from the index in one delete call.
    let surviving: std::collections::HashSet<&str> = rows.iter().map(|r| r.id.as_str()).collect();
    let to_remove: Vec<&str> = task_ids
        .iter()
        .map(String::as_str)
        .filter(|id| !surviving.contains(id))
        .collect();

    if !rows.is_empty() {
        let items: Vec<objc2::rc::Retained<CSSearchableItem>> = rows
            .iter()
            .map(|row| {
                let attrs = build_attribute_set(
                    &row.id,
                    &row.title,
                    row.body.as_deref(),
                    row.list_name.as_deref(),
                    row.due_date.as_deref(),
                );
                build_searchable_item(&row.id, &attrs)
            })
            .collect();
        let ns_items = NSArray::from_retained_slice(&items);
        // SAFETY: see `index_task`.
        let index = unsafe { CSSearchableIndex::defaultSearchableIndex() };
        let handler = log_error_block("reindex_tasks_by_ids: index batch");
        // SAFETY: see `index_task`.
        unsafe {
            index.indexSearchableItems_completionHandler(&ns_items, Some(&handler));
        }
    }

    if !to_remove.is_empty() {
        let ns_ids: Vec<objc2::rc::Retained<NSString>> =
            to_remove.iter().map(|id| NSString::from_str(id)).collect();
        let identifiers = NSArray::from_retained_slice(&ns_ids);
        // SAFETY: see `index_task`.
        let index = unsafe { CSSearchableIndex::defaultSearchableIndex() };
        let handler = log_error_block("reindex_tasks_by_ids: delete batch");
        // SAFETY: see `remove_task`.
        unsafe {
            index.deleteSearchableItemsWithIdentifiers_completionHandler(
                &identifiers,
                Some(&handler),
            );
        }
    }
}

/// Reindex all tasks from the database into Spotlight.
///
/// Called on app startup. Deletes all existing entries for the domain,
/// then inserts all open/someday tasks in a single batch. Completed and
/// cancelled tasks are excluded — they are not useful in Spotlight search.
pub fn reindex_all_tasks() {
    if !spotlight_io_enabled() {
        return;
    }
    // Check if indexing is available on this system.
    // SAFETY: static class-method probe;
    // returns a `BOOL` and has no preconditions.
    if !unsafe { CSSearchableIndex::isIndexingAvailable() } {
        super::super::log_spotlight_error(
            "reindex_all_tasks",
            "Core Spotlight indexing is not available on this system",
        );
        return;
    }

    // serialize concurrent reindexes. If another
    // reindex is already in flight, request a rerun and return —
    // the in-flight reindex's completion block will re-enter
    // this path once it finishes. `REINDEX_STATE_LOCK` makes the
    // two-step "is in-flight? if not, mark in-flight" atomic;
    // without it two callers could both conclude they are the
    // first and race the OS calls.
    // the
    // `REINDEX_STATE_LOCK` is mandatory here because the load /
    // store pair on `REINDEX_IN_FLIGHT` is a TOCTOU. Two
    // concurrent triggers could otherwise both observe the flag
    // as `false`, both store `true`, and both race the
    // platform-side `MDQuery` calls — which is exactly the race
    // the surrounding comment warns about. The mutex collapses
    // the two atomics into a single critical section so the
    // "first observer wins, the rest set the rerun bit" property
    // holds. Poison recovery via `into_inner` keeps the lock
    // reusable after a panic in any prior reindex caller; the
    // protected state is just two booleans whose invariants are
    // re-asserted on every entry.
    {
        let _state_guard = REINDEX_STATE_LOCK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if REINDEX_IN_FLIGHT.load(Ordering::SeqCst) {
            REINDEX_RERUN_REQUESTED.store(true, Ordering::SeqCst);
            return;
        }
        REINDEX_IN_FLIGHT.store(true, Ordering::SeqCst);
        REINDEX_RERUN_REQUESTED.store(false, Ordering::SeqCst);
    }

    // Once the in-flight bit is set, every early return below
    // must clear it (otherwise a future trigger never fires).
    // Use a small helper struct so the clear path is centralized
    // and the completion-block path uses a separate manual clear.
    struct InFlightGuard;
    impl Drop for InFlightGuard {
        fn drop(&mut self) {
            REINDEX_IN_FLIGHT.store(false, Ordering::SeqCst);
            if REINDEX_RERUN_REQUESTED.swap(false, Ordering::SeqCst) {
                // A second trigger arrived during the early-
                // return path; honor it. Direct recursion is
                // safe — the in-flight bit is now false so the
                // re-entry will proceed normally.
                super::super::reindex_all_tasks();
            }
        }
    }
    // The synchronous-error early returns clear the gate via
    // this guard; the success path must `forget` it before
    // dispatching the OS work so the completion-block path
    // owns the clear instead.
    let in_flight_guard = InFlightGuard;

    let conn = match crate::db::get_read_conn() {
        Ok(c) => c,
        Err(e) => {
            super::super::log_spotlight_error(
                "reindex_all_tasks: failed to get DB connection",
                &e.to_string(),
            );
            return;
        }
    };

    // Query all indexable tasks (open + someday).
    // share the projection / visibility predicate via the
    // module-level `queries` helper so a future schema bump only
    // touches one place.
    let rows: Vec<super::super::queries::IndexableRow> =
        match super::super::queries::read_indexable_rows(
            &conn,
            &super::super::queries::select_all_sql(),
            [],
        ) {
            Ok(rows) => rows,
            Err(e) => {
                super::super::log_spotlight_error("reindex_all_tasks: read failed", &e.to_string());
                return;
            }
        };

    drop(conn);

    if rows.is_empty() {
        // No tasks to index — just clear any stale entries.
        remove_all_tasks();
        return;
    }

    // Build all searchable items.
    let items: Vec<objc2::rc::Retained<CSSearchableItem>> = rows
        .iter()
        .map(|row| {
            let attrs = build_attribute_set(
                &row.id,
                &row.title,
                row.body.as_deref(),
                row.list_name.as_deref(),
                row.due_date.as_deref(),
            );
            build_searchable_item(&row.id, &attrs)
        })
        .collect();

    let ns_items = NSArray::from_retained_slice(&items);
    // SAFETY: see `index_task`.
    let index = unsafe { CSSearchableIndex::defaultSearchableIndex() };

    // Two-phase reindex: clear the domain first, then insert fresh entries.
    // This ensures no stale entries linger (e.g. tasks completed between launches).
    let domain = NSString::from_str(SPOTLIGHT_DOMAIN);
    let domains = NSArray::from_retained_slice(&[domain]);

    // Panic safety (audit): both completion blocks below run on a
    // CoreSpotlight private dispatch queue. They reach into
    // `crate::db::get_conn()` (via `super::super::log_spotlight_error`)
    // and an inner spotlight call. Any panic crossing the
    // Objective-C → Rust boundary is undefined behavior on macOS,
    // so each block body runs inside `catch_unwind`.
    let clear_handler = block2::RcBlock::new(move |error: *mut objc2_foundation::NSError| {
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            if !error.is_null() {
                // SAFETY: null-checked
                // CoreSpotlight `NSError *`; the autoreleased
                // pointee outlives the closure body.
                let desc = unsafe { (*error).localizedDescription() };
                super::super::log_spotlight_error("reindex clear error", &desc.to_string());
                // Continue with insert anyway — partial reindex is better than none.
            }

            let insert_handler =
                block2::RcBlock::new(move |error: *mut objc2_foundation::NSError| {
                    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                        if error.is_null() {
                            // success path was a stray
                            // `eprintln!` that goes nowhere on packaged
                            // builds (no stderr surface) and is noise
                            // during `cargo run`. Drop it; the only
                            // diagnostic that matters is the failure
                            // path above (`super::super::log_spotlight_error`).
                        } else {
                            // SAFETY: same
                            // contract as the clear-handler error
                            // above — null-checked autoreleased
                            // `NSError *`.
                            let desc = unsafe { (*error).localizedDescription() };
                            super::super::log_spotlight_error(
                                "reindex insert error",
                                &desc.to_string(),
                            );
                        }
                        // this is the terminal
                        // completion of the two-step reindex.
                        // Clear the in-flight gate and honor any
                        // rerun request that arrived while we
                        // were running.
                        REINDEX_IN_FLIGHT.store(false, Ordering::SeqCst);
                        if REINDEX_RERUN_REQUESTED.swap(false, Ordering::SeqCst) {
                            super::super::reindex_all_tasks();
                        }
                    }));
                });
            // SAFETY: `ns_items` and
            // `insert_handler` outlive this dispatch (CoreSpotlight
            // retains both until the inner completion fires); the
            // default index is the live process singleton.
            unsafe {
                CSSearchableIndex::defaultSearchableIndex()
                    .indexSearchableItems_completionHandler(&ns_items, Some(&insert_handler));
            }
        }));
    });

    // hand ownership of the in-flight gate to
    // the inner completion handler. From this point on, the
    // gate must be cleared by `insert_handler` (terminal step
    // of the two-call reindex) — not by this function's drop.
    std::mem::forget(in_flight_guard);
    // SAFETY: `domains` and `clear_handler`
    // outlive this dispatch (CoreSpotlight retains both until
    // the completion fires); receiver is the live default index.
    unsafe {
        index.deleteSearchableItemsWithDomainIdentifiers_completionHandler(
            &domains,
            Some(&clear_handler),
        );
    }
}
