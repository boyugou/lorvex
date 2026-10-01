extension LorvexSystemIntentRunner {
  /// The tasks with a time on `date` (today when nil), in start order, with
  /// the day they were read for.
  public static func readDayTimes(
    date: String?,
    core: any LorvexCoreServicing
  ) async throws -> (date: String, tasks: [LorvexTask]) {
    let resolvedDate = try await logicalDay(date, core: core)
    return (resolvedDate, try await core.loadTimedTasks(from: resolvedDate, through: resolvedDate))
  }

  /// Suggested times for the tasks on `date` (today when nil). Nothing is
  /// stored.
  public static func proposeDayTimes(
    date: String?,
    core: any LorvexCoreServicing
  ) async throws -> DayTimesProposal {
    let resolvedDate = try await logicalDay(date, core: core)
    return try await core.proposeDayTimes(date: resolvedDate)
  }

  /// Suggest times for the tasks on `date` (today when nil) and save them as
  /// the day's times, then return the suggestion. Saving a day clears the
  /// times of its unfinished tasks the suggestion left out, so a suggestion
  /// that places nothing — the working time is over, or nothing fits — is not
  /// saved, and the day keeps the times it has.
  public static func saveProposedDayTimes(
    date: String?,
    core: any LorvexCoreServicing
  ) async throws -> DayTimesProposal {
    let resolvedDate = try await logicalDay(date, core: core)
    let proposal = try await core.proposeDayTimes(date: resolvedDate)
    guard !proposal.placements.isEmpty else { return proposal }
    _ = try await core.saveDayTimes(date: proposal.date, times: proposal.times)
    return proposal
  }
}
