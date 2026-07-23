//! Export archive writers.
//!
//! Holds the inner orchestrators (`export_to_zip_inner`,
//! `export_to_zip_scoped_inner`) plus the scoped archive writer
//! (`write_export_archive`). The public entry points live in
//! `export::entrypoints` and wrap these in transaction/panic-safety
//! scaffolding.
//!
//! Each JSONL section streams directly into the ZIP through a
//! `SectionDigestWriter` that tees writes into both the ZIP entry and
//! a SHA-256 hasher. No section is buffered in memory — a
//! materialize-then-push approach (each JSONL section as a `Vec<u8>`
//! before pushing it into the ZIP) produces unbounded memory bloat
//! on multi-million-row exports (#3053 H1+M18). The hasher state is
//! finalized at section boundary so `manifest.json` records a
//! `FileDigest` (sha256 + uncompressed bytes) that the import side's
//! integrity check verifies byte-for-byte.

mod archive_writer;
mod digest;
mod full_export;
mod scoped_export;

pub(super) use full_export::export_to_zip_inner;
pub(super) use scoped_export::export_to_zip_scoped_inner;
