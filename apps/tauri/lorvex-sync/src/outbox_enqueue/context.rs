//! Caller-supplied context bundle threaded through every outbox enqueue.
//!
//! Carries the canonical HLC version string and the authoring
//! `device_id`.

#[derive(Debug, Clone, Copy)]
pub struct OutboxWriteContext<'a> {
    pub version: &'a str,
    pub device_id: &'a str,
}
