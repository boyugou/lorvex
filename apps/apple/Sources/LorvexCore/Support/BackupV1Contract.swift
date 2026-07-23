import Foundation

/// Immutable outer resource contract for the first public backup wire.
///
/// A v1 backup produced on macOS must be restorable on iPhone/iPad, so producer
/// and consumer limits cannot vary by the compiling platform. Larger datasets
/// require a future streaming format rather than a desktop-only v1 artifact.
public enum BackupV1Contract {
  public static let formatVersion = "1"
  public static let zipSchemaVersion = "1"
  public static let nativeTaskGraphSchemaVersion = "1"

  /// Portable source/entry limit shared by every v1 producer and consumer.
  public static let maxSourceBytes = 64 * 1024 * 1024
  public static let maxEntryUncompressedBytes = maxSourceBytes
  public static let maxTotalUncompressedBytes = 128 * 1024 * 1024

  static func assertPortableOutputSize(_ size: Int) throws {
    if size > maxSourceBytes {
      throw LorvexDataExportError.outputTooLarge(size: size, limit: maxSourceBytes)
    }
  }
}
