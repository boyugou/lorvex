use lorvex_domain::hlc::HlcSurface;
use rusqlite::Connection;
use sha2::{Digest, Sha256};

use crate::error::{RuntimeError, RuntimeResult};
use crate::sync_checkpoints::{self, KEY_DEVICE_ID};

pub fn get_or_create_device_id(conn: &Connection) -> RuntimeResult<String> {
    if let Some(existing) = sync_checkpoints::get(conn, KEY_DEVICE_ID)? {
        return Ok(existing);
    }

    // Use `INSERT ... ON CONFLICT DO NOTHING RETURNING` (via
    // [`sync_checkpoints::set_if_absent`]) so the conditional insert
    // is a single busy-retry-eligible round-trip. Splitting it into
    // an INSERT followed by a separate readback would let
    // `SQLITE_BUSY` interrupt between them and surface
    // `DeviceIdentityUnavailable` even though the row had been
    // written.
    let generated = lorvex_domain::new_entity_id_string();
    if sync_checkpoints::set_if_absent(conn, KEY_DEVICE_ID, &generated)? {
        return Ok(generated);
    }

    // The INSERT was skipped because a concurrent writer (sibling MCP
    // or app) won the race. Read the now-present row.
    sync_checkpoints::get(conn, KEY_DEVICE_ID)?.ok_or(RuntimeError::DeviceIdentityUnavailable)
}

/// Derive a 16-character HLC device suffix from the stable
/// `device_id` **and** the emitting `surface` (app / mcp / cli).
///
/// Number of hex characters in the HLC device suffix.
///
/// previously 8 (32 bits, ~50% birthday collision at
/// 65k devices). Widened to 16 (64 bits, ~50% birthday collision at
/// 4 billion devices) so cross-device LWW tiebreaks remain
/// deterministic at any realistic install scale.
///
/// the canonical constant now lives in
/// `lorvex_domain::hlc::HLC_DEVICE_SUFFIX_HEX_LEN` so the type-system
/// invariant on `Hlc::new` / `Hlc::parse` and the runtime helper
/// share a single source of truth. Re-exported here so existing
/// `use lorvex_runtime::HLC_DEVICE_SUFFIX_HEX_LEN` call sites keep
/// compiling.
pub use lorvex_domain::hlc::HLC_DEVICE_SUFFIX_HEX_LEN;

/// the Tauri app, MCP server, and CLI all share one
/// `sync_checkpoints.device_id` but each holds an independent
/// `HlcState` counter in its own process memory. If every surface
/// derived the same suffix, two surfaces calling `generate()` in
/// the same wall-clock millisecond at counter=0 produced identical
/// HLC strings — and LWW's tie-break-to-LocalWins silently dropped
/// the second write. Mixing the surface tag into the hash makes the
/// three suffixes deterministically distinct so same-ms writes from
/// different surfaces produce different HLCs even at counter=0.
///
/// Derivation: `SHA-256(device_id_lowercased_dashless || "|" || surface_tag)`,
/// take the first [`HLC_DEVICE_SUFFIX_HEX_LEN`] hex characters.
/// SHA-256 is deterministic and the 64-bit truncation pushes the
/// birthday-collision probability to ~10⁻¹⁰ at 65k devices and ~50%
/// only past 4 billion devices (#2870). Costs a few microseconds on
/// init.
///
/// device_id is lowercased before hashing so a hand-edited
/// / restored device_id with uppercase hex produces the same suffix a
/// canonically-generated one does. ASCII 'A' sorts before 'a' in lex
/// order, so a mixed-case cluster silently gets an unintended LWW
/// tiebreak. `Hlc::new` / `Hlc::parse` also lowercase at the type
/// boundary; this keeps the two layers consistent.
pub fn device_id_to_hlc_suffix(device_id: &str, surface: HlcSurface) -> String {
    // 16 hex characters = first 8 bytes of the 32-byte digest. Emit
    // each byte as two ASCII hex chars directly rather than running
    // every byte through the formatter machinery — `write!(_,
    // "{byte:02x}")` per byte is ~3-5x slower than nibble-to-hex on
    // the same hot path.
    const HEX_TABLE: &[u8; 16] = b"0123456789abcdef";
    // Hash the normalized bytes directly: skip dashes, fold ASCII
    // upper→lower with `byte | 0x20` (only correct because device_id
    // is ASCII hex by construction). Pre-fix `device_id.replace('-',
    // "").to_ascii_lowercase()` allocated two transient `String`s
    // per call on the write-hot path;
    // streaming the bytes into the hasher avoids both. The output
    // remains identical because hashing is associative over input
    // chunks and the predicate "skip ASCII '-' / lowercase ASCII
    // letters" is byte-local.
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64];
    let mut filled = 0usize;
    for byte in device_id.bytes() {
        if byte == b'-' {
            continue;
        }
        let normalized = if byte.is_ascii_uppercase() {
            byte | 0x20
        } else {
            byte
        };
        buf[filled] = normalized;
        filled += 1;
        if filled == buf.len() {
            hasher.update(&buf[..]);
            filled = 0;
        }
    }
    if filled > 0 {
        hasher.update(&buf[..filled]);
    }
    hasher.update(b"|");
    hasher.update(surface.as_str().as_bytes());
    let digest = hasher.finalize();
    let bytes_needed = HLC_DEVICE_SUFFIX_HEX_LEN / 2;
    let mut out_bytes = Vec::with_capacity(HLC_DEVICE_SUFFIX_HEX_LEN);
    for &byte in &digest[..bytes_needed] {
        out_bytes.push(HEX_TABLE[(byte >> 4) as usize]);
        out_bytes.push(HEX_TABLE[(byte & 0x0f) as usize]);
    }
    // SAFETY: every byte pushed comes from `HEX_TABLE`, which contains
    // only ASCII characters in the range `0-9a-f`.
    String::from_utf8(out_bytes).expect("hex output is ASCII by construction")
}

#[cfg(test)]
mod tests;
