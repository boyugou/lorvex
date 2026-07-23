//! Streaming SHA-256 + ZIP tee writer used per export section.
//!
//! The `SectionDigestWriter` wraps the active `ZipWriter` entry and
//! forwards every byte to both the ZIP and a SHA-256 hasher, so the
//! manifest digest matches what the reader sees without ever holding
//! the full section bytes in memory. `write_section` is the small
//! orchestration helper that opens a ZIP entry, runs `body` against
//! the tee writer, finalizes the digest, and records it in the
//! caller's `file_digests` map.

use super::super::{ExportError, FileDigest};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::io::Write;
use zip::write::SimpleFileOptions;
use zip::ZipWriter;

/// Tee writer that forwards every byte to an inner writer (the
/// active ZIP entry) AND a SHA-256 hasher. Used per-section so the
/// manifest digest matches what the reader sees, without ever holding
/// the section's bytes in memory at once.
pub(super) struct SectionDigestWriter<'a, W: Write> {
    inner: &'a mut W,
    hasher: Sha256,
    bytes: u64,
}

impl<'a, W: Write> SectionDigestWriter<'a, W> {
    fn new(inner: &'a mut W) -> Self {
        Self {
            inner,
            hasher: Sha256::new(),
            bytes: 0,
        }
    }

    fn finish(self) -> FileDigest {
        let hash = self.hasher.finalize();
        FileDigest {
            sha256: hex::encode(hash),
            bytes: self.bytes,
        }
    }
}

impl<'a, W: Write> Write for SectionDigestWriter<'a, W> {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        let n = self.inner.write(buf)?;
        self.hasher.update(&buf[..n]);
        self.bytes += n as u64;
        Ok(n)
    }

    fn flush(&mut self) -> std::io::Result<()> {
        self.inner.flush()
    }
}

/// Run `body` with a section-scoped digest writer wrapping `zip` (the
/// caller having already invoked `zip.start_file(...)`). Returns the
/// `FileDigest` for the section so the manifest can reference it.
pub(super) fn write_section<W, F>(
    zip: &mut ZipWriter<W>,
    name: &str,
    options: SimpleFileOptions,
    file_digests: &mut BTreeMap<String, FileDigest>,
    body: F,
) -> Result<(), ExportError>
where
    W: Write + std::io::Seek,
    F: FnOnce(&mut SectionDigestWriter<'_, ZipWriter<W>>) -> Result<(), ExportError>,
{
    zip.start_file(name, options)?;
    let mut sink = SectionDigestWriter::new(zip);
    body(&mut sink)?;
    let digest = sink.finish();
    file_digests.insert(name.to_string(), digest);
    Ok(())
}
