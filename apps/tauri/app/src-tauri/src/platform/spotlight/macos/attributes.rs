//! CoreSpotlight attribute / item construction + the shared error
//! completion-block factory. Building a `CSSearchableItem` is two
//! steps (attribute set → searchable item) and every flush path
//! (`index_task`, `reindex_tasks_*`, `reindex_all_tasks`) calls them
//! exactly the same way; lifting them here keeps the FFI shape in
//! one file.

use objc2::AnyThread;
use objc2_core_spotlight::{CSSearchableItem, CSSearchableItemAttributeSet};
use objc2_foundation::{NSString, NSURL};
use objc2_uniform_type_identifiers::UTType;

use super::SPOTLIGHT_DOMAIN;

/// UTI content type for the attribute set — plain text items.
/// Migrated to the UTType-based init (#2947) once macOS-min was
/// bumped to 14: `initWithItemContentType:` (NSString) is
/// deprecated and Apple no longer ships fixes for it.
const CONTENT_TYPE: &str = "public.text";

/// Build the deep-link URL for a task: `lorvex://task/<id>`.
fn task_deep_link_url(task_id: &str) -> Option<objc2::rc::Retained<NSURL>> {
    let encoded_id: String =
        percent_encoding::utf8_percent_encode(task_id, percent_encoding::NON_ALPHANUMERIC)
            .to_string();
    let url_str = NSString::from_str(&format!("lorvex://task/{encoded_id}"));
    NSURL::URLWithString(&url_str)
}

/// Build a `CSSearchableItemAttributeSet` for a task.
pub(super) fn build_attribute_set(
    task_id: &str,
    title: &str,
    body_snippet: Option<&str>,
    list_name: Option<&str>,
    due_date: Option<&str>,
) -> objc2::rc::Retained<CSSearchableItemAttributeSet> {
    // SAFETY: all msg_send invocations in
    // this block are typed objc2 calls on freshly allocated /
    // autoreleased CoreSpotlight + Foundation objects. Every
    // `Retained<NS*>` is bound to a local before being passed by
    // reference, so the receivers outlive the call. The
    // `UTType::typeWithIdentifier` early-`expect` covers the
    // documented invariant that `public.text` is always
    // registered on supported macOS versions; the rest of the
    // body only sets typed properties on the attribute set.
    unsafe {
        // `typeWithIdentifier` returns `Option<Retained<UTType>>`;
        // the static `CONTENT_TYPE = "public.text"` is a system
        // type that is always present, so this `expect` is
        // documenting an invariant rather than guarding a
        // dynamic failure.
        let content_uti = NSString::from_str(CONTENT_TYPE);
        let content_type = UTType::typeWithIdentifier(&content_uti)
            .expect("UTType for public.text is always available on macOS");
        let attrs = CSSearchableItemAttributeSet::initWithContentType(
            CSSearchableItemAttributeSet::alloc(),
            &content_type,
        );

        // Title — the primary search target, shown prominently in results.
        let ns_title = NSString::from_str(title);
        attrs.setTitle(Some(&ns_title));

        // Display name — shown as the item name in Spotlight results.
        attrs.setDisplayName(Some(&ns_title));

        // Content description — body snippet + list name + due date.
        let mut description_parts: Vec<String> = Vec::new();
        if let Some(body) = body_snippet {
            // Truncate long bodies to keep the index lean.
            // Use `.chars().take()` instead of byte slicing to avoid
            // panicking on multi-byte UTF-8 content (Chinese, emoji, etc.).
            let truncated: String = body.chars().take(200).collect();
            description_parts.push(truncated);
        }
        if let Some(list) = list_name {
            description_parts.push(format!("List: {list}"));
        }
        if let Some(due) = due_date {
            description_parts.push(format!("Due: {due}"));
        }
        if !description_parts.is_empty() {
            let desc = NSString::from_str(&description_parts.join(" | "));
            attrs.setContentDescription(Some(&desc));
        }

        // Deep link URL — clicking the Spotlight result opens this URL,
        // which the existing `RunEvent::Opened` handler in lib.rs routes
        // to the task detail view.
        if let Some(url) = task_deep_link_url(task_id) {
            attrs.setContentURL(Some(&url));
        }

        attrs
    }
}

/// Build a `CSSearchableItem` from its parts.
pub(super) fn build_searchable_item(
    task_id: &str,
    attribute_set: &CSSearchableItemAttributeSet,
) -> objc2::rc::Retained<CSSearchableItem> {
    let unique_id = NSString::from_str(task_id);
    let domain_id = NSString::from_str(SPOTLIGHT_DOMAIN);
    // SAFETY: the Obj-C initializer takes
    // `alloc()`-produced storage plus three typed retained refs;
    // all pointers are non-null and live for the call.
    unsafe {
        CSSearchableItem::initWithUniqueIdentifier_domainIdentifier_attributeSet(
            CSSearchableItem::alloc(),
            Some(&unique_id),
            Some(&domain_id),
            attribute_set,
        )
    }
}

/// Shared error-logging block factory.
///
/// Panic safety (audit): the block runs on a CoreSpotlight private
/// dispatch queue and reaches into `crate::db::get_conn()` plus the
/// error-log writer. A panic — poisoned mutex, allocation failure
/// under memory pressure, schema drift — propagating across the
/// Objective-C → Rust boundary is undefined behavior on macOS
/// (process abort at best). Wrap the body in `catch_unwind` and
/// fall through silently if the absorber itself fails (the alternative
/// is to let UB happen).
pub(super) fn log_error_block(
    context: &'static str,
) -> block2::RcBlock<dyn Fn(*mut objc2_foundation::NSError)> {
    block2::RcBlock::new(move |error: *mut objc2_foundation::NSError| {
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            if !error.is_null() {
                // SAFETY: `error` is the
                // `NSError *` Apple passes to CoreSpotlight
                // completion blocks; we already null-checked it.
                // The pointee outlives the closure body because
                // CoreSpotlight retains the autoreleased error
                // until the block returns.
                let desc = unsafe { (*error).localizedDescription() };
                super::super::log_spotlight_error(context, &desc.to_string());
            }
        }));
    })
}
