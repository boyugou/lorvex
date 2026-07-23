import LorvexCore

public enum LorvexTaskIntentRunner {
  public static func validatedTaskID(_ id: LorvexTask.ID) throws -> LorvexTask.ID {
    try LorvexSystemIntentRunner.validatedTaskID(id)
  }
}
