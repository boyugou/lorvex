import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  public func loadHabits(date: String) async throws -> HabitCatalogSnapshot {
    try read { db in
      try Self.loadHabitsSnapshot(db, date: date)
    }
  }

  public func loadArchivedHabits(date: String) async throws -> HabitCatalogSnapshot {
    try read { db in
      try Self.loadHabitsSnapshot(db, date: date, archived: true)
    }
  }
}
