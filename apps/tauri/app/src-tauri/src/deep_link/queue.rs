use std::sync::{Mutex, OnceLock};

use super::{append_deep_link_log, DeepLinkTarget, DeepLinkTargetPayload};

const MAX_PENDING_DEEP_LINKS: usize = 8;

fn pending_links() -> &'static Mutex<Vec<DeepLinkTarget>> {
    static PENDING: OnceLock<Mutex<Vec<DeepLinkTarget>>> = OnceLock::new();
    PENDING.get_or_init(|| Mutex::new(Vec::new()))
}

fn lock_pending_links() -> std::sync::MutexGuard<'static, Vec<DeepLinkTarget>> {
    pending_links()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

pub fn enqueue_pending(target: DeepLinkTarget) {
    let mut pending = lock_pending_links();
    if pending.len() >= MAX_PENDING_DEEP_LINKS {
        pending.remove(0);
    }
    pending.push(target);
}

pub fn take_pending_payload() -> Option<DeepLinkTargetPayload> {
    let mut pending = lock_pending_links();
    if pending.is_empty() {
        return None;
    }
    Some(pending.remove(0).to_payload())
}

pub fn acknowledge_pending_payload(payload: &DeepLinkTargetPayload) -> bool {
    let target = match DeepLinkTarget::from_payload_result(payload) {
        Ok(Some(target)) => target,
        Ok(None) => return false,
        Err(error) => {
            append_deep_link_log(
                "warn",
                "pending_ack",
                "ignored malformed pending deep link payload",
                Some(format!("payload={payload:?} error={error}")),
            );
            return false;
        }
    };
    let mut pending = lock_pending_links();
    if let Some(index) = pending.iter().position(|candidate| candidate == &target) {
        pending.remove(index);
        return true;
    }
    false
}

#[cfg(test)]
pub(super) fn poison_pending_queue_for_test() {
    let _ = std::panic::catch_unwind(|| {
        let _guard = pending_links()
            .lock()
            .expect("poison pending deep-link queue");
        panic!("poison pending deep-link queue");
    });
}
