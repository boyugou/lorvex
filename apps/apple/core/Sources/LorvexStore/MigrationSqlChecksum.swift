import Foundation

/// The canonical checksum of a schema artifact's SQL text: a SHA-256 hex digest
/// over *normalized* SQL.
///
/// This is Apple's schema-identity convention — the digest recorded in
/// `schema/migrations/checksums.lock` and stamped into the
/// `schema_migrations.checksum` rows the Apple app verifies on every open, so an
/// Apple database's recorded ladder stays self-consistent across app versions.
/// Tauri's Rust/Node implementations use the same normalization algorithm but are
/// a separate, directionally-aligned realization: Apple owns its schema and never
/// compares bytes against them.
///
/// Normalization, in order:
/// 1. strip a UTF-8 BOM if present;
/// 2. replace CRLF with LF (a Windows clone with `core.autocrlf=true` must
///    hash the same as a Unix clone);
/// 3. strip SQL comments (`-- line` and `/* block */`), drop lines left
///    whitespace-only, and trim the trailing whitespace an inline comment
///    leaves behind — so comment-only edits never change the digest;
/// 4. trim leading/trailing whitespace.
///
/// Interior whitespace inside non-comment SQL is preserved so a semantic edit
/// cannot slip past a frozen checksum by reformatting alone. String literals
/// (single quotes) and quoted identifiers (double quotes) pass through
/// verbatim, including embedded newlines and embedded `--` / `/*` markers;
/// SQLite-style escaped quotes (`''` / `""`) keep the quoted run open. Block
/// comments do not nest; an unterminated block runs to end-of-input.
public enum MigrationSqlChecksum {
  /// The canonical normalized SHA-256 of `sql` as a 64-character lowercase hex
  /// string.
  public static func hexDigest(_ sql: String) -> String {
    var normalized = sql
    if normalized.hasPrefix("\u{feff}") {
      normalized.removeFirst()
    }
    normalized = normalized.replacingOccurrences(of: "\r\n", with: "\n")
    let stripped = stripSQLComments(normalized)
    let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    return Sha256Checksum.hexDigest(Data(trimmed.utf8))
  }

  private static func stripSQLComments(_ sql: String) -> String {
    let bytes = Array(sql.utf8)
    var out: [UInt8] = []
    out.reserveCapacity(bytes.count)
    var pending: [UInt8] = []
    pending.reserveCapacity(256)
    var pendingHasContent = false
    var i = 0

    while i < bytes.count {
      let byte = bytes[i]
      if byte == 0x0A {
        if pendingHasContent {
          out.append(contentsOf: pending)
          out.append(0x0A)
        }
        pending.removeAll(keepingCapacity: true)
        pendingHasContent = false
        i += 1
        continue
      }
      if byte == 0x27 || byte == 0x22 {
        let quote = byte
        pending.append(quote)
        pendingHasContent = true
        i += 1
        while i < bytes.count {
          pending.append(bytes[i])
          if bytes[i] == quote {
            i += 1
            if i < bytes.count && bytes[i] == quote {
              pending.append(bytes[i])
              i += 1
              continue
            }
            break
          }
          i += 1
        }
        continue
      }
      if byte == 0x2D, i + 1 < bytes.count, bytes[i + 1] == 0x2D {
        trimTrailingWhitespace(&pending, hasContent: &pendingHasContent)
        i += 2
        while i < bytes.count && bytes[i] != 0x0A {
          i += 1
        }
        continue
      }
      if byte == 0x2F, i + 1 < bytes.count, bytes[i + 1] == 0x2A {
        trimTrailingWhitespace(&pending, hasContent: &pendingHasContent)
        i += 2
        while i + 1 < bytes.count && !(bytes[i] == 0x2A && bytes[i + 1] == 0x2F) {
          i += 1
        }
        if i + 1 < bytes.count {
          i += 2
        } else {
          i = bytes.count
        }
        continue
      }

      let length = utf8CharacterLength(firstByte: byte)
      let end = min(i + length, bytes.count)
      pending.append(contentsOf: bytes[i..<end])
      if !bytes[i..<end].allSatisfy(isASCIIWhitespace) {
        pendingHasContent = true
      }
      i = end
    }
    if pendingHasContent {
      out.append(contentsOf: pending)
    }
    return String(decoding: out, as: UTF8.self)
  }

  private static func trimTrailingWhitespace(_ pending: inout [UInt8], hasContent: inout Bool) {
    while let last = pending.last, isASCIIWhitespace(last) {
      pending.removeLast()
    }
    if pending.isEmpty {
      hasContent = false
    }
  }

  private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
    byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0B || byte == 0x0C
  }

  private static func utf8CharacterLength(firstByte byte: UInt8) -> Int {
    switch byte {
    case 0x00...0x7F: return 1
    case 0xC0...0xDF: return 2
    case 0xE0...0xEF: return 3
    case 0xF0...0xF7: return 4
    default: return 1
    }
  }
}
