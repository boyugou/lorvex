import Compression
import Foundation

extension LorvexZipArchive {
  /// Upper bound on a single entry's declared uncompressed size, enforced before
  /// the reader allocates the inflate destination buffer. The uncompressed size
  /// is read from the archive's central-directory header — attacker-controlled in
  /// a crafted archive — so without this cap an entry could declare a
  /// multi-gigabyte size and force an unbounded heap allocation before the CRC
  /// (which runs only after inflation) could reject it. Sized far above any
  /// legitimate Lorvex export entry.
  ///
  /// Fixed by the public-v1 wire contract so an archive accepted on one Apple
  /// platform is accepted on every other supported Apple platform.
  public static let maxEntryUncompressedBytes = BackupV1Contract.maxEntryUncompressedBytes

  /// Upper bound on the whole archive's on-disk byte length, checked before the
  /// reader copies the source into `[UInt8]`. A Lorvex export archive is
  /// compressed text; a source this large is not a plausible Lorvex archive.
  /// Fixed at the iPhone-safe v1 maximum on every platform.
  public static let maxArchiveBytes = BackupV1Contract.maxSourceBytes

  /// Upper bound on the number of central-directory entries the reader will walk.
  /// A Lorvex archive emits well under two dozen entries (one JSON file per
  /// category plus a manifest); classic ZIP permits up to 65,535, so this
  /// rejects an archive padded with tens of thousands of tiny entries to
  /// exhaust memory an entry at a time.
  public static let maxEntryCount = 4096

  /// Upper bound on the SUM of every entry's declared uncompressed size across
  /// the whole archive, enforced from the central directory BEFORE any entry is
  /// inflated. The per-entry cap alone cannot stop many near-cap entries from
  /// aggregating into a multi-gigabyte materialization; this bounds the total the
  /// reader can be asked to hold at once. Fixed by the portable v1 wire contract.
  public static let maxTotalUncompressedBytes = BackupV1Contract.maxTotalUncompressedBytes

  /// Upper bound on a single entry's declared decompression ratio
  /// (uncompressed ÷ compressed), a classic zip-bomb guard. Store entries are 1:1;
  /// real deflate-compressed Lorvex JSON stays far under this, so an entry that
  /// claims to inflate more than this many times its stored bytes is rejected
  /// before inflation. The absolute per-entry and total caps remain the primary
  /// memory bound; this is a defense-in-depth layer against a small compressed
  /// payload declaring a huge output.
  public static let maxCompressionRatio = 1000

  /// Errors raised while reading a `.zip` archive back into entries.
  public enum ReadError: Error, CustomStringConvertible, Equatable {
    /// No end-of-central-directory record was found (not a zip, or truncated).
    case missingEndOfCentralDirectory
    /// A central-directory or local-file header signature did not match.
    case malformedHeader(String)
    /// An entry uses a compression method this reader does not support. Only
    /// store (0) and deflate (8) — the methods the `zip` ecosystem actually
    /// emits — are accepted.
    case unsupportedCompression(entry: String, method: UInt16)
    /// A deflate entry could not be inflated to its recorded uncompressed size.
    case inflateFailed(entry: String)
    /// An entry's bytes did not match the CRC-32 recorded in its header.
    case crcMismatch(entry: String, expected: UInt32, actual: UInt32)
    /// A header pointed past the end of the data (truncated/corrupt archive).
    case truncated
    /// An entry's central-directory header declares an uncompressed size beyond
    /// ``maxEntryUncompressedBytes``. Rejected before the inflate buffer is
    /// allocated so a crafted archive cannot force an unbounded allocation.
    case entryTooLarge(entry: String, declaredSize: Int, limit: Int)
    /// The archive's on-disk byte length exceeds ``maxArchiveBytes``.
    case archiveTooLarge(size: Int, limit: Int)
    /// The archive declares more entries than ``maxEntryCount``.
    case tooManyEntries(count: Int, limit: Int)
    /// The sum of all entries' declared uncompressed sizes exceeds
    /// ``maxTotalUncompressedBytes``.
    case totalUncompressedTooLarge(total: Int, limit: Int)
    /// An entry declares a decompression ratio beyond ``maxCompressionRatio``.
    case compressionRatioExceeded(
      entry: String, compressedSize: Int, uncompressedSize: Int, limit: Int)

    public var description: String {
      switch self {
      case .missingEndOfCentralDirectory:
        return "zip end-of-central-directory record not found"
      case .malformedHeader(let detail): return "malformed zip header: \(detail)"
      case .unsupportedCompression(let entry, let method):
        return "zip entry '\(entry)' uses unsupported compression method \(method)"
      case .inflateFailed(let entry):
        return "zip entry '\(entry)' could not be inflated"
      case .crcMismatch(let entry, let expected, let actual):
        return "zip entry '\(entry)' CRC mismatch (expected \(expected), actual \(actual))"
      case .truncated: return "zip archive is truncated"
      case .entryTooLarge(let entry, let declaredSize, let limit):
        return
          "zip entry '\(entry)' declares uncompressed size \(declaredSize) bytes, "
          + "exceeding the \(limit)-byte per-entry limit"
      case .archiveTooLarge(let size, let limit):
        return "zip archive is \(size) bytes, exceeding the \(limit)-byte archive limit"
      case .tooManyEntries(let count, let limit):
        return "zip archive declares \(count) entries, exceeding the \(limit)-entry limit"
      case .totalUncompressedTooLarge(let total, let limit):
        return
          "zip archive declares \(total) total uncompressed bytes, "
          + "exceeding the \(limit)-byte aggregate limit"
      case .compressionRatioExceeded(let entry, let compressedSize, let uncompressedSize, let limit):
        return
          "zip entry '\(entry)' declares a \(uncompressedSize)-byte inflation of "
          + "\(compressedSize) stored bytes, exceeding the \(limit):1 decompression-ratio limit"
      }
    }
  }

  /// One entry's central-directory metadata. Collected for the whole archive in a
  /// first pass so the aggregate resource limits can reject a hostile archive from
  /// its declared sizes alone — before any local file header is followed or any
  /// payload is materialized.
  private struct EntryPlan {
    let name: String
    let nameBytes: [UInt8]
    let flags: UInt16
    let method: UInt16
    let crc: UInt32
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int
  }

  /// Reads a `.zip` archive back into its entries, in central-directory order.
  ///
  /// Locates the end-of-central-directory record, walks the central directory to
  /// collect every entry's metadata, then enforces the layered resource limits
  /// (``maxArchiveBytes``, ``maxEntryCount``, ``maxEntryUncompressedBytes``,
  /// ``maxTotalUncompressedBytes``, ``maxCompressionRatio``) from the declared
  /// sizes BEFORE inflating anything — so a compression-bomb or entry-flood
  /// archive is rejected without ever materializing its payloads. Only after the
  /// whole plan passes does it follow each entry's local-header offset to its
  /// bytes: store (method 0) entries are taken verbatim; deflate (method 8)
  /// entries are inflated via the `Compression` framework (`COMPRESSION_ZLIB` is
  /// raw DEFLATE, matching ZIP). Every entry's CRC-32 is recomputed over the
  /// uncompressed bytes and checked against the header so a corrupt or tampered
  /// archive is rejected rather than silently restored. Round-trips
  /// ``archive(entries:)`` output exactly.
  public static func read(_ data: Data) throws -> [Entry] {
    guard data.count <= Self.maxArchiveBytes else {
      throw ReadError.archiveTooLarge(size: data.count, limit: Self.maxArchiveBytes)
    }
    let bytes = [UInt8](data)
    guard let eocd = findEndOfCentralDirectory(bytes) else {
      throw ReadError.missingEndOfCentralDirectory
    }
    let diskNumber = readUInt16LE(bytes, eocd + 4)
    let centralDirectoryDisk = readUInt16LE(bytes, eocd + 6)
    guard diskNumber == 0, centralDirectoryDisk == 0 else {
      throw ReadError.malformedHeader("multi-disk archives are not supported")
    }
    let entriesOnDisk = Int(readUInt16LE(bytes, eocd + 8))
    let entryCount = Int(readUInt16LE(bytes, eocd + 10))
    guard entriesOnDisk == entryCount else {
      throw ReadError.malformedHeader(
        "central directory record counts disagree (\(entriesOnDisk) on disk, \(entryCount) total)")
    }
    guard entryCount <= Self.maxEntryCount else {
      throw ReadError.tooManyEntries(count: entryCount, limit: Self.maxEntryCount)
    }
    let centralDirectorySize = Int(readUInt32LE(bytes, eocd + 12))
    let centralDirectoryOffset = Int(readUInt32LE(bytes, eocd + 16))
    guard centralDirectoryOffset <= eocd,
      centralDirectorySize == eocd - centralDirectoryOffset
    else {
      throw ReadError.malformedHeader(
        "central directory offset and size do not end at the end-of-central-directory record")
    }
    let centralDirectoryEnd = eocd
    var offset = centralDirectoryOffset

    // First pass: collect and bound every entry's declared metadata BEFORE
    // inflating any of it. A crafted archive is thus rejected on its declared
    // sizes, never by inflating its way to memory exhaustion.
    var plans: [EntryPlan] = []
    plans.reserveCapacity(entryCount)
    var totalUncompressed = 0
    for _ in 0..<entryCount {
      guard offset + 46 <= centralDirectoryEnd else { throw ReadError.truncated }
      guard readUInt32LE(bytes, offset) == 0x0201_4b50 else {
        throw ReadError.malformedHeader("central directory signature at \(offset)")
      }
      let flags = readUInt16LE(bytes, offset + 8)
      let method = readUInt16LE(bytes, offset + 10)
      let crc = readUInt32LE(bytes, offset + 16)
      let compressedSize = Int(readUInt32LE(bytes, offset + 20))
      let uncompressedSize = Int(readUInt32LE(bytes, offset + 24))
      let nameLength = Int(readUInt16LE(bytes, offset + 28))
      let extraLength = Int(readUInt16LE(bytes, offset + 30))
      let commentLength = Int(readUInt16LE(bytes, offset + 32))
      let localHeaderOffset = Int(readUInt32LE(bytes, offset + 42))

      let nameStart = offset + 46
      let nextOffset = nameStart + nameLength + extraLength + commentLength
      guard nextOffset <= centralDirectoryEnd else { throw ReadError.truncated }
      let nameBytes = Array(bytes[nameStart..<(nameStart + nameLength)])
      guard let name = String(bytes: nameBytes, encoding: .utf8) else {
        throw ReadError.malformedHeader("central-directory entry name is not valid UTF-8")
      }

      guard flags & 0x0001 == 0 else {
        throw ReadError.malformedHeader("encrypted entries are not supported")
      }

      guard method == 0 || method == 8 else {
        throw ReadError.unsupportedCompression(entry: name, method: method)
      }

      // Bound the declared uncompressed size BEFORE `inflate` allocates a buffer
      // of that size. The CRC guard only runs after inflation, so it cannot stop
      // a crafted entry from demanding a huge allocation on its own.
      guard uncompressedSize <= Self.maxEntryUncompressedBytes else {
        throw ReadError.entryTooLarge(
          entry: name, declaredSize: uncompressedSize, limit: Self.maxEntryUncompressedBytes)
      }
      // Decompression-ratio guard: a small stored payload declaring a huge
      // inflation is the classic zip bomb. An empty entry (both sizes 0) never
      // trips this; a store entry is 1:1.
      if uncompressedSize > compressedSize * Self.maxCompressionRatio {
        throw ReadError.compressionRatioExceeded(
          entry: name, compressedSize: compressedSize, uncompressedSize: uncompressedSize,
          limit: Self.maxCompressionRatio)
      }
      guard method != 0 || compressedSize == uncompressedSize else {
        throw ReadError.malformedHeader(
          "stored entry '\(name)' declares different compressed and uncompressed sizes")
      }
      totalUncompressed += uncompressedSize
      guard totalUncompressed <= Self.maxTotalUncompressedBytes else {
        throw ReadError.totalUncompressedTooLarge(
          total: totalUncompressed, limit: Self.maxTotalUncompressedBytes)
      }

      plans.append(
        EntryPlan(
          name: name, nameBytes: nameBytes, flags: flags, method: method, crc: crc,
          compressedSize: compressedSize,
          uncompressedSize: uncompressedSize, localHeaderOffset: localHeaderOffset))
      offset = nextOffset
    }
    guard offset == centralDirectoryEnd else {
      throw ReadError.malformedHeader(
        "central directory record count does not consume its declared size")
    }

    // Second pass: the plan is within every resource bound; follow each entry's
    // local file header to its bytes and verify its CRC. No payload is touched
    // until the whole archive has passed the aggregate limits above.
    var entries: [Entry] = []
    entries.reserveCapacity(plans.count)
    for plan in plans {
      guard plan.localHeaderOffset < centralDirectoryOffset,
        plan.localHeaderOffset + 30 <= centralDirectoryOffset
      else { throw ReadError.truncated }
      guard readUInt32LE(bytes, plan.localHeaderOffset) == 0x0403_4b50 else {
        throw ReadError.malformedHeader(
          "local file header signature at \(plan.localHeaderOffset)")
      }
      let localFlags = readUInt16LE(bytes, plan.localHeaderOffset + 6)
      let localMethod = readUInt16LE(bytes, plan.localHeaderOffset + 8)
      guard localFlags == plan.flags else {
        throw ReadError.malformedHeader(
          "local and central flags disagree for entry '\(plan.name)'")
      }
      guard localMethod == plan.method else {
        throw ReadError.malformedHeader(
          "local and central compression methods disagree for entry '\(plan.name)'")
      }
      let localNameLength = Int(readUInt16LE(bytes, plan.localHeaderOffset + 26))
      let localExtraLength = Int(readUInt16LE(bytes, plan.localHeaderOffset + 28))
      let localNameStart = plan.localHeaderOffset + 30
      let localNameEnd = localNameStart + localNameLength
      guard localNameEnd <= centralDirectoryOffset else { throw ReadError.truncated }
      guard Array(bytes[localNameStart..<localNameEnd]) == plan.nameBytes else {
        throw ReadError.malformedHeader(
          "local and central names disagree for entry '\(plan.name)'")
      }
      let payloadStart = plan.localHeaderOffset + 30 + localNameLength + localExtraLength
      let payloadEnd = payloadStart + plan.compressedSize
      guard payloadStart <= centralDirectoryOffset, payloadEnd <= centralDirectoryOffset else {
        throw ReadError.truncated
      }

      let usesDataDescriptor = plan.flags & 0x0008 != 0
      let localCrc = readUInt32LE(bytes, plan.localHeaderOffset + 14)
      let localCompressedSize = readUInt32LE(bytes, plan.localHeaderOffset + 18)
      let localUncompressedSize = readUInt32LE(bytes, plan.localHeaderOffset + 22)
      if usesDataDescriptor {
        // With bit 3 set, local metadata may be zero and the authoritative
        // values follow the payload. Validate that descriptor too; otherwise a
        // crafted central entry can point through another local entry or into
        // the central directory while still passing the payload CRC.
        // The optional descriptor signature has the same byte shape as a CRC.
        // If an unsigned descriptor's real CRC is 0x08074b50, treating those
        // first four bytes as a signature shifts the fields and rejects a valid
        // archive. Validate both legal layouts against the authoritative
        // central-directory triple instead of guessing from the first word.
        let unsignedDescriptorMatches =
          payloadEnd + 12 <= centralDirectoryOffset
          && readUInt32LE(bytes, payloadEnd) == plan.crc
          && readUInt32LE(bytes, payloadEnd + 4) == UInt32(plan.compressedSize)
          && readUInt32LE(bytes, payloadEnd + 8) == UInt32(plan.uncompressedSize)
        let signedDescriptorMatches =
          payloadEnd + 16 <= centralDirectoryOffset
          && readUInt32LE(bytes, payloadEnd) == 0x0807_4b50
          && readUInt32LE(bytes, payloadEnd + 4) == plan.crc
          && readUInt32LE(bytes, payloadEnd + 8) == UInt32(plan.compressedSize)
          && readUInt32LE(bytes, payloadEnd + 12) == UInt32(plan.uncompressedSize)
        guard unsignedDescriptorMatches || signedDescriptorMatches else {
          throw ReadError.malformedHeader(
            "data descriptor disagrees with central metadata for entry '\(plan.name)'")
        }
        guard localCrc == 0 || localCrc == plan.crc,
          localCompressedSize == 0 || localCompressedSize == UInt32(plan.compressedSize),
          localUncompressedSize == 0 || localUncompressedSize == UInt32(plan.uncompressedSize)
        else {
          throw ReadError.malformedHeader(
            "local and central metadata disagree for entry '\(plan.name)'")
        }
      } else {
        guard localCrc == plan.crc,
          localCompressedSize == UInt32(plan.compressedSize),
          localUncompressedSize == UInt32(plan.uncompressedSize)
        else {
          throw ReadError.malformedHeader(
            "local and central metadata disagree for entry '\(plan.name)'")
        }
      }

      let rawBytes = Data(bytes[payloadStart..<payloadEnd])
      let payload: Data
      if plan.method == 8 {
        payload = try inflate(rawBytes, uncompressedSize: plan.uncompressedSize, entry: plan.name)
      } else {
        payload = rawBytes
      }
      // The header CRC-32 covers the UNCOMPRESSED bytes for both methods.
      let actualCrc = crc32(payload)
      guard actualCrc == plan.crc else {
        throw ReadError.crcMismatch(entry: plan.name, expected: plan.crc, actual: actualCrc)
      }
      entries.append(Entry(path: plan.name, data: payload))
    }
    return entries
  }

  /// Inflate a raw-DEFLATE entry to its recorded uncompressed size using the
  /// `Compression` framework. ZIP method 8 is raw DEFLATE (RFC 1951) with no
  /// zlib wrapper, which is exactly what `COMPRESSION_ZLIB` decodes.
  private static func inflate(_ data: Data, uncompressedSize: Int, entry: String) throws -> Data {
    if uncompressedSize == 0 { return Data() }
    var dst = Data(count: uncompressedSize)
    let written = dst.withUnsafeMutableBytes { (dstRaw: UnsafeMutableRawBufferPointer) -> Int in
      data.withUnsafeBytes { (srcRaw: UnsafeRawBufferPointer) -> Int in
        guard let dstBase = dstRaw.bindMemory(to: UInt8.self).baseAddress,
          let srcBase = srcRaw.bindMemory(to: UInt8.self).baseAddress
        else { return 0 }
        return compression_decode_buffer(
          dstBase, uncompressedSize, srcBase, data.count, nil, COMPRESSION_ZLIB)
      }
    }
    guard written == uncompressedSize else {
      throw ReadError.inflateFailed(entry: entry)
    }
    return dst
  }

  /// Scan backwards for the end-of-central-directory signature (`0x06054b50`).
  /// The EOCD is within the last 22 + 65535 bytes (max comment length); a clean
  /// archive (no comment) places it at the final 22 bytes. Returns the byte
  /// offset of the signature, or nil if absent.
  private static func findEndOfCentralDirectory(_ bytes: [UInt8]) -> Int? {
    guard bytes.count >= 22 else { return nil }
    let lowerBound = max(0, bytes.count - 22 - 0xFFFF)
    var i = bytes.count - 22
    while i >= lowerBound {
      if readUInt32LE(bytes, i) == 0x0605_4b50,
        i + 22 + Int(readUInt16LE(bytes, i + 20)) == bytes.count
      {
        return i
      }
      i -= 1
    }
    return nil
  }
}
