import LorvexCore
import SwiftUI

struct MobileStoreRouteView: View {
  let route: MobileRoute
  @Bindable var store: MobileStore
  @State private var failedRouteTaskIDs: Set<LorvexTask.ID> = []
  @State private var failedRouteHabitIDs: Set<LorvexHabit.ID> = []
  @State private var editingHabit: LorvexHabit?
  @State private var editingMemoryEntry: MemoryEntry?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    routeContent
      .mobileReadableWidth()
  }

  @ViewBuilder
  private var routeContent: some View {
    Group {
      switch route {
      case .task(let id):
        Group {
          if let task = store.resolveTask(id) {
            MobileStoreTaskDetailView(
              store: store,
              task: task,
              isMutating: store.taskIsMutating(task.id),
              saveEditDraft: { draft in await store.saveTaskEditDraft(draft) },
              actions: store.rowActions(for: task.id),
              reopen: { await store.reopenTask(task.id) },
              markSomeday: { await store.markTaskSomeday(task.id) },
              toggleChecklistItem: { item in await store.toggleChecklistItem(item) },
              addChecklistItem: { text in
                await store.addChecklistItem(taskID: task.id, text: text)
              },
              removeChecklistItem: { item in await store.removeChecklistItem(item) },
              addReminder: { date in await store.addReminder(taskID: task.id, date: date) },
              removeReminder: { reminder in
                await store.removeReminder(taskID: task.id, reminder: reminder)
              },
              cancel: { await store.requestCancelTask(task) },
              tagSuggestions: store.knownTagSuggestions,
              searchDependencyCandidates: { query, excluded in
                await store.dependencyCandidates(matching: query, excluding: excluded)
              },
              resolveDependencyTasks: { ids in await store.dependencyTasks(for: ids) }
            )
            .onAppear {
              store.selectTask(task.id)
            }
          } else if failedRouteTaskIDs.contains(id) {
            ContentUnavailableView(
              String(
                localized: "route.task_not_found", defaultValue: "Task Not Found",
                table: "Localizable", bundle: MobileL10n.bundle),
              systemImage: "questionmark.circle")
          } else {
            List {
              MobileDetailSkeleton()
            }
          }
        }
        // The task belongs to the whole route state machine, including the
        // not-found branch. A transient read failure or later peer recreation
        // therefore retries when the canonical task revision advances instead
        // of leaving this route permanently stuck on its error placeholder.
        .task(id: "\(id)|\(store.taskWorkspaceRevision)") {
          await loadRouteTask(id)
        }
      case .habit(let id):
        Group {
          if let habit = store.habits?.habits.first(where: { $0.id == id }) {
            MobileHabitDetailPanel(
              habit: habit,
              detail: store.habitDetail(for: id),
              isMutating: store.isMutatingHabit || store.isDeletingHabit
                || store.isMutatingHabitReminder,
              editHabit: {
                store.prepareHabitDraft(for: habit)
                editingHabit = habit
              },
              // Archive and Delete pop the page before the habit leaves the
              // list, so it slides away intact and the row then disappears from
              // the list beneath it. A failure surfaces as the store's error.
              deleteHabit: {
                dismiss()
                return await store.deleteHabit(habit)
              },
              archiveHabit: {
                dismiss()
                return await store.setHabitArchived(habit, archived: true)
              },
              complete: { await store.completeHabit(habit) },
              reset: { await store.uncompleteHabit(habit) },
              addReminder: { time in await store.addHabitReminder(habitID: habit.id, time: time) },
              setReminderTime: { policy, time in
                await store.setHabitReminderTime(policy: policy, to: time)
              },
              toggleReminder: { policy in await store.toggleHabitReminderEnabled(policy: policy) },
              removeReminder: { policy in
                await store.removeHabitReminder(habitID: habit.id, policyID: policy.id)
              }
            )
            .onAppear {
              store.selectHabit(id)
            }
            .task(id: "\(id)|\(store.habitDetailRevision)") {
              await store.loadHabitDetail(id: id)
            }
          } else if failedRouteHabitIDs.contains(id) {
            // Shown only after an authoritative reload confirmed the habit is
            // absent — never as a first guess against a not-yet-loaded list.
            ContentUnavailableView(
              String(
                localized: "route.habit_not_found", defaultValue: "Habit Not Found",
                table: "Localizable", bundle: MobileL10n.bundle),
              systemImage: "questionmark.circle")
          } else {
            // The list hasn't loaded yet, or a reload is confirming the target:
            // show a skeleton rather than a false "Habit Not Found". A peer/MCP
            // addition resolves here too, since the branch reads the observed list.
            List {
              MobileDetailSkeleton()
            }
          }
        }
        // Re-key on the observed presence of this habit, not just its id: if the
        // habit disappears out-of-band (a peer/MCP deletion refreshes the list
        // without it) while its detail is open, this re-runs the reconcile so the
        // route reaches "Habit Not Found" instead of a perpetual skeleton.
        .task(id: "\(id)|\(store.habits?.habits.contains(where: { $0.id == id }) == true)") {
          await loadRouteHabit(id)
        }
        .navigationTitle(
          String(
            localized: "detail.habit", defaultValue: "Habit", table: "Localizable",
            bundle: MobileL10n.bundle)
        )
        // The habit's own name is the headline of the content; the generic
        // navigation title stays small so it does not compete with it.
        .toolbarTitleDisplayMode(.inline)
      case .workspace(let destination):
        MobileDestinationView(destination: destination, store: store)
      case .tasksScope(let scope):
        if let listID = scope.listID, let lists = store.lists,
          !lists.lists.contains(where: { $0.id == listID })
        {
          // The loaded catalog has no such list: it was deleted elsewhere, or a
          // stale link named it. Say so rather than show an empty task list.
          ContentUnavailableView(
            String(
              localized: "route.list_not_found", defaultValue: "List Not Found",
              table: "Localizable", bundle: MobileL10n.bundle),
            systemImage: "questionmark.circle")
        } else {
          MobileStoreTasksView(
            store: store, scope: scope, scopeTitle: scope.displayTitle(store: store))
        }
      case .memoryEntry(let id):
        MobileStoreMemoryDetailDestination(
          store: store, initialEntryID: id, edit: { editingMemoryEntry = $0 })
      }
    }
    .sheet(item: $editingMemoryEntry) { entry in
      MobileStoreMemoryEditorSheet(store: store, entry: entry)
    }
    .sheet(item: $editingHabit) { habit in
      MobileStoreEditHabitSheet(
        habit: habit,
        store: store,
        isPresented: Binding(
          get: { editingHabit != nil },
          set: { if !$0 { editingHabit = nil } }
        )
      )
    }
  }

  private func loadRouteTask(_ id: LorvexTask.ID) async {
    if await store.refreshTaskForRoute(id) {
      failedRouteTaskIDs.remove(id)
    } else {
      failedRouteTaskIDs.insert(id)
    }
  }

  private func loadRouteHabit(_ id: LorvexHabit.ID) async {
    if store.habits?.habits.contains(where: { $0.id == id }) == true {
      failedRouteHabitIDs.remove(id)
      return
    }
    let reloaded = await store.reloadHabitsForRoute()
    if store.habits?.habits.contains(where: { $0.id == id }) == true {
      failedRouteHabitIDs.remove(id)
    } else if reloaded {
      // The authoritative list loaded and this id isn't in it — genuinely gone.
      // A transient read failure (`reloaded == false`) instead keeps the
      // skeleton; the next refresh repopulates `habits` and re-resolves here.
      failedRouteHabitIDs.insert(id)
    }
  }
}
