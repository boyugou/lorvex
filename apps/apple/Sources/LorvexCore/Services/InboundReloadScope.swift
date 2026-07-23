import LorvexDomain

/// A UI-surface group a store reloads as a unit. An inbound sync's applied
/// entity kinds map (via ``InboundReloadScope``) to the domains they can affect,
/// so a store reloads only those instead of its whole refresh fan-out.
///
/// Domains name the store's *primary read surfaces*, not its derived ones: a
/// store recomputes reminders / badge / widget / Spotlight from whichever of
/// these reloaded (task or habit rows drive reminders; today / focus / habits /
/// lists drive the widget snapshot). Each store interprets each case with its
/// own load calls — macOS and iOS share the vocabulary, not the implementation.
///
/// `CaseIterable` is load-bearing: every per-platform inbound-reload executor
/// (``AppStore/performSelectiveInboundReload(_:)`` on macOS,
/// `MobileStore.reloadInboundDomains(_:)` on iOS) dispatches these cases through a
/// `switch` with no `default`, so each executor MUST handle every case — either a
/// real reload of that domain's surface, or an explicit `break` documented with
/// why the platform has no store-published surface for it. Adding a case here is a
/// compile-time obligation on both executors, which is the point: a new domain
/// cannot be silently left unhandled on one platform.
public enum InboundReloadDomain: Sendable, Hashable, CaseIterable {
  /// The `TodaySnapshot` (top-priority open tasks + open-count summary).
  case today
  /// The task pools/workspace, the selected-task detail, and everything derived
  /// from the full task set (task Spotlight index, task reminders, badge).
  case tasks
  /// The list catalog and the selected list's detail.
  case lists
  /// The calendar timeline and the scheduled-task overlay.
  case calendar
  /// The current-focus plan and the saved focus schedule.
  case focus
  /// The daily review, its day evidence, the weekly review, and the review digest.
  case reviews
  /// The habit catalog and per-habit stats.
  case habits
  /// The AI-memory catalog and its detail/editor workspace.
  case memory
  /// The runtime diagnostics surface (including the AI changelog counters).
  case diagnostics
}

/// Maps the entity kinds an inbound sync applied to the ``InboundReloadDomain``s
/// whose surfaces read them, so a store reloads only the affected domains.
///
/// Conservative by construction: every kind maps to a *superset* of the surfaces
/// it can change, and any signal that cannot be cleanly bounded — an empty set,
/// or a kind (`preference`) with a diffuse blast radius across derived surfaces —
/// returns `nil`, telling the caller to fall back to a full reload. A selective
/// reload therefore never misses a surface a change should have updated; the only
/// cost of a mis-map would be an *extra* reload, never a stale one.
public enum InboundReloadScope {
  /// The domains to reload for `kinds`, or `nil` when the caller should fall back
  /// to a full reload (an empty set, or a diffuse kind). See the type docs for
  /// the conservative contract.
  public static func domains(for kinds: Set<EntityKind>) -> Set<InboundReloadDomain>? {
    guard !kinds.isEmpty else { return nil }
    var domains: Set<InboundReloadDomain> = []
    for kind in kinds {
      switch kind {
      case .task:
        // A task can move lists, (re)schedule, join/leave focus, and land on the
        // day's completion evidence, so its blast radius is every task-bearing
        // surface.
        domains.formUnion([.today, .tasks, .lists, .calendar, .focus, .reviews])
      case .taskReminder, .taskChecklistItem, .taskTag, .taskDependency:
        // Task-child / task-edge data is rendered by both the task workspace and
        // the selected-list detail. Reminder rescheduling is folded into `.tasks`.
        domains.formUnion([.today, .tasks, .lists])
      case .taskCalendarEventLink:
        domains.formUnion([.today, .tasks, .lists, .calendar])
      case .list:
        // A list rename/delete rehomes tasks, re-counts the sidebar, and changes
        // the list evidence rendered by daily/weekly review surfaces.
        domains.formUnion([.today, .tasks, .lists, .reviews])
      case .tag:
        // A tag rename/delete re-renders task rows and the tag filters, but review
        // evidence is list/task based and does not render the tag catalog.
        domains.formUnion([.today, .tasks, .lists])
      case .calendarEvent:
        // A base delete cascades task-event links, while scoped edits and
        // decision cleanup can also alter saved focus blocks. Reload every
        // surface that renders either relationship, not just the timeline.
        // Daily-review evidence also includes the selected day's event count.
        domains.formUnion([.calendar, .today, .tasks, .focus, .reviews])
      case .calendarSeriesCutover:
        // Boundaries change effective recurrence ownership, can invalidate
        // occurrence decisions, and therefore have the same rendered blast
        // radius as the segment events they partition.
        domains.formUnion([.calendar, .today, .tasks, .focus, .reviews])
      case .habit, .habitCompletion:
        // Review evidence joins habits and completions, so a peer completion,
        // rename, or delete changes both the habit cards and daily/weekly review.
        domains.formUnion([.habits, .reviews])
      case .habitReminderPolicy:
        domains.insert(.habits)
      case .dailyReview:
        domains.insert(.reviews)
      case .currentFocus, .focusSchedule:
        domains.insert(.focus)
      case .memory:
        domains.insert(.memory)
      case .aiChangelog:
        domains.insert(.diagnostics)
      case .entityRedirect:
        // The wire kind is structural; its payload's source type determines the
        // aggregate and dependent surfaces changed by the merge. The current
        // report carries only the envelope kind, so fail conservatively to a
        // full reload rather than under-refresh a target aggregate.
        return nil
      case .preference:
        // Preferences fan out into derived surfaces (badge enablement, notes in
        // notifications, calendar detail level, …) with no single home surface;
        // reload everything rather than risk missing one.
        return nil
      case .deviceState, .importSession:
        // Local-only kinds should never arrive inbound; if one does, fall back to
        // a full reload rather than silently ignore an unmodelled change.
        return nil
      }
    }
    return domains
  }

  /// Whether a selective reload of `domains` should re-plan task + habit reminders
  /// — the surfaces derived from the task and habit pools.
  public static func recomputesReminders(_ domains: Set<InboundReloadDomain>) -> Bool {
    !domains.isDisjoint(with: [.today, .tasks, .habits])
  }

  /// Whether a selective reload of `domains` should refresh the app-icon badge.
  /// The badge counts due/overdue *tasks* only (never habits), so a task-bearing
  /// today/tasks reload can move that count while a habits-only change cannot —
  /// narrower than ``recomputesReminders(_:)``, which also spans habits.
  public static func recomputesBadge(_ domains: Set<InboundReloadDomain>) -> Bool {
    !domains.isDisjoint(with: [.today, .tasks])
  }

  /// Whether a selective reload of `domains` should republish the widget snapshot,
  /// which reads today, current focus, habits, and lists.
  public static func republishesWidget(_ domains: Set<InboundReloadDomain>) -> Bool {
    !domains.isDisjoint(with: [.today, .tasks, .focus, .habits, .lists])
  }
}
