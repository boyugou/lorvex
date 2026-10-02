import Foundation
import LorvexCore
import Testing

/// A rejected import file is described by one of a few plain outcomes in the
/// person's language, with what to do next, while the decoder's specific
/// finding stays available for the log.
@Suite("Import error messages")
struct LorvexImportErrorMessageTests {
  typealias ImportError = LorvexDataImporter.ImportError

  private static let notABackup =
    "This file isn’t a Lorvex backup, or it’s damaged. Choose a file exported from Lorvex."
  private static let damaged =
    "This backup is damaged and can’t be imported. Export it again on the device it came from, then try again."
  private static let newer =
    "This backup was made by a newer version of Lorvex. Update Lorvex on this device, then try again."

  @Test("Every decoder finding reads as one plain outcome")
  func outcomes() {
    #expect(ImportError.emptyFile.errorDescription == "The selected file is empty.")
    #expect(ImportError.noImportableData.errorDescription == "This backup has no data to import.")
    let unreadable: [ImportError] = [
      .malformedJSON("x"), .malformedZip("x"), .missingManifest, .missingPayloadManifest,
      .missingFormatVersion, .unexpectedArchiveEntry("extra.json"), .unexpectedJSONMember("extra"),
    ]
    for error in unreadable { #expect(error.errorDescription == Self.notABackup) }
    let inconsistent: [ImportError] = [
      .manifestCountMismatch("x"), .duplicateArchiveEntry("tasks.json"), .invalidNativeTaskGraph("x"),
      .inconsistentTaskRepresentations("x"), .inconsistentBackupContents("x"),
    ]
    for error in inconsistent { #expect(error.errorDescription == Self.damaged) }
  }

  @Test("Only a version later than every readable one comes from a newer Lorvex")
  func versions() {
    #expect(ImportError.incompatibleFormatVersion(found: "2", supported: "1").errorDescription == Self.newer)
    #expect(ImportError.incompatibleManifest(found: "3", supported: "1, 2").errorDescription == Self.newer)
    #expect(ImportError.incompatibleNativeTaskGraph(found: "2", supported: "1").errorDescription == Self.newer)
    #expect(ImportError.incompatibleFormatVersion(found: "0", supported: "1").errorDescription == Self.notABackup)
    #expect(ImportError.incompatibleManifest(found: "v9", supported: "1").errorDescription == Self.notABackup)
    #expect(ImportError.incompatibleManifest(found: "2", supported: "1, 3").errorDescription == Self.notABackup)
  }

  @Test("The decoder's finding stays in the diagnostic description")
  func diagnostics() {
    #expect(ImportError.duplicateArchiveEntry("tasks.json").diagnosticDescription.contains("\"tasks.json\""))
    #expect(
      ImportError.incompatibleFormatVersion(found: "999", supported: "1").diagnosticDescription
        == "The file uses export format 999, but this version supports 1.")
  }

  @Test("An oversized file names its size and the limit in the units Finder shows")
  func tooLarge() {
    let error = LorvexImportLimits.SourceTooLargeError(size: 412_300_000, limit: 64 * 1024 * 1024)
    #expect(error.errorDescription == "The selected file is 412.3 MB. A Lorvex backup can be at most 67.1 MB.")
  }
}
