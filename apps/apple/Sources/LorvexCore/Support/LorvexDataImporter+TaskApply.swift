import Foundation

extension LorvexDataImporter {
  /// One imported task's deferred work — the steps that must run only after every
  /// task in the batch exists (dependency edges may forward-reference a task
  /// imported later) or that refine an already-consistent record (cancelled
  /// state, exact metadata). The native path carries the exact create-version
  /// witness so all refinement happens under one write lock only if no live edit
  /// intervened; simpler backends receive dependency-only patches.
  struct DeferredTaskWork {
    let task: ExportTask
    let creationWitness: ImportedTaskRecordCreationWitness?
  }

  static func applyTasks(
    _ tasks: [ExportTask],
    nativeTaskGraph: NativeTaskGraphSnapshot?,
    permitExactNativeRestore: Bool,
    using core: any LorvexCoreServicing
  ) async -> (LorvexImportCategoryResult, [LorvexImportIssue]) {
    // A native backup can preserve the complete task aggregate exactly, but
    // only the concrete Apple core can prove the entire task domain is fresh
    // and materialize it atomically. Missing roots or any pre-existing task
    // state deliberately falls through to the portable, per-record importer.
    if permitExactNativeRestore, let nativeTaskGraph,
      let nativeImporter = core as? any LorvexNativeTaskGraphImportServicing
    {
      guard
        taskIdentityMultiset(tasks, id: \.id)
          == taskIdentityMultiset(nativeTaskGraph.tasks, id: \.id)
      else {
        let error = NativeTaskGraphImportError.invalidGraph(
          "the native and portable task projections contain different task identities")
        return (
          LorvexImportCategoryResult(category: .tasks, imported: 0, skipped: 0),
          [
            LorvexImportIssue(
              category: .tasks, record: .wholeCategory, outcome: .notImported,
              detail: error.localizedDescription)
          ]
        )
      }
      do {
        switch try await nativeImporter.importNativeTaskGraphIfFresh(nativeTaskGraph) {
        case .imported(let taskCount):
          return (
            LorvexImportCategoryResult(
              category: .tasks, imported: taskCount, skipped: 0),
            []
          )
        case .portableFallback:
          break
        }
      } catch {
        return (
          LorvexImportCategoryResult(category: .tasks, imported: 0, skipped: 0),
          [
            LorvexImportIssue(
              category: .tasks, record: .wholeCategory, outcome: .notImported,
              detail: error.localizedDescription)
          ]
        )
      }
    }

    var deferredWork: [DeferredTaskWork] = []
    let created: (imported: Int, skipped: Int, errors: [LorvexImportIssue])
    // Restore each task record atomically when the backend supports it (create +
    // list + checklist + reminders + recurrence in one transaction), so a child
    // failure rolls the whole task — and its outbox envelopes — back rather than
    // leaving a half-applied task. Fall back to per-operation restore otherwise.
    if let tx = core as? any LorvexNativeImportServicing {
      created = await createTasksTransactionally(tasks, tx: tx, deferredWork: &deferredWork)
    } else {
      created = await createTasksPerOperation(tasks, using: core, deferredWork: &deferredWork)
    }
    var errors = created.errors
    errors.append(contentsOf: await applyDeferredTaskWork(deferredWork, using: core))
    return (
      LorvexImportCategoryResult(
        category: .tasks, imported: created.imported, skipped: created.skipped),
      errors
    )
  }

  /// The native graph and portable rows are two representations of one backup,
  /// so exact restore is allowed only when their task identity multisets match.
  /// A frequency map catches both missing identities and duplicate-count drift.
  private static func taskIdentityMultiset<T>(
    _ tasks: [T], id: KeyPath<T, String>
  ) -> [String: Int] {
    tasks.reduce(into: [:]) { counts, task in
      counts[task[keyPath: id], default: 0] += 1
    }
  }

  /// Create each task record atomically through the transactional backend seam.
  /// Parse errors (unknown priority, unparseable dates) are reported and the task
  /// skipped, matching the per-operation path; a successfully created task is
  /// queued for the shared deferred pass.
  private static func createTasksTransactionally(
    _ tasks: [ExportTask], tx: any LorvexNativeImportServicing,
    deferredWork: inout [DeferredTaskWork]
  ) async -> (imported: Int, skipped: Int, errors: [LorvexImportIssue]) {
    var imported = 0
    var skipped = 0
    var errors: [LorvexImportIssue] = []
    for task in tasks {
      guard let parsed = parseTaskCreateFields(task, into: &errors) else { continue }
      do {
        let witness = try await tx.importTaskRecordTransactionally(
          task, priority: parsed.priority, dueDate: parsed.dueDate,
          plannedDate: parsed.plannedDate, availableFrom: parsed.availableFrom,
          dependenciesToApply: [])
        if let witness {
          imported += 1
          deferredWork.append(DeferredTaskWork(task: task, creationWitness: witness))
        } else {
          skipped += 1
        }
      } catch {
        errors.append(.notImported(task, error.localizedDescription))
      }
    }
    return (imported, skipped, errors)
  }

  /// Best-effort per-operation restore for a backend without the transactional
  /// record seam: create the task, then attach list / checklist / reminders /
  /// recurrence as independent operations (each failure reported but tolerated).
  private static func createTasksPerOperation(
    _ tasks: [ExportTask], using core: any LorvexCoreServicing,
    deferredWork: inout [DeferredTaskWork]
  ) async -> (imported: Int, skipped: Int, errors: [LorvexImportIssue]) {
    var imported = 0
    var skipped = 0
    var errors: [LorvexImportIssue] = []
    for task in tasks {
      let exists: Bool
      do {
        _ = try await core.loadTask(id: task.id)
        exists = true
      } catch LorvexCoreError.taskNotFound {
        exists = false
      } catch {
        errors.append(.notImported(task, error.localizedDescription))
        continue
      }
      if exists {
        skipped += 1
        continue
      }

      guard let parsed = parseTaskCreateFields(task, into: &errors) else { continue }
      // `cancelled` and `in_progress` cannot be expressed by a plain create; both
      // land as `.open` and are reached by a transition in the deferred pass.
      let createStatus: LorvexTask.Status =
        (parsed.status == .cancelled || parsed.status == .inProgress) ? .open : parsed.status
      do {
        // Dependencies are attached in a second pass: a task may depend on
        // one imported later in this same batch.
        _ = try await core.importRemoteTask(
          id: task.id,
          title: task.title,
          notes: task.notes ?? "",
          aiNotes: task.aiNotes,
          rawInput: task.rawInput,
          priority: parsed.priority,
          status: createStatus,
          estimatedMinutes: task.estimatedMinutes,
          dueDate: parsed.dueDate,
          plannedDate: parsed.plannedDate,
          availableFrom: parsed.availableFrom,
          tags: parsed.tags,
          dependsOn: [])
        if let plannedTime = parsed.plannedTime {
          do {
            _ = try await core.updateTask(
              TaskUpdateDraft(id: task.id, plannedTime: .set(plannedTime)))
          } catch {
            errors.append(
              .restored(
                task, without: .plannedTime,
                "Restored without its planned time: \(error.localizedDescription)"))
          }
        }
        if let listID = task.listID {
          do {
            _ = try await core.moveTask(id: task.id, toListID: listID)
          } catch {
            // The task itself restored; only its list membership did not.
            errors.append(
              .restored(
                task, without: .list,
                "Restored without list \"\(listID)\": \(error.localizedDescription)"))
          }
        }
        if let checklistError = await restoreChecklist(task, using: core) {
          errors.append(checklistError)
        }
        if let reminderError = await restoreReminders(task, using: core) {
          errors.append(reminderError)
        }
        if let recurrenceError = await restoreRecurrence(task, using: core) {
          errors.append(recurrenceError)
        }
        deferredWork.append(DeferredTaskWork(task: task, creationWitness: nil))
        imported += 1
      } catch {
        errors.append(.notImported(task, error.localizedDescription))
      }
    }
    return (imported, skipped, errors)
  }

  /// After every task in the batch exists: attach dependency edges (which may
  /// forward-reference a task imported later), apply lifecycle state, and restore
  /// exact metadata. The native finalizer first matches the task's exact creation
  /// witness and then holds one transaction around savepoint-isolated steps, so
  /// backup refinement cannot overwrite an edit made after create.
  private static func applyDeferredTaskWork(
    _ deferredWork: [DeferredTaskWork], using core: any LorvexCoreServicing
  ) async -> [LorvexImportIssue] {
    var errors: [LorvexImportIssue] = []
    for work in deferredWork {
      if let witness = work.creationWitness,
        let nativeImporter = core as? any LorvexNativeImportServicing
      {
        do {
          let result = try await nativeImporter.finalizeImportedTaskRecordTransactionally(
            work.task, creationWitness: witness)
          guard result.matchedCreationWitness else {
            // The deferred pass never overwrites an edit made after create, so
            // every detail it would have applied stays out.
            errors.append(
              contentsOf: deferredParts(of: work.task).map {
                .restored(
                  work.task, without: $0,
                  "Skipped deferred restore because the task changed after its backup row was created."
                )
              })
            continue
          }
          for failure in result.failures {
            errors.append(
              .restored(
                work.task, without: deferredPart(failure.step),
                deferredFailureMessage(failure, status: work.task.status)))
          }
        } catch {
          errors.append(
            contentsOf: deferredParts(of: work.task).map {
              .restored(
                work.task, without: $0,
                "Could not finish the task restore: \(error.localizedDescription)")
            })
        }
        continue
      }

      if let dependsOn = work.task.dependsOn, !dependsOn.isEmpty {
        do {
          _ = try await core.updateTask(
            TaskUpdateDraft(id: work.task.id, dependsOn: dependsOn))
        } catch {
          errors.append(
            .restored(
              work.task, without: .dependencies,
              "Restored without dependencies: \(error.localizedDescription)"))
        }
      }
      if work.task.status == LorvexTask.Status.cancelled.rawValue {
        do {
          _ = try await core.cancelTask(id: work.task.id)
        } catch {
          errors.append(
            .restored(
              work.task, without: .status,
              "Restored without cancelled status: \(error.localizedDescription)"))
        }
      }
      do {
        try await core.restoreImportedTaskMetadata(
          id: work.task.id,
          archivedAt: work.task.archivedAt,
          deferCount: work.task.deferCount,
          lastDeferReason: work.task.lastDeferReason,
          lastDeferredAt: work.task.lastDeferredAt,
          completedAt: work.task.completedAt,
          createdAt: work.task.createdAt,
          updatedAt: work.task.updatedAt)
      } catch {
        errors.append(
          .restored(
            work.task, without: .history,
            "Restored without exact task metadata: \(error.localizedDescription)"))
      }
    }
    // Apply `in_progress` last, once every identity and dependency exists. The
    // concrete native importer restores the exact persisted state without the
    // interactive start gate: a task may legally have started first and acquired
    // an unresolved dependency later. Simpler backends retain the ordinary start
    // command as their best-effort fallback.
    for work in deferredWork
    where work.creationWitness == nil
      && work.task.status == LorvexTask.Status.inProgress.rawValue
    {
      do {
        if let nativeImporter = core as? any LorvexNativeImportServicing {
          try await nativeImporter.restoreImportedTaskLifecycleState(
            id: work.task.id, status: .inProgress)
        } else {
          _ = try await core.startTask(id: work.task.id)
        }
      } catch {
        errors.append(
          .restored(
            work.task, without: .status,
            "Restored without in_progress status: \(error.localizedDescription)"))
      }
    }
    return errors
  }

  /// The details the deferred pass applies to `task`: its dependencies when it
  /// has any, a cancelled or in-progress status, and always its history.
  private static func deferredParts(of task: ExportTask) -> [LorvexImportIssue.Part] {
    var parts: [LorvexImportIssue.Part] = []
    if let dependsOn = task.dependsOn, !dependsOn.isEmpty { parts.append(.dependencies) }
    if task.status == LorvexTask.Status.cancelled.rawValue
      || task.status == LorvexTask.Status.inProgress.rawValue
    {
      parts.append(.status)
    }
    parts.append(.history)
    return parts
  }

  private static func deferredPart(
    _ step: ImportedTaskRecordFinalizeStep
  ) -> LorvexImportIssue.Part {
    switch step {
    case .dependencies: .dependencies
    case .metadata: .history
    case .lifecycle: .status
    }
  }

  private static func deferredFailureMessage(
    _ failure: ImportedTaskRecordFinalizeFailure,
    status: String
  ) -> String {
    switch failure.step {
    case .dependencies:
      return "Restored without dependencies: \(failure.message)"
    case .metadata:
      return "Restored without exact task metadata: \(failure.message)"
    case .lifecycle:
      let label = status == LorvexTask.Status.cancelled.rawValue ? "cancelled" : "in_progress"
      return "Restored without \(label) status: \(failure.message)"
    }
  }

  /// Parse the create-time fields shared by both restore paths (priority, the
  /// three optional dates, the planned time, tags, status). On any parse
  /// failure — unknown priority, unparseable date or time, or unrecognized
  /// status — appends a per-record error and returns nil so the caller skips
  /// the task. Status parsing is strict: every accepted value must be a current
  /// ``LorvexTask/Status`` wire value.
  private static func parseTaskCreateFields(
    _ task: ExportTask, into errors: inout [LorvexImportIssue]
  ) -> (
    priority: LorvexTask.Priority, status: LorvexTask.Status, dueDate: Date?, plannedDate: Date?,
    plannedTime: Range<Int>?, availableFrom: Date?, tags: [String]
  )? {
    guard let priority = LorvexTask.Priority(rawValue: task.priority) else {
      errors.append(.notImported(task, "Unknown priority \"\(task.priority)\"."))
      return nil
    }
    let parsedDueDate = parseOptionalTaskDate(task.dueDate, of: task, field: "dueDate")
    if let error = parsedDueDate.error {
      errors.append(error)
      return nil
    }
    let parsedPlannedDate = parseOptionalTaskDate(
      task.plannedDate, of: task, field: "plannedDate")
    if let error = parsedPlannedDate.error {
      errors.append(error)
      return nil
    }
    let parsedAvailableFrom = parseOptionalTaskDate(
      task.availableFrom, of: task, field: "availableFrom")
    if let error = parsedAvailableFrom.error {
      errors.append(error)
      return nil
    }
    let plannedTime: Range<Int>?
    do {
      plannedTime = try task.plannedTimeRange()
    } catch {
      errors.append(.notImported(task, error.localizedDescription))
      return nil
    }
    guard let status = LorvexTask.Status(rawValue: task.status) else {
      errors.append(.notImported(task, "Unknown status \"\(task.status)\"."))
      return nil
    }
    let tags = task.tags ?? []
    return (
      priority, status, parsedDueDate.date, parsedPlannedDate.date, plannedTime,
      parsedAvailableFrom.date, tags
    )
  }

  /// Re-apply the recurrence rule and its skipped-occurrence dates. Returns a
  /// per-record error (the task itself already restored) on failure or an
  /// unknown frequency.
  private static func restoreRecurrence(
    _ task: ExportTask, using core: any LorvexCoreServicing
  ) async -> LorvexImportIssue? {
    guard let exported = task.recurrence else { return nil }
    guard let rule = exported.rule else {
      return .restored(
        task, without: .recurrence,
        "Restored without recurrence: unknown frequency \"\(exported.freq)\".")
    }
    do {
      _ = try await core.setTaskRecurrence(taskID: task.id, rule: rule)
      if let exceptions = task.recurrenceExceptions, !exceptions.isEmpty {
        for date in exceptions {
          _ = try await core.addTaskRecurrenceException(taskID: task.id, exceptionDate: date)
        }
      }
      return nil
    } catch {
      return .restored(
        task, without: .recurrence, "Restored without recurrence: \(error.localizedDescription)")
    }
  }

  /// Re-create the checklist rows in export order, re-checking the completed
  /// ones. Returns a per-record error (the task itself already restored) on
  /// the first failure.
  private static func restoreChecklist(
    _ task: ExportTask, using core: any LorvexCoreServicing
  ) async -> LorvexImportIssue? {
    guard let checklist = task.checklist, !checklist.isEmpty else { return nil }
    do {
      if checklist.allSatisfy({ $0.id != nil }),
        let importing = core as? any LorvexNativeImportServicing
      {
        for item in checklist {
          try await importing.importTaskChecklistItem(taskID: task.id, item: item)
        }
        return nil
      }
      for item in checklist {
        let updated = try await core.addTaskChecklistItem(taskID: task.id, text: item.text)
        if item.completed, let added = updated.checklistItems.max(by: { $0.position < $1.position })
        {
          _ = try await core.toggleTaskChecklistItem(itemID: added.id, completed: true)
        }
      }
      return nil
    } catch {
      return .restored(
        task, without: .checklist, "Restored without full checklist: \(error.localizedDescription)")
    }
  }

  private static func restoreReminders(
    _ task: ExportTask, using core: any LorvexCoreServicing
  ) async -> LorvexImportIssue? {
    if let reminders = task.reminders, !reminders.isEmpty {
      guard let importing = core as? any LorvexNativeImportServicing else {
        return .restored(
          task, without: .reminders,
          "Restored without reminders: exact reminder import is unsupported.")
      }
      do {
        for reminder in reminders {
          try await importing.importTaskReminder(taskID: task.id, reminder: reminder)
        }
        return nil
      } catch {
        return .restored(
          task, without: .reminders, "Restored without reminders: \(error.localizedDescription)")
      }
    }
    return nil
  }

  private static func parseOptionalTaskDate(
    _ raw: String?,
    of task: ExportTask,
    field: String
  ) -> (date: Date?, error: LorvexImportIssue?) {
    guard let raw else { return (nil, nil) }
    // Accept both the fractional-millisecond `Z` shape the exporter now emits and
    // the plain internet-date-time form, so a date round-trips regardless of
    // sub-second precision.
    guard
      let date = LorvexDateFormatters.iso8601Fractional.date(from: raw)
        ?? LorvexDateFormatters.iso8601.date(from: raw)
    else {
      return (nil, .notImported(task, "Unparseable \(field) \"\(raw)\"."))
    }
    return (date, nil)
  }
}

extension LorvexImportIssue {
  /// A backup task the import did not restore, named by its title.
  fileprivate static func notImported(_ task: ExportTask, _ detail: String) -> Self {
    LorvexImportIssue(
      category: .tasks, record: .named(id: task.id, name: task.title), outcome: .notImported,
      detail: detail)
  }

  /// A backup task restored without one of its details, named by its title.
  fileprivate static func restored(
    _ task: ExportTask, without part: Part, _ detail: String
  ) -> Self {
    LorvexImportIssue(
      category: .tasks, record: .named(id: task.id, name: task.title),
      outcome: .restoredWithout(part), detail: detail)
  }
}
