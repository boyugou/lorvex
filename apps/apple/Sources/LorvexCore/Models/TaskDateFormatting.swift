import Foundation

public extension LorvexTask {
  var dueDateDisplaySummary: String? {
    dueDate?.formatted(date: .abbreviated, time: .omitted)
  }
}
