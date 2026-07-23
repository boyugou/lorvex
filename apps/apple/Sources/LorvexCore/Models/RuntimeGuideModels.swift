public struct GuideSnapshot: Equatable, Sendable {
  public var topic: String
  public var summary: String
  public var suggestedActions: [String]

  public init(topic: String, summary: String, suggestedActions: [String]) {
    self.topic = topic
    self.summary = summary
    self.suggestedActions = suggestedActions
  }
}
