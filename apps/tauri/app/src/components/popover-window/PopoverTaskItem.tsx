import { useCallback, useEffect, useId, useLayoutEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import type { Task } from '@/lib/ipc/tasks/models';
import { useI18n } from '@/lib/i18n';
import {
  installPopoverTaskDeferMenuDismissRuntime,
  resolvePopoverTaskDeferMenuPosition,
} from './PopoverTaskItem.runtime';

interface PopoverTaskItemProps {
  task: Task;
  completing: boolean;
  deferring: boolean;
  expanded: boolean;
  onComplete: (taskId: string) => void;
  onOpenTask: (taskId: string) => void;
  onDefer: (taskId: string) => void;
  onDeferNextWeek: (taskId: string) => void;
  onToggleExpand: () => void;
  t: ReturnType<typeof useI18n>['t'];
}

function CheckCircle({ completing }: { completing: boolean }) {
  return (
    <span
      className={`shrink-0 w-[18px] h-[18px] rounded-full border-[1.5px] flex items-center justify-center transition-colors ${
        completing
          ? 'border-success/60 bg-[var(--success-tint-md)]'
          : 'border-text-muted/30 hover:border-success/50 hover:bg-[var(--success-tint-xs)]'
      }`}
    >
      {completing && (
        <svg width="10" height="10" viewBox="0 0 10 10" fill="none" className="text-success">
          <path d="M2 5.5L4 7.5L8 3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      )}
    </span>
  );
}

/** Truncate text to a given number of lines, returning the truncated string. */
function truncateLines(text: string, maxLines: number): string {
  const lines = text.split('\n').slice(0, maxLines);
  const result = lines.join('\n');
  if (text.split('\n').length > maxLines) {
    // typographic ellipsis (U+2026) instead of three
    // ASCII dots. Renders as a single glyph at the typographic width
    // a designer would expect, and copies cleanly into search/copy
    // surfaces that special-case '…'.
    return result + '…';
  }
  return result;
}

function ExpandedDetail({
  task,
  busy,
  onComplete,
  onDefer,
  onDeferNextWeek,
  onOpenTask,
  t,
}: {
  task: Task;
  busy: boolean;
  onComplete: (taskId: string) => void;
  onDefer: (taskId: string) => void;
  onDeferNextWeek: (taskId: string) => void;
  onOpenTask: (taskId: string) => void;
  t: PopoverTaskItemProps['t'];
}) {
  const [deferMenuOpen, setDeferMenuOpen] = useState(false);
  const deferBtnRef = useRef<HTMLButtonElement>(null);
  const deferMenuRef = useRef<HTMLDivElement>(null);
  const [deferMenuPos, setDeferMenuPos] = useState<{ left: number; top: number } | null>(null);
  // a hard-coded `popover-task-defer-menu` id was
  // shared by every `PopoverTaskItem` in the popover list. Two rows
  // mid-animation overlap (one closing while another opens) put two
  // portals with identical ids in the DOM at the same time —
  // `aria-controls` on the trigger then resolves to whichever the
  // AT tree picks first, so screen readers can read the wrong row's
  // menu items. `useId()` mints a per-instance stable id so each
  // trigger/portal pair is referentially distinct.
  const deferMenuId = useId();

  // Compute fixed position for the defer dropdown portal
  useLayoutEffect(() => {
    if (!deferMenuOpen || !deferBtnRef.current) {
      setDeferMenuPos(null);
      return;
    }
    setDeferMenuPos(resolvePopoverTaskDeferMenuPosition(
      deferBtnRef.current.getBoundingClientRect(),
      window.innerHeight,
    ));
  }, [deferMenuOpen]);

  // Close defer menu on click outside or Escape
  useEffect(() => {
    if (!deferMenuOpen) return;
    return installPopoverTaskDeferMenuDismissRuntime({
      addWindowMouseDownListener: typeof window === 'undefined'
        ? null
        : (listener) => {
            window.addEventListener('mousedown', listener, true);
            return () => window.removeEventListener('mousedown', listener, true);
          },
      addWindowKeydownListener: typeof window === 'undefined'
        ? null
        : (listener) => {
            window.addEventListener('keydown', listener, true);
            return () => window.removeEventListener('keydown', listener, true);
          },
      isInsideMenuOrTrigger: (target) => {
        if (!(target instanceof Node)) return false;
        return Boolean(
          deferMenuRef.current?.contains(target) || deferBtnRef.current?.contains(target),
        );
      },
      onDismiss: () => setDeferMenuOpen(false),
    });
  }, [deferMenuOpen]);

  const closeDeferAndAct = useCallback((action: () => void) => {
    setDeferMenuOpen(false);
    action();
  }, []);

  // When the defer menu opens, move focus to the
  // first menuitem so keyboard users can immediately ArrowDown/Enter
  // without an extra Tab. Closing returns focus to the trigger
  // (handled via ref click invariant — the dismiss runtime closes
  // the menu and the document already holds the trigger).
  const firstItemRef = useRef<HTMLButtonElement | null>(null);
  const secondItemRef = useRef<HTMLButtonElement | null>(null);
  // Mirror FilterDropdown's roving-tabindex contract.
  // The focused menuitem is the only one with `tabIndex=0`; the rest
  // get `-1` so Tab exits the menu instead of cycling within it.
  const [focusedDeferIndex, setFocusedDeferIndex] = useState(0);
  // Track the previous open state so the close-side focus-restore only
  // fires on a real `true → false` transition. Without this guard the
  // first render of `ExpandedDetail` (when the user expanded a task
  // without ever opening the defer menu) would land in the else-branch
  // and yank focus onto the Defer button — a visible focus-ring jump
  // that breaks keyboard flow on every expand.
  const wasMenuOpenRef = useRef(false);
  useEffect(() => {
    if (deferMenuOpen) {
      // Reset to the first item every time the menu re-opens — keyboard
      // users always land at the top of the list.
      setFocusedDeferIndex(0);
      // Defer to next tick so the portal has mounted.
      const handle = window.requestAnimationFrame(() => {
        firstItemRef.current?.focus();
      });
      wasMenuOpenRef.current = true;
      return () => window.cancelAnimationFrame(handle);
    }
    // Return focus to the trigger only when the menu just closed (open
    // → closed transition); skip the initial render where the menu was
    // never open in the first place.
    if (wasMenuOpenRef.current) {
      wasMenuOpenRef.current = false;
      deferBtnRef.current?.focus();
    }
    return undefined;
  }, [deferMenuOpen]);

  // Full WAI-ARIA menu key contract —
  // Arrow keys move the roving tabIndex, Home/End jump to ends, and
  // Escape closes explicitly (the dismiss runtime is the second line
  // of defence; keyDown on the menu element itself is the portable
  // path that runs even when the runtime is suspended for a transition).
  const handleMenuKeyDown = useCallback((event: React.KeyboardEvent) => {
    const items = [firstItemRef.current, secondItemRef.current].filter(
      (el): el is HTMLButtonElement => el !== null,
    );
    if (items.length === 0) return;
    if (event.key === 'Escape') {
      event.stopPropagation();
      setDeferMenuOpen(false);
      return;
    }
    const activeIdx = items.indexOf(document.activeElement as HTMLButtonElement);
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      const nextIdx = (activeIdx + 1 + items.length) % items.length;
      setFocusedDeferIndex(nextIdx);
      items[nextIdx]?.focus();
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      const nextIdx = (activeIdx - 1 + items.length) % items.length;
      setFocusedDeferIndex(nextIdx);
      items[nextIdx]?.focus();
    } else if (event.key === 'Home') {
      event.preventDefault();
      setFocusedDeferIndex(0);
      items[0]?.focus();
    } else if (event.key === 'End') {
      event.preventDefault();
      const lastIdx = items.length - 1;
      setFocusedDeferIndex(lastIdx);
      items[lastIdx]?.focus();
    }
  }, []);

  const bodyPreview = task.body?.trim()
    ? truncateLines(task.body.trim(), 3)
    : null;

  const aiNotesPreview = task.ai_notes?.trim()
    ? truncateLines(task.ai_notes.trim(), 2)
    : null;

  return (
    <div className="ms-[26px] mt-1 rounded-r-control bg-surface-2/40 px-2.5 py-2 animate-[fade-in_0.12s_ease-out]">
      {/* Body / notes preview */}
      <div className="mb-2">
        {bodyPreview ? (
          <p className="text-xs leading-relaxed text-text-secondary whitespace-pre-line line-clamp-3">
            {bodyPreview}
          </p>
        ) : (
          <p className="text-xs leading-relaxed text-text-muted/50 italic">
            {t('popover.noNotes')}
          </p>
        )}
      </div>

      {/* AI notes preview */}
      {aiNotesPreview && (
        <div className="mb-2 rounded-r-control bg-[var(--accent-tint-xxs)] px-2 py-1">
          <p className="text-3xs font-medium text-accent mb-0.5">
            {t('popover.aiNotes')}
          </p>
          <p className="text-2xs leading-relaxed text-text-muted whitespace-pre-line line-clamp-2">
            {aiNotesPreview}
          </p>
        </div>
      )}

      {/* Action buttons row */}
      <div className="flex items-center gap-1.5">
        {/* Done button */}
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); onComplete(task.id); }}
          disabled={busy}
          className="flex items-center gap-1 rounded-r-control chip-success chip-success-interactive px-2 py-1 text-2xs font-medium active:scale-95 transition-[color,background-color,transform] disabled:opacity-50 disabled:cursor-default focus-ring-soft-success"
        >
          <span>✓</span>
          {t('common.done')}
        </button>

        {/* Defer dropdown button */}
        <div className="relative">
          {/* expose the menu-trigger relationship to
              assistive tech. aria-haspopup="menu" tells SR that the
              button opens a menu, aria-expanded tracks the open state,
              and aria-controls ties the button to the portal-rendered
              list (which has role="menu" + matching id below). */}
          <button
            ref={deferBtnRef}
            type="button"
            onClick={(e) => { e.stopPropagation(); setDeferMenuOpen(!deferMenuOpen); }}
            disabled={busy}
            aria-haspopup="menu"
            aria-expanded={deferMenuOpen}
            // the menu element only mounts in a
            // portal while `deferMenuOpen` is true, so `aria-controls`
            // would point at an id that doesn't exist in the DOM
            // when the menu is collapsed. Gate the attribute so the
            // relationship is only asserted while the controlled
            // element actually exists.
            aria-controls={deferMenuOpen ? deferMenuId : undefined}
            className="flex items-center gap-0.5 rounded-r-control chip-warning chip-warning-interactive px-2 py-1 text-2xs font-medium active:scale-95 transition-[color,background-color,transform] disabled:opacity-50 disabled:cursor-default focus-ring-soft-warning"
          >
            {t('popover.deferMenu')}
            <svg width="10" height="10" viewBox="0 0 10 10" fill="none" className={`transition-transform ${deferMenuOpen ? 'rotate-180' : ''}`} aria-hidden="true">
              <path d="M2.5 4L5 6.5L7.5 4" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </button>
          {deferMenuOpen && deferMenuPos && createPortal(
            <div
              ref={deferMenuRef}
              id={deferMenuId}
              role="menu"
              aria-label={t('popover.deferMenu')}
              aria-orientation="vertical"
              onKeyDown={handleMenuKeyDown}
              // tokenize the popover elevation to --shadow-popover so
              // the defer menu matches every other floating menu's
              // depth instead of drifting at a raw Tailwind value.
              className="fixed z-[var(--z-popover)] min-w-[var(--menu-min-w-sm)] rounded-r-card border border-card bg-surface-1 shadow-[var(--shadow-popover)] py-0.5 animate-[fade-in_0.1s_ease-out]"
              style={{ left: deferMenuPos.left, top: deferMenuPos.top }}
            >
              <button
                ref={firstItemRef}
                type="button"
                role="menuitem"
                tabIndex={focusedDeferIndex === 0 ? 0 : -1}
                onClick={(e) => { e.stopPropagation(); closeDeferAndAct(() => onDefer(task.id)); }}
                onFocus={() => setFocusedDeferIndex(0)}
                disabled={busy}
                className="w-full text-start px-2.5 py-1 text-2xs text-text-secondary hover:bg-surface-2/80 transition-colors disabled:opacity-50 focus-ring-soft"
              >
                {t('popover.deferTomorrowShort')}
              </button>
              <button
                ref={secondItemRef}
                type="button"
                role="menuitem"
                tabIndex={focusedDeferIndex === 1 ? 0 : -1}
                onClick={(e) => { e.stopPropagation(); closeDeferAndAct(() => onDeferNextWeek(task.id)); }}
                onFocus={() => setFocusedDeferIndex(1)}
                disabled={busy}
                className="w-full text-start px-2.5 py-1 text-2xs text-text-secondary hover:bg-surface-2/80 transition-colors disabled:opacity-50 focus-ring-soft"
              >
                {t('popover.deferNextWeek')}
              </button>
            </div>,
            document.body,
          )}
        </div>

        {/* Spacer */}
        <div className="flex-1" />

        {/* Open in App button */}
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); onOpenTask(task.id); }}
          className="flex items-center gap-0.5 rounded-r-control px-2 py-1 text-2xs text-text-muted/70 hover:text-text-secondary hover:bg-surface-2/60 active:scale-95 transition-[color,background-color,transform] focus-ring-soft"
        >
          {t('popover.openInApp')}
          <span className="text-3xs">→</span>
        </button>
      </div>
    </div>
  );
}

export function PopoverTaskItem({
  task,
  completing,
  deferring,
  expanded,
  onComplete,
  onOpenTask,
  onDefer,
  onDeferNextWeek,
  onToggleExpand,
  t,
}: PopoverTaskItemProps) {
  const { formatNumber } = useI18n();
  const busy = completing || deferring;

  return (
    <li className="group rounded-r-card px-1.5 py-[5px] hover:bg-surface-2/60 transition-colors">
      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={() => { onComplete(task.id); }}
          disabled={busy}
          className="shrink-0 focus-ring-soft rounded-full disabled:cursor-default"
          aria-label={t('common.done')}
        >
          <CheckCircle completing={completing} />
        </button>
        <button
          type="button"
          onClick={onToggleExpand}
          className={`flex-1 min-w-0 text-start flex items-center gap-1.5 focus-ring-soft rounded-r-control ${
            busy ? 'text-text-muted line-through' : ''
          }`}
          title={task.title}
        >
          {task.priority != null && task.priority <= 2 && (
            <span className="shrink-0 text-2xs text-danger">!!</span>
          )}
          <span className={`text-13 leading-snug truncate ${busy ? '' : 'text-text-primary'}`}>
            {task.title}
          </span>
          {task.due_time && (
            <span className="shrink-0 text-2xs text-text-muted tabular-nums">
              {task.due_time}
            </span>
          )}
          {task.estimated_minutes != null && task.estimated_minutes > 0 && (
            <span className="shrink-0 text-2xs text-text-muted/60 tabular-nums">
              {formatNumber(task.estimated_minutes)}{t('common.min')}
            </span>
          )}
          {/* Expand indicator */}
          <svg
            width="12"
            height="12"
            viewBox="0 0 12 12"
            fill="none"
            className={`shrink-0 ms-auto text-text-muted/40 transition-transform ${expanded ? 'rotate-180 opacity-100' : 'reveal-on-hover'}`}
          >
            <path d="M3 4.5L6 7.5L9 4.5" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </button>
      </div>

      {/* Expanded inline detail */}
      {expanded && (
        <ExpandedDetail
          task={task}
          busy={busy}
          onComplete={onComplete}
          onDefer={onDefer}
          onDeferNextWeek={onDeferNextWeek}
          onOpenTask={onOpenTask}
          t={t}
        />
      )}
    </li>
  );
}
