import LorvexCore
import SwiftUI

extension MobileStore {
  func unplannedTodayCandidates(text: String = "", offset: Int = 0, limit: Int = 40) async throws -> TaskPageResult {
    try await core.listTasks(query: TaskListQueryRequest(
      status: LorvexTask.Status.actionableFilter, text: text, availability: "visible",
      plannedPresence: "absent", limit: limit, offset: offset))
  }

  func addExistingTaskToToday(_ task: LorvexTask, on day: String) async -> Bool {
    guard day == logicalTodayString else { return false }
    var changed = false
    _ = await mutateTaskReturningToday(id: task.id) {
      if let change = try await core.planUnscheduledTask(id: task.id, on: day) {
        changed = true
        offerUndo("\(task.title) · \(MobileTab.today.title)") { [weak self] in
          guard let self else { return }
          _ = await self.mutateTaskReturningToday(id: task.id) {
            try await self.core.restoreReviewTasks([change], undo: true)
            return try await self.core.loadToday()
          }
        }
      }
      return try await core.loadToday()
    }
    return changed
  }
}

/// Keeps the free day quiet unless there is work that can actually be chosen.
struct MobileTodayPlanButton: View {
  let store: MobileStore
  @State private var hasCandidates = false
  let openPicker: () -> Void

  var body: some View {
    Group {
      if hasCandidates {
        Button(action: openPicker) {
          Label(Self.title, systemImage: "text.badge.plus")
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("today.chooseTask")
      } else {
        Color.clear.frame(height: 0)
      }
    }
    .task(id: store.taskWorkspaceRevision) {
      if let page = try? await store.unplannedTodayCandidates(limit: 1), !Task.isCancelled {
        hasCandidates = !page.tasks.isEmpty
      }
    }
  }

  static var title: String {
    String(localized: "tasks.detail.empty.title", defaultValue: "Select a Task", table: "Localizable", bundle: MobileL10n.bundle)
  }
}

struct MobileTodayTaskPicker: View {
  let store: MobileStore
  let day: String
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var tasks: [LorvexTask] = []
  @State private var nextOffset: Int?
  @State private var loading = true
  @State private var saving = false

  private struct Search: Equatable {
    let text: String
    let revision: UInt64
  }

  var body: some View {
    NavigationStack {
      List {
        ForEach(tasks) { task in
          Button {
            guard !saving else { return }
            saving = true
            Task {
              if await store.addExistingTaskToToday(task, on: day) { dismiss() }
              saving = false
            }
          } label: {
            VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
              Text(verbatim: task.title).foregroundStyle(.primary)
              if let detail = details(task) {
                Text(verbatim: detail).font(.subheadline).foregroundStyle(.secondary)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
          .disabled(saving)
          .accessibilityIdentifier("today.chooseTask.row.\(task.id)")
        }
        if let nextOffset {
          Button(MobileTodayCalmCopy.briefingMore) { Task { await load(offset: nextOffset) } }
            .disabled(loading)
        }
      }
      .overlay {
        if tasks.isEmpty {
          if loading { ProgressView() } else { MobileEmptyState.search(text: text) }
        }
      }
      .searchable(text: $text)
      .mobileSheetTitle(String(localized: "today.plan_for_today", defaultValue: "Plan for Today",
        table: "Localizable", bundle: MobileL10n.bundle))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(MobileTodayCalmCopy.cancel) { dismiss() }
        }
      }
      .task(id: Search(text: text, revision: store.taskWorkspaceRevision)) { await load(offset: 0) }
      .onChange(of: store.logicalTodayString) { dismiss() }
    }
    .mobileCompactEditorSheetPresentation()
  }

  private func details(_ task: LorvexTask) -> String? {
    let list = store.lists?.lists.first { $0.id == task.listID }?.displayName
      ?? (task.listID == LorvexListNaming.inboxID ? LorvexListNaming.localizedInboxName : nil)
    guard let due = task.dueDate else { return list }
    let deadline = LorvexTaskRowPlan.dueLabel(LorvexDayPhrase.phrase(for: due, logicalDay: day, position: .inline))
    return [list, deadline].compactMap { $0 }.joined(separator: " · ")
  }

  private func load(offset: Int) async {
    let query = text
    let revision = store.taskWorkspaceRevision
    if offset == 0 {
      tasks = []
      nextOffset = nil
    } else if loading || offset != nextOffset { return }
    loading = true
    do {
      let page = try await store.unplannedTodayCandidates(text: query, offset: offset)
      guard !Task.isCancelled, query == text, revision == store.taskWorkspaceRevision else { return }
      let existing = Set(tasks.map(\.id))
      tasks.append(contentsOf: page.tasks.filter { !existing.contains($0.id) })
      nextOffset = page.nextOffset
      loading = false
      if tasks.isEmpty && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { dismiss() }
    } catch {
      guard !Task.isCancelled, query == text, revision == store.taskWorkspaceRevision else { return }
      loading = false
      await store.presentUserFacingError(error)
    }
  }
}
