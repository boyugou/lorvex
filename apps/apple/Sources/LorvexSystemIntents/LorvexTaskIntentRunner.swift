import LorvexCore

/// The actions Lorvex's App Intents run. Each one runs the matching
/// ``LorvexSystemIntentRunner`` action and throws its failure as a
/// ``LorvexIntentFailure``, so Shortcuts and Siri show the failure in the
/// interface language instead of the core's English message.
public enum LorvexTaskIntentRunner {
  public static func validatedTaskID(_ id: LorvexTask.ID) throws -> LorvexTask.ID {
    try LorvexIntentFailure.rewording { try LorvexSystemIntentRunner.validatedTaskID(id) }
  }
}
