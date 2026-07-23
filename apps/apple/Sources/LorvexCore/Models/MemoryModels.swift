import Foundation

// MARK: - Memory Models

public struct MemorySnapshot: Equatable, Sendable {
  public var entries: [MemoryEntry]

  public init(entries: [MemoryEntry]) {
    self.entries = entries
  }
}

public struct MemoryEntry: Identifiable, Equatable, Sendable {
  public var id: String { key }
  public var key: String
  public var content: String
  public var updatedAt: String

  public init(
    key: String,
    content: String,
    updatedAt: String
  ) {
    self.key = key
    self.content = content
    self.updatedAt = updatedAt
  }
}
