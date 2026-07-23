import Foundation

extension LorvexDataImporter {
  private static let zipMagic: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
  private static let zipEmptyMagic: [UInt8] = [0x50, 0x4B, 0x05, 0x06]

  private struct SingleFileVersionEnvelope: Decodable {
    var formatVersion: String?
  }

  private struct ZipVersionEnvelope: Decodable {
    var schemaVersion: String
  }

  /// Decode raw file bytes into a payload, accepting either a single-file JSON
  /// export or a ZIP package export.
  public static func decode(_ data: Data) throws -> LorvexDataExportPayload {
    try decodeFull(data).payload
  }

  /// Decode raw file bytes into the versioned import representation.
  ///
  /// Rejects a source larger than ``LorvexImportLimits/maxSourceBytes`` before
  /// decoding so no path can build an in-memory object graph from an unbounded
  /// buffer. (The ZIP reader applies its own layered limits; this bound also
  /// covers a single-file JSON export, which has no container.)
  public static func decodeFull(_ data: Data) throws -> DecodedImport {
    guard !data.isEmpty else { throw ImportError.emptyFile }
    try LorvexImportLimits.assertWithinSourceBound(data)
    if startsWith(data, zipMagic) || startsWith(data, zipEmptyMagic) {
      return try decodeZip(data)
    }
    do {
      // The native single-file JSON backup is fail-fast: it MUST carry the format
      // version the exporter stamped. There are no released users or legacy files
      // to accommodate, so an unversioned JSON is not a Lorvex backup and is
      // rejected rather than mis-decoded — to bring in hand-written or AI-authored
      // JSON, have the assistant recreate it through the MCP tools instead of
      // importing it here. Decode only the version envelope first, then route to
      // that version's decoder; a future version is never decoded as the current
      // DTO merely because its fields happen to overlap.
      let envelope = try JSONDecoder().decode(SingleFileVersionEnvelope.self, from: data)
      guard let version = envelope.formatVersion else {
        throw ImportError.missingFormatVersion
      }
      guard LorvexDataExportPayload.supportedFormatVersions.contains(version) else {
        throw ImportError.incompatibleFormatVersion(
          found: version, supported: LorvexDataExportPayload.supportedFormatVersionsDescription)
      }
      let payload: LorvexDataExportPayload
      if version == LorvexDataExportPayload.firstPublicFormatVersion {
        payload = try BackupV1Archive.decodeJSON(data)
        try BackupV1SingleFileInventory.validate(data, payload: payload)
      } else {
        // Adding a version to `supportedFormatVersions` must be paired with an
        // explicit decoder branch. Fail closed if those declarations drift.
        throw ImportError.incompatibleFormatVersion(
          found: version, supported: LorvexDataExportPayload.supportedFormatVersionsDescription)
      }
      if let snapshot = payload.nativeTaskGraph,
        snapshot.schemaVersion != BackupV1Contract.nativeTaskGraphSchemaVersion
      {
        throw ImportError.incompatibleNativeTaskGraph(
          found: snapshot.schemaVersion,
          supported: BackupV1Contract.nativeTaskGraphSchemaVersion)
      }
      try BackupV1PayloadPreflight.validate(payload)
      return DecodedImport(payload: payload)
    } catch let importError as ImportError {
      throw importError
    } catch let decodingError as DecodingError {
      throw ImportError.malformedJSON(Self.describe(decodingError))
    } catch {
      throw ImportError.malformedJSON(error.localizedDescription)
    }
  }

  /// Reconstruct a payload from a ZIP export archive.
  ///
  /// The archive's `manifest.json` is an enforced compatibility contract: it must
  /// be present, declare a `schemaVersion` this build supports, and its per-file
  /// record counts must match the archive's actual inventory exactly. An archive
  /// with no manifest, a future/incompatible `schemaVersion`, or a truncated /
  /// tampered inventory is rejected rather than silently misread. The current
  /// version is a closed member set; unrecognized entries are rejected.
  private static func decodeZip(_ data: Data) throws -> DecodedImport {
    let entries: [LorvexZipArchive.Entry]
    do {
      entries = try LorvexZipArchive.read(data)
    } catch {
      throw ImportError.malformedZip(String(describing: error))
    }

    // Reject a repeated entry path before processing. The loop below is
    // last-occurrence-wins (`payload.tasks = rows`) and the
    // observed inventory is deduped, so a smuggled duplicate would silently
    // replace an earlier entry while still matching the manifest's counts —
    // defeating the exact-inventory contract. A well-formed export never repeats
    // a path.
    var seenPaths = Set<String>()
    for entry in entries {
      guard seenPaths.insert(entry.path).inserted else {
        throw ImportError.duplicateArchiveEntry(entry.path)
      }
    }

    guard
      let manifestData = entries.first(where: {
        $0.path == BackupV1ZipMember.manifestPath
      })?.data
    else {
      throw ImportError.missingManifest
    }
    let versionEnvelope = try decodeZipEntry(
      ZipVersionEnvelope.self, manifestData, path: BackupV1ZipMember.manifestPath)
    guard ExportManifest.supportedSchemaVersions.contains(versionEnvelope.schemaVersion) else {
      throw ImportError.incompatibleManifest(
        found: versionEnvelope.schemaVersion,
        supported: ExportManifest.supportedSchemaVersionsDescription)
    }
    if versionEnvelope.schemaVersion == ExportManifest.firstPublicSchemaVersion {
      let payload = try BackupV1Archive.decodeZip(
        entries: entries, manifestData: manifestData)
      try BackupV1PayloadPreflight.validate(payload)
      return DecodedImport(payload: payload)
    }
    // Adding a version to `supportedSchemaVersions` must be paired with an
    // explicit decoder branch. Fail closed if those declarations drift.
    throw ImportError.incompatibleManifest(
      found: versionEnvelope.schemaVersion,
      supported: ExportManifest.supportedSchemaVersionsDescription)
  }

  private static func decodeZipEntry<T: Decodable>(
    _ type: T.Type, _ bytes: Data, path: String
  ) throws -> T {
    do {
      return try JSONDecoder().decode(T.self, from: bytes)
    } catch let decodingError as DecodingError {
      throw ImportError.malformedZip("\(path): \(Self.describe(decodingError))")
    } catch {
      throw ImportError.malformedZip("\(path): \(error.localizedDescription)")
    }
  }

  private static func startsWith(_ data: Data, _ prefix: [UInt8]) -> Bool {
    guard data.count >= prefix.count else { return false }
    for (i, byte) in prefix.enumerated() where data[data.startIndex + i] != byte {
      return false
    }
    return true
  }

  private static func describe(_ error: DecodingError) -> String {
    switch error {
    case .dataCorrupted(let context):
      return context.debugDescription
    case .keyNotFound(let key, _):
      return "missing key \"\(key.stringValue)\""
    case .typeMismatch(_, let context), .valueNotFound(_, let context):
      return context.debugDescription
    @unknown default:
      return "unrecognized JSON shape"
    }
  }
}
