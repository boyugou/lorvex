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
/// tags, daily reviews, daily briefings, canonical task-calendar links, memory,
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
    .dailyBriefings, .taskCalendarEventLinks, .memory, .preferences,
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

    /// What the person importing the file is told, in their language: that
    /// the file is empty, is not a Lorvex backup or is damaged past
    /// recognition, holds nothing to import, comes from a newer Lorvex, or is
    /// a damaged backup, each with what to do next. The decoder's specific
    /// finding is ``diagnosticDescription``.
    public var errorDescription: String? {
      switch self {
      case .emptyFile:
        String(
          localized: "import.error.empty_file", defaultValue: "The selected file is empty.",
          table: "Localizable", bundle: CoreL10n.bundle)
      case .noImportableData:
        String(
          localized: "import.error.no_data", defaultValue: "This backup has no data to import.",
          table: "Localizable", bundle: CoreL10n.bundle)
      case .incompatibleManifest(let found, let supported),
        .incompatibleFormatVersion(let found, let supported),
        .incompatibleNativeTaskGraph(let found, let supported):
        Self.isNewerVersion(found, than: supported) ? Self.newerVersionMessage : Self.notABackupMessage
      case .malformedJSON, .malformedZip, .missingManifest, .missingPayloadManifest,
        .missingFormatVersion, .unexpectedArchiveEntry, .unexpectedJSONMember:
        Self.notABackupMessage
      case .manifestCountMismatch, .duplicateArchiveEntry, .invalidNativeTaskGraph,
        .inconsistentTaskRepresentations, .inconsistentBackupContents:
        Self.damagedMessage
      }
    }

    /// The decoder's specific finding, in English ("The archive repeats the
    /// entry \"tasks.json\" …"), for logs and tests. The interface shows
    /// ``errorDescription`` instead.
    public var diagnosticDescription: String {
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

    private static var notABackupMessage: String {
      String(
        localized: "import.error.not_a_backup",
        defaultValue: "This file isn’t a Lorvex backup, or it’s damaged. Choose a file exported from Lorvex.",
        table: "Localizable", bundle: CoreL10n.bundle)
    }

    private static var newerVersionMessage: String {
      String(
        localized: "import.error.newer_version",
        defaultValue: "This backup was made by a newer version of Lorvex. Update Lorvex on this device, then try again.",
        table: "Localizable", bundle: CoreL10n.bundle)
    }

    private static var damagedMessage: String {
      String(
        localized: "import.error.damaged",
        defaultValue:
          "This backup is damaged and can’t be imported. Export it again on the device it came from, then try again.",
        table: "Localizable", bundle: CoreL10n.bundle)
    }

    /// Whether the version a file declares is later than every version this
    /// build reads. Versions are whole numbers, and `supported` lists the
    /// readable ones separated by commas ("1", "1, 2"); a version that is not a
    /// whole number is never newer, since no Lorvex writes one.
    private static func isNewerVersion(_ found: String, than supported: String) -> Bool {
      let readable = supported.split(separator: ",").compactMap {
        Int($0.trimmingCharacters(in: .whitespaces))
      }
      guard let version = Int(found), let newest = readable.max() else { return false }
      return version > newest
    }
  }
}
