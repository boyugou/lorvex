import Foundation

/// Reads back a `LorvexDataExportPayload` JSON file and restores it through the
/// core's idempotent, ID/key-preserving primitives.
///
/// The importer is split into pure preview and explicit write phases:
/// `plan(from:)` / `decodeFull(_:)` only decode and count records; `apply(...)`
/// is the only write path and collects per-record failures instead of aborting
/// the whole import.
///
/// Supported categories restore through ID/key-preserving primitives where
/// possible: tasks, lists, habits, calendar events, calendar subscriptions,
/// tags, daily reviews, focus aggregates, canonical task-calendar links, memory,
/// and preferences.
public enum LorvexDataImporter {
  /// A decoded, version-checked import file ready for preview and apply.
  public struct DecodedImport: Sendable {
    public var payload: LorvexDataExportPayload

    public init(payload: LorvexDataExportPayload) {
      self.payload = payload
    }
  }

  /// Categories this pass can restore idempotently. Declaration order here is
  /// also the apply order.
  public static let supportedCategories: [LorvexDataExportCategory] = [
    .tasks, .lists, .tags, .habits, .calendarEvents, .dailyReviews,
    .currentFocus, .focusSchedules, .taskCalendarEventLinks, .memory, .preferences,
  ]

  public enum ImportError: LocalizedError, Equatable {
    case emptyFile
    case malformedJSON(String)
    case malformedZip(String)
    case noImportableData
    /// A ZIP export archive did not contain the required `manifest.json`.
    case missingManifest
    /// A single-file backup did not contain its inline provenance/inventory
    /// manifest. Public-v1 JSON is a backup contract, not permissive hand-written
    /// input, so it cannot safely accept an unverifiable category set.
    case missingPayloadManifest
    /// The archive's `manifest.json` declares a `schemaVersion` this build does
    /// not support. Failing closed avoids misreading a future archive shape as
    /// the current one.
    case incompatibleManifest(found: String, supported: String)
    /// The JSON/ZIP artifact's actual inventory does not match the counts its
    /// manifest declares (truncated inventory, misspelling, or tampering).
    case manifestCountMismatch(String)
    /// The archive repeats an entry path. A well-formed export never does; a
    /// duplicate would let the decoder keep only the last occurrence while the
    /// deduped inventory still matched the manifest, smuggling a substitution
    /// past the exact-inventory check. The associated value is the repeated path.
    case duplicateArchiveEntry(String)
    /// The current manifest version is a closed inventory. A path outside its
    /// supported members is neither imported nor silently retained.
    case unexpectedArchiveEntry(String)
    /// Public-v1 JSON has a closed top-level key set. A misspelled category must
    /// not silently decode as an omitted category and produce a partial restore.
    case unexpectedJSONMember(String)
    /// A single-file JSON export declares a `formatVersion` this build does not
    /// support. Failing closed avoids misreading a future file shape as the
    /// current one (the ZIP path's equivalent is `incompatibleManifest`).
    case incompatibleFormatVersion(found: String, supported: String)
    /// The independently versioned exact task-graph member uses a shape this
    /// build cannot safely materialize.
    case incompatibleNativeTaskGraph(found: String, supported: String)
    /// The retained native graph's wire version is known, but its internal
    /// lineage, relation, clock, or sync-artifact invariants are corrupt.
    case invalidNativeTaskGraph(String)
    /// Public-v1 carries both a portable task document and an exact native graph.
    /// They must be two projections of the same user data, never competing
    /// authorities chosen according to destination freshness.
    case inconsistentTaskRepresentations(String)
    /// The public-v1 artifact is structurally decodable but its own rows
    /// contradict one another (duplicate identities, dangling references into
    /// another included full category, or control state for an omitted
    /// category). Reject before preview so apply never chooses an arbitrary row
    /// or writes only the prefix preceding the contradiction.
    case inconsistentBackupContents(String)
    /// A single-file JSON file carries no `formatVersion`. The native backup is
    /// fail-fast (no released users / legacy files to tolerate), so an unversioned
    /// file is not a Lorvex backup and is rejected rather than mis-decoded.
    case missingFormatVersion

    public var errorDescription: String? {
      switch self {
      case .emptyFile:
        "The selected file is empty."
      case .malformedJSON(let detail):
        "The file is not a valid Lorvex export: \(detail)"
      case .malformedZip(let detail):
        "The file is not a valid Lorvex export archive: \(detail)"
      case .noImportableData:
        "The file contains no Lorvex data to import."
      case .missingManifest:
        "The archive is missing its manifest.json and can't be verified as a Lorvex export."
      case .missingPayloadManifest:
        "The file is missing its backup manifest and can't be verified as a Lorvex export."
      case .incompatibleManifest(let found, let supported):
        "The archive uses export format \(found), but this version supports \(supported)."
      case .manifestCountMismatch(let detail):
        "The backup contents don't match its manifest: \(detail)"
      case .duplicateArchiveEntry(let path):
        "The archive repeats the entry \"\(path)\" and can't be trusted as a Lorvex export."
      case .unexpectedArchiveEntry(let path):
        "The archive contains the unsupported entry \"\(path)\"."
      case .unexpectedJSONMember(let key):
        "The file contains the unsupported top-level entry \"\(key)\"."
      case .incompatibleFormatVersion(let found, let supported):
        "The file uses export format \(found), but this version supports \(supported)."
      case .incompatibleNativeTaskGraph(let found, let supported):
        "The archive uses native task format \(found), but this version supports \(supported)."
      case .invalidNativeTaskGraph(let detail):
        "The archive contains an invalid native task graph: \(detail)"
      case .inconsistentTaskRepresentations(let detail):
        "The backup contains contradictory task representations: \(detail)"
      case .inconsistentBackupContents(let detail):
        "The backup contains contradictory records: \(detail)"
      case .missingFormatVersion:
        "The file has no Lorvex export format version and can't be imported as a backup."
      }
    }
  }
}
