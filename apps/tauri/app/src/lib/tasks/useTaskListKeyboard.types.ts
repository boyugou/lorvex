/**
 * Reusable keyboard navigation for flat task lists.
 * Supports j/k (vim) and arrow keys for movement, Enter to select.
 */
export interface TaskListKeyboardActions {
  /** Called when 'x' is pressed — complete/toggle the focused task. */
  onComplete?: (taskId: string) => void;
  /** Called when 'c' is pressed — cancel the focused task. */
  onCancelTask?: (taskId: string) => void;
  /** Called when 's' is pressed — defer the focused task to tomorrow. */
  onDefer?: (taskId: string) => void;
  /** Called when 'S' (Shift+s) is pressed — defer the focused task to next Monday. */
  onDeferNextWeek?: (taskId: string) => void;
  /** Called when 'e' is pressed — start inline editing the focused task. */
  onEdit?: (taskId: string) => void;
  /** Called when 'd' is pressed — toggle due date to today for the focused task. */
  onSetDueToday?: (taskId: string) => void;
  /** Called when 'D' (Shift+d) is pressed — set due date to tomorrow for the focused task. */
  onSetDueTomorrow?: (taskId: string) => void;
  /** Called when '1'-'3' is pressed — set priority on the focused task. */
  onSetPriority?: (taskId: string, priority: 1 | 2 | 3) => void;
  /** Called when 'r' is pressed — toggle weekly recurrence on the focused task. */
  onToggleRecurrence?: (taskId: string) => void;
  /** Called when 'R' (Shift+r) is pressed — open recurrence picker for the focused task. */
  onSetRecurrence?: (taskId: string) => void;
  /** Called when 't' is pressed — open due date picker for the focused task. */
  onSetDueDate?: (taskId: string) => void;
  /** Called when 'w' is pressed — open duration picker for the focused task. */
  onSetDuration?: (taskId: string) => void;
  /** Called when 'm' is pressed — open the list picker to move the focused task. */
  onMoveToList?: (taskId: string) => void;
  /** Called when 'y' is pressed — duplicate the focused task. */
  onDuplicate?: (taskId: string) => void;
  /** Called when 'a' is pressed — promote a someday/deferred task to active (open). */
  onPromoteToActive?: (taskId: string) => void;
  /** Called when Alt+Up/Down is pressed — reorder the focused task in its list. */
  onReorder?: (taskId: string, direction: -1 | 1) => void;
  /**
   * Called when Ctrl+Arrow is pressed — move the focused task to an
   * adjacent column/quadrant in the view.
   *
   * `direction` keeps the original ±1 contract (-1 = up/left, +1 =
   * down/right). `axis` is optional and lets views decide which axes
   * they support: Eisenhower consumes both importance (horizontal) and
   * urgency (vertical), while one-axis surfaces such as Kanban can
   * reject the unsupported axis by returning false.
   */
  onMoveInView?: (taskId: string, direction: -1 | 1, axis?: 'horizontal' | 'vertical') => boolean | void;
  /** Called when Shift+F10 or '.' is pressed — open the context menu for the focused task. */
  onOpenContextMenu?: (taskId: string) => void;
  /** Called when Space is pressed — toggle selection state of the focused task. */
  onToggleSelected?: (taskId: string) => void;
  /** Called to enable selection mode (if not already active) before toggling selection. */
  setSelectionModeEnabled?: (enabled: boolean) => void;
  selectionModeActive?: boolean;
  /**
   * Called on Shift+ArrowUp / Shift+ArrowDown — extend the current
   * selection by one row in the given direction and return the row that
   * should receive keyboard focus next (null if movement is impossible).
   * The caller is the selection state owner and is responsible for
   * updating the selected Set; this hook only forwards the focused row
   * it gets back.
   */
  onExtendSelection?: (direction: 'up' | 'down', focusedId: string | null) => string | null;
  /**
   * Called on Ctrl/Cmd+A while a list is focused — select every visible
   * row. Independent from the visual selection-mode toggle, so a user
   * who prefers modifier-driven selection never needs to open the
   * checkbox UI.
   */
  onSelectAll?: () => void;
  /**
   * Called on Escape when selection is non-empty — clear selection +
   * anchor. Runs before the selection-mode Escape handler so the user
   * can first "Esc to clear" and then "Esc to exit" in explicit
   * checkbox mode.
   */
  onClearSelection?: () => void;
  /** True when `selectedIds` is non-empty; drives the Escape branch above. */
  hasSelection?: boolean;
}

export interface TaskListKeyboardOptions {
  /** Ordered list of task IDs currently visible. */
  taskIds: string[];
  /** Called when Enter is pressed on the focused task. */
  onSelect?: ((taskId: string) => void) | undefined;
  /** Optional action shortcuts for the focused task. */
  actions?: TaskListKeyboardActions;
  /** Disables all keyboard handling when true. */
  disabled?: boolean;
}

export interface TaskListKeyboardState {
  /** Currently focused task ID (null if no tasks). */
  focusedId: string | null;
  /** Whether a given task ID is the keyboard-focused one. */
  isFocused: (taskId: string) => boolean;
  /** Reset focus to first item. */
  resetFocus: () => void;
  /**
   * Imperatively set the focused task id. Used by surfaces
   * that want to layer secondary keyboard bindings (e.g. cluster-
   * jump shift+j/k in the dependency graph) on top of the default
   * flat j/k roving focus. Callers are responsible for passing an id
   * that actually exists in the current `taskIds` set.
   */
  focusTaskId: (taskId: string) => void;
  /** True when keyboard hint bar should be shown (first navigation, auto-dismisses). */
  showKeyboardHints: boolean;
}
