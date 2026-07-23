enum TaskStatusOperation: Equatable {
  case start
  case pause
  case cancel
  case reopen

  var status: String {
    switch self {
    case .start: "in_progress"
    case .pause: "open"
    case .cancel: "cancelled"
    case .reopen: "open"
    }
  }

  var toolOperation: String {
    switch self {
    case .start: "task.start"
    case .pause: "task.pause"
    case .cancel: "task.cancel"
    case .reopen: "task.reopen"
    }
  }

  var verb: String {
    switch self {
    case .start: "Started"
    case .pause: "Paused"
    case .cancel: "Cancelled"
    case .reopen: "Reopened"
    }
  }

  /// The MCP tool name that drives this operation, for id-validation and
  /// not-found error messages.
  var toolName: String {
    switch self {
    case .start: "start_task"
    case .pause: "pause_task"
    case .cancel: "cancel_task"
    case .reopen: "reopen_task"
    }
  }
}
