import Foundation

/// One leg of a list move: the tasks that go into one list. A move out of
/// several lists is undone with one leg per list the tasks came from.
public struct TaskListMoveStep: Equatable, Sendable {
  public let ids: [LorvexTask.ID]
  public let listID: LorvexList.ID

  public init(ids: [LorvexTask.ID], listID: LorvexList.ID) {
    self.ids = ids
    self.listID = listID
  }
}
