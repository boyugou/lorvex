import SwiftUI

/// What a task row and a task's detail say about the task's hand-off to the
/// person's assistant (``LorvexTaskDelegation``): "With assistant" while the
/// assistant holds it, "Assistant replied" once the assistant handed it back.
///
/// Both read with the `sparkles` glyph, the mark of the assistant's voice.
/// Only a reply asks something of the person, so only it takes the accent; a
/// task the assistant still holds reads in the neutral secondary style. Each
/// surface supplies the words from its own string catalog.
public enum LorvexTaskDelegationMarker: Equatable, Sendable {
  /// The assistant holds the task; nothing waits on the person.
  case withAssistant
  /// The assistant handed the task back with a result; it waits for the person.
  case assistantReplied

  /// The marker `task` shows, or nil when it shows none: the task is the
  /// person's own, or it is no longer open work (done, cancelled, parked in
  /// Someday, or in the Trash), where a hand-off asks nothing of anyone.
  public init?(task: LorvexTask) {
    guard task.status.isActionable, task.archivedAt == nil, let delegation = task.delegation
    else { return nil }
    switch delegation.state {
    case .assistant: self = .withAssistant
    case .returned: self = .assistantReplied
    }
  }

  /// The glyph that leads the marker's words.
  public static let systemImage = "sparkles"

  /// Whether the marker asks for the person's attention.
  public var asksForAttention: Bool { self == .assistantReplied }

  /// The color of the glyph and the words.
  public var tint: Color {
    asksForAttention ? LorvexDesign.Palette.accent : LorvexDesign.Palette.neutral
  }
}

/// What the person can do about a task's hand-off to the assistant, offered
/// beside Complete and Defer in a task's menus.
public enum LorvexTaskDelegationAction: Hashable, Sendable {
  /// Hand the task to the assistant, or hand a task it returned over again.
  case handToAssistant
  /// Take the task back: remove its hand-off, whichever state it is in.
  case takeBack

  /// The actions `task` offers, in menu order: Hand to Assistant for a task
  /// that is the person's own or that the assistant handed back, and Take Back
  /// for any task that is handed over. A task that is not open work (done,
  /// cancelled, parked in Someday, or in the Trash) offers neither.
  public static func available(for task: LorvexTask) -> [Self] {
    guard task.status.isActionable, task.archivedAt == nil else { return [] }
    switch task.delegation?.state {
    case nil: return [.handToAssistant]
    case .assistant: return [.takeBack]
    case .returned: return [.handToAssistant, .takeBack]
    }
  }

  /// The SF Symbol the action's menu item carries.
  public var systemImage: String {
    switch self {
    case .handToAssistant: LorvexTaskDelegationMarker.systemImage
    case .takeBack: "arrow.uturn.backward"
    }
  }
}
