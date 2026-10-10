import LorvexDomain

extension LorvexSystemIntentRunner {
  /// `value` held to the range a habit's per-day target takes, at least 1 and
  /// at most ``ValidationLimits/maxHabitTargetCount``.
  static func clampedHabitTargetCount(_ value: Int) -> Int {
    min(max(1, value), Int(ValidationLimits.maxHabitTargetCount))
  }

  public static func updateHabit(
    id: LorvexHabit.ID,
    name: String?,
    cue: String?,
    targetCount: Int?,
    core: any LorvexCoreServicing
  ) async throws -> LorvexHabit {
    // Behavior-preserving: an absent/blank cue leaves the stored value, a
    // non-blank cue sets it. The intent surface has no explicit "clear" affordance.
    try await core.updateHabit(
      id: validatedHabitID(id),
      name: name.trimmedNilIfEmpty,
      cue: cue.trimmedNilIfEmpty.map { .set($0) } ?? .unset,
      color: nil,
      icon: nil,
      targetCount: targetCount.map(clampedHabitTargetCount)
    )
  }

  public static func deleteHabit(
    id: LorvexHabit.ID,
    core: any LorvexCoreServicing
  ) async throws -> LorvexHabit.ID {
    let habitID = try validatedHabitID(id)
    _ = try await core.deleteHabit(id: habitID)
    return habitID
  }

  public static func completeHabit(
    id: LorvexHabit.ID,
    date: String?,
    core: any LorvexCoreServicing
  ) async throws -> LorvexHabit {
    let habitID = try validatedHabitID(id)
    let completionDate = try await logicalDay(date, core: core)
    let snapshot = try await core.completeHabit(id: habitID, date: completionDate)
    return try habit(id: habitID, in: snapshot)
  }

  public static func uncompleteHabit(
    id: LorvexHabit.ID,
    date: String?,
    core: any LorvexCoreServicing
  ) async throws -> LorvexHabit {
    let habitID = try validatedHabitID(id)
    let completionDate = try await logicalDay(date, core: core)
    let snapshot = try await core.uncompleteHabit(id: habitID, date: completionDate)
    return try habit(id: habitID, in: snapshot)
  }

  /// Sets `date` (today when nil) aside for the habit: the day counts as
  /// neither done nor missed. The core refuses a day that already holds a
  /// check-in, and skipping an already skipped day changes nothing.
  public static func skipHabit(
    id: LorvexHabit.ID,
    date: String?,
    core: any LorvexCoreServicing
  ) async throws -> LorvexHabit {
    let habitID = try validatedHabitID(id)
    let skipDate = try await logicalDay(date, core: core)
    let snapshot = try await core.skipHabit(id: habitID, date: skipDate)
    return try habit(id: habitID, in: snapshot)
  }

  /// Takes back the skip of `date` (today when nil), so the day is open again.
  /// A day that was not skipped is left as it is.
  public static func unskipHabit(
    id: LorvexHabit.ID,
    date: String?,
    core: any LorvexCoreServicing
  ) async throws -> LorvexHabit {
    let habitID = try validatedHabitID(id)
    let skipDate = try await logicalDay(date, core: core)
    let snapshot = try await core.unskipHabit(id: habitID, date: skipDate)
    return try habit(id: habitID, in: snapshot)
  }

  public static func validatedHabitID(_ id: LorvexHabit.ID) throws -> LorvexHabit.ID {
    let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.validation(field: "habit_id", message: "A habit ID is required.")
    }
    return trimmed
  }

  private static func habit(id: LorvexHabit.ID, in snapshot: HabitCatalogSnapshot) throws
    -> LorvexHabit
  {
    guard let habit = snapshot.habits.first(where: { $0.id == id }) else {
      throw LorvexCoreError.unsupportedOperation("The selected habit does not exist.")
    }
    return habit
  }
}
