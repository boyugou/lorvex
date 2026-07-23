extension LorvexSystemIntentRunner {
  public static func updateHabit(
    id: LorvexHabit.ID,
    name: String?,
    cue: String?,
    targetCount: Int?,
    core: any LorvexCoreServicing
  ) async throws -> LorvexHabit {
    try await core.updateHabit(
      id: validatedHabitID(id),
      name: name.trimmedNilIfEmpty,
      cue: cue.trimmedNilIfEmpty,
      color: nil,
      icon: nil,
      targetCount: targetCount.map { max(1, $0) }
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
