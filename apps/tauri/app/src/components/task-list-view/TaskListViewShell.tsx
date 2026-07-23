import type { ReactNode } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import type { TranslationKey } from '@/lib/i18n';
import { useI18n } from '@/lib/i18n';
import { formatPageTitle } from '@/lib/pageTitle';
import { PickerOverlays } from '../ui/PickerOverlays';
import { ViewToolbar, type ViewToolbarProps } from '../ui/ViewToolbar';

/**
 * Action bundle shape consumed by `<PickerOverlays>`. Every list-shaped
 * view's `useTaskListActions` return value already exposes these eight
 * fields (four picker-task-ids paired with their close callbacks), so
 * the shell takes them as a single bundle to spare each caller from
 * re-listing the same eight props at the bottom of its render tree.
 */
interface TaskListPickerActions {
  movePickerTaskId: string | null;
  closeMovePickerAction: () => void;
  recurrencePickerTaskId: string | null;
  closeRecurrencePickerAction: () => void;
  dueDatePickerTaskId: string | null;
  closeDueDatePickerAction: () => void;
  durationPickerTaskId: string | null;
  closeDurationPickerAction: () => void;
}

interface TaskListViewShellProps<
  SortKey extends string = string,
  GroupKey extends string = string,
> {
  /**
   * Translation key for the document title (rendered through React
   * 19's native `<title>`). Routed through `formatPageTitle` so the
   * "Lorvex · " prefix is consistent with the rest of the app.
   */
  pageTitleKey: TranslationKey;
  /**
   * Header inner content. The four views diverge significantly in
   * what their headers contain (small label vs heading-only, copy
   * buttons, view-mode toggles, threshold paragraphs, drag hints), so
   * the shell owns only the outer `<header>` wrapper + padding and
   * lets each view supply the rest.
   */
  headerContent: ReactNode;
  /** Toolbar slot configuration; rendered between the header and body. */
  toolbar: ViewToolbarProps<SortKey, GroupKey>;
  /**
   * Optional bulk-action bar — rendered immediately below the toolbar,
   * still inside the sticky header chrome. Views that don't expose
   * bulk selection (Eisenhower, Kanban) leave this undefined.
   */
  bulkBar?: ReactNode;
  /**
   * Optional stale-data banner. Rendered between the header and body
   * with the canonical `px-4 sm:px-8 pt-2` padding so cached-data
   * views (Upcoming, Eisenhower, Kanban) all share the same vertical
   * rhythm.
   */
  staleBanner?: ReactNode;
  /** Main scrolling body. Each view owns its own scroll container. */
  body: ReactNode;
  /** Tasks list passed to `<PickerOverlays>` for the picker panes. */
  pickerTasks: Task[];
  /** Picker open state + close callbacks. */
  pickerActions: TaskListPickerActions;
  /**
   * Override for the outer container className. Defaults to
   * `h-full flex flex-col overflow-hidden`. Kanban needs a different
   * overflow chain on desktop so it accepts an override.
   */
  containerClassName?: string;
  /**
   * Override for the `<header>` className. Defaults to the canonical
   * `px-4 sm:px-8 pt-1.5 pb-5 shrink-0` shared by AllTasks, Upcoming,
   * and Eisenhower. Kanban swaps padding by runtime profile (mobile
   * vs desktop) rather than CSS breakpoint, so it supplies its own
   * value here.
   */
  headerClassName?: string;
}

/**
 * Shared shell for the four task-list-shaped views (AllTasks, Upcoming,
 * Eisenhower, Kanban). Owns the universal chrome:
 *
 *   - outer flex container
 *   - `<title>` element (page title with locale-aware prefix)
 *   - `<header>` wrapper with the canonical `px-4 sm:px-8 pt-1.5 pb-5`
 *     responsive padding shared by every entity-list view
 *   - `<ViewToolbar>` with view-supplied slot configuration
 *   - optional `<BulkActionBar>` slot
 *   - optional stale-data banner slot
 *   - the view-specific body
 *   - `<PickerOverlays>` at the bottom
 *
 * Pre-refactor each view rolled this same skeleton from scratch, with
 * minor and accidental drift on padding, the title element, and the
 * picker overlay prop list. The shell freezes the contract so any
 * future polish (e.g. responsive padding tweaks, header alignment
 * fixes) lands on every view in one place.
 */
export function TaskListViewShell<
  SortKey extends string = string,
  GroupKey extends string = string,
>({
  pageTitleKey,
  headerContent,
  toolbar,
  bulkBar,
  staleBanner,
  body,
  pickerTasks,
  pickerActions,
  containerClassName = 'h-full flex flex-col overflow-hidden',
  headerClassName = 'px-4 sm:px-8 pt-1.5 pb-5 shrink-0',
}: TaskListViewShellProps<SortKey, GroupKey>) {
  const { t } = useI18n();
  return (
    <div className={containerClassName}>
      <title>{formatPageTitle(t(pageTitleKey))}</title>
      {/* Tablet-portrait responsive padding — see TodayHeader. */}
      <header className={headerClassName}>
        {headerContent}
        <ViewToolbar<SortKey, GroupKey> {...toolbar} />
        {bulkBar}
      </header>
      {staleBanner}
      {body}
      <PickerOverlays tasks={pickerTasks} {...pickerActions} />
    </div>
  );
}
