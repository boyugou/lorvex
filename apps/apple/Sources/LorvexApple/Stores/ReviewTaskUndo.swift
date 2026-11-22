import Foundation

/// AppKit gives a sheet and its presenting window separate undo managers.
/// Actions still available when the task editor closes belong to the journal.
@MainActor
final class ReviewTaskUndo {
  private let journal: UndoManager
  private var pending: [Action] = []
  private var closed = false

  init(journal: UndoManager) { self.journal = journal }

  func register(named name: String, sheet: UndoManager?, perform: @escaping () -> Void) {
    let action = Action(name: name, perform: perform)
    if closed || sheet === journal {
      // A task mutation can finish after the sheet has already closed.
      action.add(to: journal)
    } else {
      pending.append(action)
      if let sheet { action.add(to: sheet) }
    }
  }

  func finish() {
    closed = true
    for action in pending where action.perform != nil { action.add(to: journal) }
    pending.removeAll()
  }

  @MainActor
  private final class Action {
    let name: String
    var perform: (() -> Void)?
    init(name: String, perform: @escaping () -> Void) {
      self.name = name
      self.perform = perform
    }

    func add(to manager: UndoManager) {
      let needsGroup = manager.groupingLevel == 0
      if needsGroup { manager.beginUndoGrouping() }
      // The registration keeps the action alive after the editor goes away.
      manager.registerUndo(withTarget: self) { [self] _ in
        let operation = perform
        perform = nil
        operation?()
      }
      manager.setActionName(name)
      if needsGroup { manager.endUndoGrouping() }
    }
  }
}
