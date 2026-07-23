//! Payload-shadow subsystem tests, split by domain so a failing
//! assertion localizes (merge edge cases, owned-keys strip, schema
//! parity, redirect merge, corruption recovery, size caps, fast-path
//! `ShadowIndex`).

mod corruption;
mod merge;
mod redirect_merge;
mod schema_parity;
mod shadow_index;
mod shadow_strip;
mod size_caps;
mod support;
