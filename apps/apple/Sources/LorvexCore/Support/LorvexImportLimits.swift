import Foundation

/// Named, tested resource limits for reading an import/restore file (a native
/// Lorvex JSON/ZIP export) into memory.
///
/// The archive reader (`LorvexZipArchive`) owns the per-entry, entry-count,
/// aggregate-uncompressed, and decompression-ratio bounds. This type owns the
/// OUTERMOST bound — the source file's on-disk byte length — and the helper that
/// enforces it BEFORE the file is materialized, so a hostile or absurdly large
/// file never becomes a multi-hundred-megabyte `Data` on an iPhone or Mac. For a
/// raw single-file JSON export (no ZIP container) this cap is also the effective
/// bound on total JSON text length, since the decoder builds a full in-memory
/// object graph from those bytes.
public enum LorvexImportLimits {
  /// Upper bound on the source file's byte length, checked from filesystem
  /// metadata before the file is read into memory. Tracks the immutable,
  /// platform-independent v1 contract: a backup emitted on macOS must remain
  /// acceptable on iPhone/iPad. A ZIP source shares that bound directly, and a
  /// raw JSON export is bounded here too because it decodes into a full in-memory
  /// object graph of comparable size.
  public static let maxSourceBytes = BackupV1Contract.maxSourceBytes

  /// An import source exceeds ``maxSourceBytes``.
  public struct SourceTooLargeError: LocalizedError, Equatable {
    public let size: Int
    public let limit: Int

    public init(size: Int, limit: Int) {
      self.size = size
      self.limit = limit
    }

    public var errorDescription: String? {
      "The selected file is \(size) bytes, larger than the \(limit)-byte import limit."
    }
  }

  /// Read an import file at `url`, rejecting it BEFORE materialization when its
  /// on-disk size exceeds ``maxSourceBytes``. The size is read from filesystem
  /// metadata (no bytes loaded) so an oversized file never allocates. Callers
  /// already hold any required security-scoped access for `url`.
  public static func readBoundedFile(at url: URL) throws -> Data {
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    if let size = values.fileSize, size > maxSourceBytes {
      throw SourceTooLargeError(size: size, limit: maxSourceBytes)
    }
    let data = try Data(contentsOf: url)
    // Defense in depth: the metadata size read can race a writer or resolve a
    // symlink to a smaller stat; bound the materialized bytes too.
    try assertWithinSourceBound(data)
    return data
  }

  /// Reject already-materialized `data` whose length exceeds ``maxSourceBytes``.
  /// Guards decoder entry points that receive bytes obtained without
  /// ``readBoundedFile(at:)`` so no path can decode an unbounded buffer.
  public static func assertWithinSourceBound(_ data: Data) throws {
    if data.count > maxSourceBytes {
      throw SourceTooLargeError(size: data.count, limit: maxSourceBytes)
    }
  }
}
