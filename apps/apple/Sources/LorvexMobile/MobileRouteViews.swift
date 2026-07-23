import LorvexCore
import SwiftUI

struct MobileStoreRouteView: View {
  let route: MobileRoute
  @Bindable var store: MobileStore
  @State private var failedRouteTaskIDs: Set<LorvexTask.ID> = []
  @State private var editingHabit: LorvexHabit?

  var body: some View {
    Group {
      switch route {
      case .task(let id):
        Group {
          if let task = store.resolveTask(id) {
            MobileStoreTaskDetailView(
              store: store,
              task: task,
              isFocused: store.taskIsFocused(task.id),
              isMutating: store.taskIsMutating(task.id),
              saveEditDraft: { draft in await store.saveTaskEditDraft(draft) },
              toggleFocus: { await store.toggleTaskFocus(task.id) },
              complete: { await store.completeTask(task.id) },
              reopen: { await store.reopenTask(task.id) },
              deferTask: { await store.deferTaskToTomorrow(task.id) },
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
              MobileListDetailSkeleton()
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
            deleteHabit: { await store.deleteHabit(habit) },
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
        } else {
          ContentUnavailableView(
            String(
              localized: "route.habit_not_found", defaultValue: "Habit Not Found",
              table: "Localizable", bundle: MobileL10n.bundle),
            systemImage: "questionmark.circle")
        }
      case .list(let id):
        MobileStoreListDetailView(listID: id, store: store)
      case .tasksScope(let scope):
        MobileStoreTasksView(
          store: store, scope: scope, scopeTitle: scope.displayTitle(store: store))
      }
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
      .lorvexSpatialBackground()
    }
  }

  private func loadRouteTask(_ id: LorvexTask.ID) async {
    if await store.refreshTaskForRoute(id) {
      failedRouteTaskIDs.remove(id)
    } else {
      failedRouteTaskIDs.insert(id)
    }
  }
}
