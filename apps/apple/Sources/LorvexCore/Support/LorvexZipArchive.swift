import Foundation

/// A minimal, dependency-free ZIP archive writer using the store method (no
/// compression). Foundation-only and `Sendable`-clean so it can run on any
/// Apple platform and across actor boundaries.
///
/// Each entry is written with a local file header (signature `0x04034b50`,
/// version-needed 20, no flags, method 0 = store) followed by the raw bytes,
/// then a central directory (per-entry signature `0x02014b50`) and an
/// end-of-central-directory record (`0x06054b50`). All multi-byte fields are
/// little-endian.
///
/// Timestamps are fixed to 1980-01-01 00:00:00 (the canonical DOS zero-date
/// `0x0021`/`0x0000`) so output is deterministic and the writer never reads the
/// wall clock. Compressed size equals uncompressed size for every entry because
/// no compression is applied.
public enum LorvexZipArchive {
  /// A single file within the archive. `path` is the in-archive name (may
  /// contain forward slashes for directories); `data` is the stored payload.
  public struct Entry: Sendable {
    public let path: String
    public let data: Data

    public init(path: String, data: Data) {
      self.path = path
      self.data = data
    }
  }

  /// A requested archive cannot be represented by the classic-ZIP subset this
  /// writer emits, or would exceed the same resource envelope the reader
  /// accepts. The writer fails before emitting any bytes rather than truncating
  /// 16/32-bit header fields and producing a backup Lorvex cannot restore.
  public enum WriteError: Error, CustomStringConvertible, Equatable {
    case tooManyEntries(count: Int, limit: Int)
    case duplicateEntryPath(String)
    case pathTooLong(path: String, byteCount: Int, limit: Int)
    case entryTooLarge(path: String, size: Int, limit: Int)
    case totalUncompressedTooLarge(total: Int, limit: Int)
    case archiveTooLarge(size: Int, limit: Int)

    public var description: String {
      switch self {
      case .tooManyEntries(let count, let limit):
        "zip export contains \(count) entries, exceeding the \(limit)-entry limit"
      case .duplicateEntryPath(let path):
        "zip export repeats the entry path '\(path)'"
      case .pathTooLong(let path, let byteCount, let limit):
        "zip entry '\(path)' has a \(byteCount)-byte path, exceeding the \(limit)-byte limit"
      case .entryTooLarge(let path, let size, let limit):
        "zip entry '\(path)' is \(size) bytes, exceeding the \(limit)-byte entry limit"
      case .totalUncompressedTooLarge(let total, let limit):
        "zip export contains \(total) data bytes, exceeding the \(limit)-byte total limit"
      case .archiveTooLarge(let size, let limit):
        "zip export would be \(size) bytes, exceeding the \(limit)-byte archive limit"
      }
    }
  }

  /// Builds a complete `.zip` archive from `entries` in the order given.
  public static func archive(entries: [Entry]) throws -> Data {
    guard entries.count <= min(Int(UInt16.max), maxEntryCount) else {
      throw WriteError.tooManyEntries(
        count: entries.count, limit: min(Int(UInt16.max), maxEntryCount))
    }

    var seenPaths = Set<String>()
    var totalUncompressed = 0
    var archiveSize = 22  // End-of-central-directory record.
    for entry in entries {
      guard seenPaths.insert(entry.path).inserted else {
        throw WriteError.duplicateEntryPath(entry.path)
      }
      let nameByteCount = entry.path.utf8.count
      guard nameByteCount <= Int(UInt16.max) else {
        throw WriteError.pathTooLong(
          path: entry.path, byteCount: nameByteCount, limit: Int(UInt16.max))
      }
      guard entry.data.count <= min(Int(UInt32.max), maxEntryUncompressedBytes) else {
        throw WriteError.entryTooLarge(
          path: entry.path, size: entry.data.count,
          limit: min(Int(UInt32.max), maxEntryUncompressedBytes))
      }
      totalUncompressed += entry.data.count
      guard totalUncompressed <= maxTotalUncompressedBytes else {
        throw WriteError.totalUncompressedTooLarge(
          total: totalUncompressed, limit: maxTotalUncompressedBytes)
      }
      archiveSize += 30 + nameByteCount + entry.data.count
      archiveSize += 46 + nameByteCount
      guard archiveSize <= maxArchiveBytes else {
        throw WriteError.archiveTooLarge(size: archiveSize, limit: maxArchiveBytes)
      }
    }

    var output = Data()
    var central = Data()
    let entryCount = UInt16(entries.count)

    for entry in entries {
      let nameBytes = Data(entry.path.utf8)
      let crc = crc32(entry.data)
      let size = UInt32(entry.data.count)
      let localHeaderOffset = UInt32(output.count)

      // Local file header (30 bytes fixed + filename).
      output.appendUInt32LE(0x0403_4b50)
      output.appendUInt16LE(20)  // version needed to extract
      output.appendUInt16LE(0)  // general purpose bit flag
      output.appendUInt16LE(0)  // compression method: 0 = store
      output.appendUInt16LE(dosTime)
      output.appendUInt16LE(dosDate)
      output.appendUInt32LE(crc)
      output.appendUInt32LE(size)  // compressed size
      output.appendUInt32LE(size)  // uncompressed size
      output.appendUInt16LE(UInt16(nameBytes.count))
      output.appendUInt16LE(0)  // extra field length
      output.append(nameBytes)
      output.append(entry.data)

      // Central directory file header (46 bytes fixed + filename).
      central.appendUInt32LE(0x0201_4b50)
      central.appendUInt16LE(20)  // version made by
      central.appendUInt16LE(20)  // version needed to extract
      central.appendUInt16LE(0)  // general purpose bit flag
      central.appendUInt16LE(0)  // compression method: 0 = store
      central.appendUInt16LE(dosTime)
      central.appendUInt16LE(dosDate)
      central.appendUInt32LE(crc)
      central.appendUInt32LE(size)  // compressed size
      central.appendUInt32LE(size)  // uncompressed size
      central.appendUInt16LE(UInt16(nameBytes.count))
      central.appendUInt16LE(0)  // extra field length
      central.appendUInt16LE(0)  // file comment length
      central.appendUInt16LE(0)  // disk number start
      central.appendUInt16LE(0)  // internal file attributes
      central.appendUInt32LE(0)  // external file attributes
      central.appendUInt32LE(localHeaderOffset)
      central.append(nameBytes)
    }

    let centralDirectoryOffset = UInt32(output.count)
    let centralDirectorySize = UInt32(central.count)
    output.append(central)

    // End of central directory record (22 bytes, no comment).
    output.appendUInt32LE(0x0605_4b50)
    output.appendUInt16LE(0)  // number of this disk
    output.appendUInt16LE(0)  // disk where central directory starts
    output.appendUInt16LE(entryCount)  // central directory records on this disk
    output.appendUInt16LE(entryCount)  // total central directory records
    output.appendUInt32LE(centralDirectorySize)
    output.appendUInt32LE(centralDirectoryOffset)
    output.appendUInt16LE(0)  // comment length

    return output
  }

  /// DOS time field for 00:00:00 (hours<<11 | minutes<<5 | seconds/2).
  private static let dosTime: UInt16 = 0x0000

  /// DOS date field for 1980-01-01 ((year-1980)<<9 | month<<5 | day).
  private static let dosDate: UInt16 = 0x0021
}

extension Data {
  fileprivate mutating func appendUInt16LE(_ value: UInt16) {
    append(UInt8(truncatingIfNeeded: value))
    append(UInt8(truncatingIfNeeded: value >> 8))
  }

  fileprivate mutating func appendUInt32LE(_ value: UInt32) {
    append(UInt8(truncatingIfNeeded: value))
    append(UInt8(truncatingIfNeeded: value >> 8))
    append(UInt8(truncatingIfNeeded: value >> 16))
    append(UInt8(truncatingIfNeeded: value >> 24))
  }
}
