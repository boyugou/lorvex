#if DEBUG
  import LorvexCore

  extension LorvexUIPreview {
    /// The Tasks stops that follow the workspace's own: the inspector on
    /// Today's first task, on a task that waits on an unfinished one, and on a
    /// task the assistant handed back; with the stress seed, the inspector on
    /// each of its hardest tasks; then the workspace scoped to a list, and a
    /// search whose matches sit in the notes. Each stop ends with nothing
    /// selected and no scope or search left behind.
    @MainActor
    static func emitTaskStops(store: AppStore) async {
      if let first = store.today.tasks.first {
        store.selectedTaskID = first.id
        try? await Task.sleep(for: .seconds(2.5))
        await emitStop("tasks-inspector")
        store.selectedTaskID = nil
      }
      if !usesEmptyStore {
        // A task that waits on an unfinished task: Start stays in place
        // but unavailable until that task is done.
        store.selectedTaskID = LorvexPreviewSeedID.venueTask
        try? await Task.sleep(for: .seconds(2.5))
        if store.selectedTask != nil { await emitStop("tasks-inspector-waiting") }
        store.selectedTaskID = nil
      }
      if let replied = store.today.tasks.first(where: { $0.delegation?.state == .returned }) {
        // A task the assistant handed back: its marker in the header, its
        // reply in the assistant's notes.
        store.selectedTaskID = replied.id
        try? await Task.sleep(for: .seconds(2.5))
        await emitStop("tasks-inspector-assistant")
        store.selectedTaskID = nil
      }
      if LorvexStressSeed.isRequested {
        // The stress seed's hardest tasks, one inspector each.
        for (stop, titlePrefix) in LorvexStressSeed.inspectorTasks {
          guard let task = store.taskWorkspaceOpenTasks.first(where: { $0.title.hasPrefix(titlePrefix) })
          else { continue }
          store.selectedTaskID = task.id
          try? await Task.sleep(for: .seconds(2.5))
          await emitStop(stop)
        }
        store.selectedTaskID = nil
      }
      if let list = tourList(in: store) {
        // The same workspace scoped to a list, as the sidebar opens it.
        store.setTaskWorkspaceListScope(list.id)
        try? await Task.sleep(for: .seconds(2.5))
        await emitStop("tasks-list")
        store.setTaskWorkspaceListScope(nil)
      }
      if !usesEmptyStore {
        // A search whose matches sit in the notes: the rows quote the text
        // around the word under each title that lacks it.
        store.searchText = "team"
        try? await Task.sleep(for: .seconds(2.5))
        await emitStop("tasks-search")
        store.searchText = ""
      }
    }
  }
#endif
