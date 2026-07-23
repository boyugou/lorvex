import Foundation

extension LorvexSystemIntentRunner {
  public static func updateList(
    id: LorvexList.ID,
    name: String?,
    description: String?,
    core: any LorvexCoreServicing
  ) async throws -> LorvexList {
    let listID = try validatedListID(id)
    let trimmedName = name.trimmedNilIfEmpty
    return try await core.updateList(
      id: listID,
      name: trimmedName,
      description: description.trimmedNilIfEmpty,
      color: nil,
      icon: nil
    )
  }

  public static func deleteList(
    id: LorvexList.ID,
    core: any LorvexCoreServicing
  ) async throws -> LorvexList.ID {
    let listID = try validatedListID(id)
    try await core.deleteList(id: listID)
    return listID
  }

  public static func listAllTags(core: any LorvexCoreServicing) async throws -> [String] {
    try await core.listAllTags()
  }

  public static func renameTag(
    oldTag: String,
    newTag: String,
    core: any LorvexCoreServicing
  ) async throws -> String {
    let oldName = try validatedTagName(oldTag, label: "old tag")
    let newName = try validatedTagName(newTag, label: "new tag")
    try await core.renameTag(oldTag: oldName, newTag: newName)
    return newName
  }

  public static func getTasksByTag(
    tag: String,
    core: any LorvexCoreServicing
  ) async throws -> [LorvexTask] {
    let tagName = try validatedTagName(tag, label: "tag")
    return try await core.getTasksByTag(tag: tagName)
  }

  public static func validatedListID(_ id: LorvexList.ID) throws -> LorvexList.ID {
    let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.validation(field: "list_id", message: "A list ID is required.")
    }
    return trimmed
  }

  private static func validatedTagName(_ tag: String, label: String) throws -> String {
    let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.validation(field: nil, message: "A \(label) is required.")
    }
    return trimmed
  }
}
