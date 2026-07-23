//! Single-task CoreSpotlight operations: index one task, remove one
//! task by id, and remove every Lorvex task by domain identifier.

use objc2_core_spotlight::CSSearchableIndex;
use objc2_foundation::{NSArray, NSString};

use super::attributes::{build_attribute_set, build_searchable_item, log_error_block};
use super::spotlight_io_enabled;
use super::SPOTLIGHT_DOMAIN;

/// Index (or update) a single task in Spotlight.
///
/// This is idempotent — calling it again with the same `task_id` replaces
/// the previous entry. Non-blocking: the actual index write happens
/// asynchronously on a background queue.
pub fn index_task(
    task_id: &str,
    title: &str,
    body_snippet: Option<&str>,
    list_name: Option<&str>,
    due_date: Option<&str>,
) {
    if !spotlight_io_enabled() {
        return;
    }
    let attrs = build_attribute_set(task_id, title, body_snippet, list_name, due_date);
    let item = build_searchable_item(task_id, &attrs);
    let items = NSArray::from_retained_slice(&[item]);
    // SAFETY: class-method getter that
    // returns the process-wide default index; no preconditions.
    let index = unsafe { CSSearchableIndex::defaultSearchableIndex() };

    let handler = log_error_block("index_task");
    // SAFETY: `items` and `handler` outlive
    // this call (CoreSpotlight retains both until the completion
    // block fires); the receiver is the live default index.
    unsafe {
        index.indexSearchableItems_completionHandler(&items, Some(&handler));
    }
}

/// Remove a single task from the Spotlight index.
pub fn remove_task(task_id: &str) {
    if !spotlight_io_enabled() {
        return;
    }
    // SAFETY: see `index_task` — class-method
    // getter for the process-wide default index.
    let index = unsafe { CSSearchableIndex::defaultSearchableIndex() };
    let ns_id = NSString::from_str(task_id);
    let identifiers = NSArray::from_retained_slice(&[ns_id]);

    let handler = log_error_block("remove_task");
    // SAFETY: `identifiers` + `handler`
    // outlive the call (CoreSpotlight retains both until the
    // completion block fires); receiver is the live default
    // index.
    unsafe {
        index.deleteSearchableItemsWithIdentifiers_completionHandler(&identifiers, Some(&handler));
    }
}

/// Remove all Lorvex tasks from the Spotlight index (by domain identifier).
pub fn remove_all_tasks() {
    if !spotlight_io_enabled() {
        return;
    }
    // SAFETY: see `index_task`.
    let index = unsafe { CSSearchableIndex::defaultSearchableIndex() };
    let domain = NSString::from_str(SPOTLIGHT_DOMAIN);
    let domains = NSArray::from_retained_slice(&[domain]);

    let handler = log_error_block("remove_all_tasks");
    // SAFETY: `domains` + `handler` outlive
    // the call; receiver is the live default index.
    unsafe {
        index
            .deleteSearchableItemsWithDomainIdentifiers_completionHandler(&domains, Some(&handler));
    }
}
