/// Numeric-range validators (priority, estimated_minutes, mood,
/// reminder window).
public enum ValidationNumeric {
  /// Inclusive-range check shared by every numeric validator. Emits
  /// ``ValidationError/outOfRange(field:min:max:actual:)`` with the supplied
  /// field label on a miss.
  static func checkRange(
    field: String, min: Int64, max: Int64, actual: Int64
  ) -> Result<Void, ValidationError> {
    if actual < min || actual > max {
      return .failure(.outOfRange(field: field, min: min, max: max, actual: actual))
    }
    return .success(())
  }

  /// Validate a task priority value: must be in ``ValidationLimits/priorityMin``...``ValidationLimits/priorityMax``.
  public static func validatePriority(_ p: Int64) -> Result<Void, ValidationError> {
    checkRange(
      field: "priority", min: ValidationLimits.priorityMin, max: ValidationLimits.priorityMax,
      actual: p)
  }

  /// Validate estimated_minutes: must be in 1...``ValidationLimits/maxEstimatedMinutes``.
  /// Zero is rejected — "no work" is not a meaningful estimate.
  public static func validateEstimatedMinutes(_ m: Int64) -> Result<Void, ValidationError> {
    checkRange(field: "estimated_minutes", min: 1, max: ValidationLimits.maxEstimatedMinutes, actual: m)
  }

  /// Validate a mood or energy_level rating: must be in ``ValidationLimits/moodMin``...``ValidationLimits/moodMax``.
  public static func validateMood(_ value: Int64) -> Result<Void, ValidationError> {
    checkRange(field: "mood", min: ValidationLimits.moodMin, max: ValidationLimits.moodMax, actual: value)
  }

  /// Validate a reminder window in seconds: must be in 0...``ValidationLimits/maxReminderWindowSeconds``.
  public static func validateReminderWindow(_ seconds: Int64) -> Result<Void, ValidationError> {
    checkRange(
      field: "reminder_window", min: 0, max: ValidationLimits.maxReminderWindowSeconds, actual: seconds)
  }
}
