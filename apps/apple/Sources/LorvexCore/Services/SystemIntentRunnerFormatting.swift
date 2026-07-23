import Foundation

extension LorvexSystemIntentRunner {
  static func logicalDay(
    _ explicitDate: String?,
    core: any LorvexCoreServicing
  ) async throws -> String {
    if let explicitDate = explicitDate.trimmedNilIfEmpty {
      return explicitDate
    }
    return try await core.getSessionContext().date
  }

  static func storageDate(
    byAddingDays days: Int,
    toLogicalDay logicalDay: String
  ) throws -> Date {
    guard
      let shifted = LorvexDateFormatters.ymdUTCAddingDays(logicalDay, days: days),
      let date = LorvexDateFormatters.ymdUTC.date(from: shifted)
    else {
      throw LorvexCoreError.unsupportedOperation("Couldn't compute the requested calendar date.")
    }
    return date
  }
}
