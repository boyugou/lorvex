//! Public face of the remote-apply pipeline.
//!
//! Phase-2 of #3441 collapsed the former `apply/remote/` directory into
//! flat siblings under `apply/` with a `remote_` prefix. This file is
//! now a thin facade that re-exports the public surface so existing
//! `crate::commands::sync::runtime::apply::remote::*` call sites
//! continue to compile.

#![allow(unused_imports)] // compatibility facade for legacy module path

pub(crate) use super::remote_core::apply_remote_sync_records_with_checkpoint_writer;
pub(crate) use super::remote_events::emit_data_changed_for_entity_types;
pub(crate) use super::remote_model::RemoteApplyMode;
pub(crate) use super::remote_pending::drain_pending_inbox;
#[cfg(test)]
pub(crate) use super::remote_wrappers::{
    apply_remote_sync_envelopes_internal, apply_remote_sync_envelopes_with_filesystem_bridge_cursor,
};
