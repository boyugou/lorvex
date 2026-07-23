import Foundation

/// Closed-inventory verification for the public-v1 single-file backup. Partial
/// exports remain valid: the manifest names exactly the selected categories,
/// not every category the app understands. Internal dependency members ride
/// with their parent category and are deliberately absent from `entityCounts`.
enum BackupV1SingleFileInventory {
  private static let metadataKeys: Set<String> = ["formatVersion", "manifest"]
  private static let allowedTopLevelKeys = metadataKeys.union(
    BackupV1ZipMember.allCases.map(\.singleFileKey))

  static func validate(
    _ data: Data,
    payload: LorvexDataExportPayload
  ) throws {
    let object: [String: Any]
    do {
      guard
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      else {
        throw LorvexDataImporter.ImportError.malformedJSON(
          "the top-level value must be an object")
      }
      object = decoded
    } catch let error as LorvexDataImporter.ImportError {
      throw error
    } catch {
      throw LorvexDataImporter.ImportError.malformedJSON(error.localizedDescription)
    }

    if let unexpected = Set(object.keys).subtracting(allowedTopLevelKeys).sorted().first {
      throw LorvexDataImporter.ImportError.unexpectedJSONMember(unexpected)
    }
    guard let manifest = payload.manifest else {
      throw LorvexDataImporter.ImportError.missingPayloadManifest
    }
    guard manifest.formatVersion == BackupV1Contract.formatVersion else {
      throw LorvexDataImporter.ImportError.incompatibleFormatVersion(
        found: manifest.formatVersion, supported: BackupV1Contract.formatVersion)
    }
    guard manifest.schemaVersion == BackupV1Contract.zipSchemaVersion else {
      throw LorvexDataImporter.ImportError.incompatibleManifest(
        found: manifest.schemaVersion, supported: BackupV1Contract.zipSchemaVersion)
    }

    var observed: [String: Int] = [:]
    func count(
      _ category: LorvexDataExportCategory,
      key: String,
      value: Int?
    ) throws {
      let isPresent = object[key] != nil
      guard isPresent == (value != nil) else {
        throw LorvexDataImporter.ImportError.malformedJSON(
          "top-level \(key) must be an array rather than null")
      }
      if let value { observed[category.rawValue] = value }
    }
    try count(.tasks, key: "tasks", value: payload.tasks?.count)
    try count(.lists, key: "lists", value: payload.lists?.count)
    try count(.tags, key: "tags", value: payload.tags?.count)
    try count(.habits, key: "habits", value: payload.habits?.count)
    try count(
      .calendarEvents, key: "calendarEvents", value: payload.calendarEvents?.count)
    try count(.dailyReviews, key: "dailyReviews", value: payload.dailyReviews?.count)
    try count(.currentFocus, key: "currentFocus", value: payload.currentFocus?.count)
    try count(
      .focusSchedules, key: "focusSchedules", value: payload.focusSchedules?.count)
    try count(
      .taskCalendarEventLinks, key: "taskCalendarEventLinks",
      value: payload.taskCalendarEventLinks?.count)
    try count(.memory, key: "memory", value: payload.memory?.count)
    try count(.preferences, key: "preferences", value: payload.preferences?.count)

    if object["nativeTaskGraph"] != nil, payload.nativeTaskGraph == nil {
      throw LorvexDataImporter.ImportError.malformedJSON(
        "top-level nativeTaskGraph must be an object rather than null")
    }
    if object["calendarSeriesCutovers"] != nil,
      payload.calendarSeriesCutovers == nil
    {
      throw LorvexDataImporter.ImportError.malformedJSON(
        "top-level calendarSeriesCutovers must be an array rather than null")
    }
    try BackupV1PayloadPreflight.validateParentMemberRelationships(payload)

    let declaredKeys = Set(manifest.entityCounts.keys)
    let observedKeys = Set(observed.keys)
    guard declaredKeys == observedKeys else {
      let missing = declaredKeys.subtracting(observedKeys).sorted()
      let extra = observedKeys.subtracting(declaredKeys).sorted()
      var parts: [String] = []
      if !missing.isEmpty {
        parts.append("manifest lists \(missing.joined(separator: ", ")) not present in the file")
      }
      if !extra.isEmpty {
        parts.append("file contains \(extra.joined(separator: ", ")) not listed in the manifest")
      }
      throw LorvexDataImporter.ImportError.manifestCountMismatch(
        parts.joined(separator: "; "))
    }
    for (name, count) in observed.sorted(by: { $0.key < $1.key })
    where manifest.entityCounts[name] != count {
      let declared = manifest.entityCounts[name].map(String.init) ?? "none"
      throw LorvexDataImporter.ImportError.manifestCountMismatch(
        "\(name) holds \(count) records but the manifest declares \(declared)")
    }
  }
}
