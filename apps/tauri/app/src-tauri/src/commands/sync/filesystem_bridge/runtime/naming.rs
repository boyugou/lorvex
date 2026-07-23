use sha2::{Digest, Sha256};

pub(super) fn filesystem_bridge_file_stem(device_id: &str, outbox_id: i64) -> String {
    let device_part = filesystem_bridge_device_hash(device_id);
    let envelope_part = filesystem_bridge_envelope_hash(device_id, outbox_id);
    format!("{device_part}_{envelope_part}")
}

/// Local-device prefix used by `gc_stale_sync_files` to distinguish
/// "ours" (short retention) from "foreign" (long retention) without
/// reading any file content.
pub(super) fn filesystem_bridge_local_file_prefix(device_id: &str) -> String {
    format!("{}_", filesystem_bridge_device_hash(device_id))
}

fn filesystem_bridge_device_hash(device_id: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"lorvex.fsbridge.device.v1\0");
    hasher.update(device_id.as_bytes());
    let digest = hasher.finalize();
    // 16 hex chars = 64 bits of entropy. Deterministic per device.
    hex_lower(&digest[..8])
}

fn filesystem_bridge_envelope_hash(device_id: &str, outbox_id: i64) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"lorvex.fsbridge.envelope.v1\0");
    hasher.update(device_id.as_bytes());
    hasher.update(b":");
    hasher.update(outbox_id.to_le_bytes());
    let digest = hasher.finalize();
    hex_lower(&digest[..8])
}

fn hex_lower(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        out.push(HEX[(b >> 4) as usize] as char);
        out.push(HEX[(b & 0x0f) as usize] as char);
    }
    out
}
