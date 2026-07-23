import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  public func createListForMcpIfAbsent(_ list: ExportList) async throws -> LorvexList {
    let fields = try Self.normalizedListFields(
      name: list.name, description: list.description, color: list.color, icon: list.icon,
      aiNotes: list.aiNotes)
    return try withWrite { db, hlc, deviceId in
      if let row = try ListRepo.getList(db, id: ListId(trusted: list.id)) {
        let counts = try Self.listCounts(db, id: list.id)
        return SwiftLorvexListDeserializers.list(
          row, openCount: counts.open, totalCount: counts.total)
      }
      if try Tombstone.isTombstoned(
        db, entityType: EntityName.list, entityId: list.id)
      {
        throw LorvexCoreError.conflict(
          message:
            "That original_id belongs to a deleted list. Omit original_id to create a new list.")
      }
      return try self.writeImportedListInTx(
        db, hlc: hlc, deviceId: deviceId, id: list.id, fields: fields,
        archivedAt: list.archivedAt, position: list.position)
    }
  }

  public func createHabitForMcpIfAbsent(_ habit: ExportHabit) async throws -> LorvexHabit {
    let milestone = try Self.normalizedMilestoneTarget(habit.milestoneTarget)
    return try withWrite { db, hlc, deviceId in
      if let row = try Self.habitColumnRow(db, id: habit.id) {
        let today = try WorkflowTimezone.todayYmdForConn(db)
        return try Self.mapHabitRow(db, row: row, date: today)
      }
      if try Tombstone.isTombstoned(
        db, entityType: EntityName.habit, entityId: habit.id)
      {
        throw LorvexCoreError.conflict(
          message:
            "That original_id belongs to a deleted habit. Omit original_id to create a new habit.")
      }
      return try self.upsertImportedHabitInTx(
        db, hlc: hlc, deviceId: deviceId, id: habit.id, name: habit.name,
        icon: habit.icon, color: habit.color, cue: habit.cue,
        frequencyType: habit.frequencyType, weekdays: habit.weekdays,
        perPeriodTarget: habit.perPeriodTarget, dayOfMonth: habit.dayOfMonth,
        targetCount: habit.targetCount, milestone: milestone, archived: habit.archived,
        position: habit.position)
    }
  }
}

extension SwiftLorvexCoreService: LorvexMcpMutationServicing {}
