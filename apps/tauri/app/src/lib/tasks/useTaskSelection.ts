import { useCallback, useEffect, useRef, useState } from 'react';

import { toast } from '../notifications/toast';

export type BulkAction = 'complete' | 'cancel' | 'move' | 'defer' | 'focus' | null;

/**
 * Shape of the modifier-aware click handler. The second argument accepts
 * either a React synthetic mouse event or a native MouseEvent so callers
 * can forward whichever they have on hand.
 */
type ModifierClickEvent = { shiftKey: boolean; metaKey: boolean; ctrlKey: boolean };

/**
 * Pure range-selection helper: returns the selectable IDs in `orderedIds`
 * that lie between `anchorId` and `targetId` (inclusive), using the display
 * order the caller passes in. If either id is missing the helper falls
 * back to `{targetId}` when the target is selectable.
 *
 * `selectableIds` lets callers pass a wider keyboard-navigation order while
 * keeping selection state constrained to rows the bulk-action surface can act
 * on.
 *
 * Split out as a bare function so tests can exercise it without a React
 * environment.
 */
export function computeRangeSelection(
  orderedIds: readonly string[],
  anchorId: string | null,
  targetId: string,
  selectableIds?: ReadonlySet<string>,
): Set<string> {
  const targetIdx = orderedIds.indexOf(targetId);
  if (targetIdx < 0) return selectableIds == null || selectableIds.has(targetId)
    ? new Set([targetId])
    : new Set();
  const anchorIdx = anchorId == null ? -1 : orderedIds.indexOf(anchorId);
  if (anchorIdx < 0) return selectableIds == null || selectableIds.has(targetId)
    ? new Set([targetId])
    : new Set();
  const lo = Math.min(anchorIdx, targetIdx);
  const hi = Math.max(anchorIdx, targetIdx);
  const out = new Set<string>();
  for (let i = lo; i <= hi; i += 1) {
    const id = orderedIds[i];
    if (id != null && (selectableIds == null || selectableIds.has(id))) {
      out.add(id);
    }
  }
  return out;
}

/**
 * Pure reducer for a modifier-aware click on row `id`. Mirrors the
 * semantics used by Finder / Files / most native list UIs:
 *   - plain click           → replace selection with `{id}`, anchor = id
 *   - ctrl/cmd click        → toggle `id` in/out, anchor unchanged
 *   - shift click           → range from anchor → id (anchor defaults to
 *                              the currently-focused row or `id` itself),
 *                              anchor unchanged
 */
export function reduceModifierClick(
  orderedIds: readonly string[],
  previous: Set<string>,
  anchorId: string | null,
  id: string,
  event: ModifierClickEvent,
  currentFocusedId: string | null,
  selectableIds?: ReadonlySet<string>,
): { next: Set<string>; nextAnchor: string | null } {
  if (event.shiftKey) {
    const effectiveAnchor = anchorId ?? currentFocusedId ?? id;
    const next = computeRangeSelection(orderedIds, effectiveAnchor, id, selectableIds);
    return { next, nextAnchor: anchorId ?? effectiveAnchor };
  }
  if (event.metaKey || event.ctrlKey) {
    const next = new Set(previous);
    if (next.has(id)) {
      next.delete(id);
    } else if (selectableIds == null || selectableIds.has(id)) {
      next.add(id);
    }
    return { next, nextAnchor: anchorId };
  }
  const next = selectableIds == null || selectableIds.has(id)
    ? new Set([id])
    : new Set<string>();
  return { next, nextAnchor: id };
}

/**
 * Pure reducer for shift+arrow range extension. The caller passes in the
 * row the user is currently focused on; the helper extends selection by
 * one row in `direction` relative to the anchor (establishing the anchor
 * from the focused row if none exists yet).
 *
 * Returns `null` when no movement is possible (empty list, focused row
 * missing, or already at the boundary).
 */
export function reduceKeyboardExtend(
  orderedIds: readonly string[],
  anchorId: string | null,
  focusedId: string | null,
  direction: 'up' | 'down',
  selectableIds?: ReadonlySet<string>,
): { next: Set<string>; nextAnchor: string; nextFocusedId: string } | null {
  if (orderedIds.length === 0 || focusedId == null) return null;
  const focusedIdx = orderedIds.indexOf(focusedId);
  if (focusedIdx < 0) return null;
  const effectiveAnchor = anchorId ?? focusedId;
  const step = direction === 'up' ? -1 : 1;
  const targetIdx = focusedIdx + step;
  if (targetIdx < 0 || targetIdx >= orderedIds.length) return null;
  const targetId = orderedIds[targetIdx];
  if (targetId == null) return null;
  const next = computeRangeSelection(orderedIds, effectiveAnchor, targetId, selectableIds);
  return { next, nextAnchor: effectiveAnchor, nextFocusedId: targetId };
}

export function reconcileSelectionVisibility(
  previous: Set<string>,
  visibleTaskIds: ReadonlySet<string>,
  anchorId: string | null,
  selectionMode: boolean,
): {
  nextSelectedIds: Set<string>;
  nextAnchorId: string | null;
  nextSelectionMode: boolean;
} {
  if (visibleTaskIds.size === 0) {
    return {
      nextSelectedIds: new Set(),
      nextAnchorId: null,
      nextSelectionMode: false,
    };
  }

  const nextSelectedIds = new Set<string>();
  for (const id of previous) {
    if (visibleTaskIds.has(id)) nextSelectedIds.add(id);
  }

  return {
    nextSelectedIds,
    nextAnchorId: anchorId != null && visibleTaskIds.has(anchorId) ? anchorId : null,
    nextSelectionMode: selectionMode,
  };
}

/**
 * Generic task multi-selection state.
 *
 * Selection semantics:
 *   - `toggleTaskSelected(id)` — checkbox-style toggle, used by the
 *     explicit selection-mode checkboxes.
 *   - `handleClickWithModifiers(id, event, focusedId?)` — modifier-aware
 *     click that matches native list UIs (plain / ctrl+click / shift+click).
 *   - `handleKeyboardExtend(direction, orderedIds, focusedId)` — shift+arrow
 *     range extension.
 *   - `clearSelection()` — Escape handler, drops selection + anchor.
 *
 * Pruning: when `visibleTaskIds` changes, selected IDs not in the new
 * set are discarded. The anchor is likewise cleared when it points at a
 * row that is no longer visible.
 */
interface UseTaskSelectionOptions {
  /** when a plain click collapses a multi-selection
   *  (>1 row → 1 row), surface a localized toast giving the user a one-
   *  click "Restore" affordance. The hook stays UI-string-free; views
   *  pass their own translated messages so the call is fully i18n-safe. */
  onSelectionCollapsedMessage?: (previousCount: number) => string;
  onSelectionCollapsedUndoLabel?: () => string;
}

export function useTaskSelection(
  visibleTaskIds: Set<string>,
  bulkAction: BulkAction,
  options: UseTaskSelectionOptions = {},
) {
  const { onSelectionCollapsedMessage, onSelectionCollapsedUndoLabel } = options;
  const [selectionMode, setSelectionMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [anchorId, setAnchorId] = useState<string | null>(null);
  const anchorRef = useRef<string | null>(null);
  anchorRef.current = anchorId;
  const selectedIdsRef = useRef<Set<string>>(selectedIds);
  selectedIdsRef.current = selectedIds;
  const selectionModeRef = useRef(selectionMode);
  selectionModeRef.current = selectionMode;

  useEffect(() => {
    setSelectedIds((previous) => {
      const reconciled = reconcileSelectionVisibility(
        previous,
        visibleTaskIds,
        anchorRef.current,
        selectionModeRef.current,
      );
      if (reconciled.nextAnchorId !== anchorRef.current) {
        setAnchorId(reconciled.nextAnchorId);
      }
      if (reconciled.nextSelectionMode !== selectionModeRef.current) {
        setSelectionMode(reconciled.nextSelectionMode);
      }
      const unchangedSelection = reconciled.nextSelectedIds.size === previous.size
        && [...previous].every((id) => reconciled.nextSelectedIds.has(id));
      return unchangedSelection ? previous : reconciled.nextSelectedIds;
    });
  }, [visibleTaskIds]);

  const setSelectionModeEnabled = (enabled: boolean) => {
    setSelectionMode(enabled);
    if (!enabled) {
      setSelectedIds(new Set());
      setAnchorId(null);
    }
  };

  const toggleTaskSelected = (id: string) => {
    if (bulkAction) return;
    setSelectedIds((previous) => {
      const next = new Set(previous);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
    // Treat the explicit checkbox toggle as establishing an anchor for
    // subsequent shift-click range operations.
    setAnchorId(id);
  };

  const selectAll = useCallback(() => {
    if (bulkAction) return;
    setSelectedIds(new Set(visibleTaskIds));
  }, [bulkAction, visibleTaskIds]);

  //: toggle every visible row — selected
  // rows become unselected and vice versa. Faster than "select all
  // then click out N rows" when the user wants the complement of a
  // small explicit set. Anchor stays where it was so a subsequent
  // shift+click still extends from the last explicit pick.
  const invertSelection = useCallback(() => {
    if (bulkAction) return;
    setSelectedIds((previous) => {
      const next = new Set<string>();
      for (const id of visibleTaskIds) {
        if (!previous.has(id)) next.add(id);
      }
      return next;
    });
  }, [bulkAction, visibleTaskIds]);

  const clearSelection = useCallback(() => {
    setSelectedIds(new Set());
    setAnchorId(null);
  }, []);

  /**
   * Modifier-aware row click.
   *
   * `orderedIds` is the list of visible task IDs in display order; used
   * only to resolve shift-click ranges. Callers that render a flat list
   * can pass the same array they feed to `useTaskListKeyboard`.
   *
   * `focusedId` is the keyboard-focused row, used as a fallback anchor
   * for a shift-click made before any anchor has been established.
   */
  const handleClickWithModifiers = useCallback(
    (
      id: string,
      event: ModifierClickEvent,
      orderedIds: readonly string[],
      focusedId: string | null = null,
    ) => {
      if (bulkAction) return;
      // when a plain click would silently collapse a
      // multi-selection (>1 row → 1 row), the user has no feedback that
      // their previous selection just disappeared. Snapshot the prior
      // selection + anchor BEFORE the reducer runs, then if the click
      // is plain (no modifier) and the prior set held >1 ids, surface
      // an actionable info toast that restores the multi-selection in
      // one click. Modifier clicks (toggle, range) intentionally
      // preserve / extend selection so they don't need this affordance.
      const isPlainClick = !event.shiftKey && !event.metaKey && !event.ctrlKey;
      const previousSelection = isPlainClick && selectedIdsRef.current.size > 1
        ? selectedIdsRef.current
        : null;
      const previousAnchor = anchorRef.current;
      setSelectedIds((previous) => {
        const { next, nextAnchor } = reduceModifierClick(
          orderedIds,
          previous,
          anchorRef.current,
          id,
          event,
          focusedId,
          visibleTaskIds,
        );
        if (nextAnchor !== anchorRef.current) {
          setAnchorId(nextAnchor);
        }
        return next;
      });
      if (previousSelection !== null) {
        const restored = new Set(previousSelection);
        const message = onSelectionCollapsedMessage
          ? onSelectionCollapsedMessage(previousSelection.size)
          : `Selection cleared (${previousSelection.size} → 1)`;
        const undoLabel = onSelectionCollapsedUndoLabel?.() ?? 'Restore';
        toast.info(
          message,
          {
            label: undoLabel,
            onClick: () => {
              setSelectedIds(restored);
              setAnchorId(previousAnchor);
            },
          },
          `selection-collapsed:${id}`,
        );
      }
    },
    [bulkAction, onSelectionCollapsedMessage, onSelectionCollapsedUndoLabel, visibleTaskIds],
  );

  /**
   * Shift+arrow keyboard range extension. Returns the new focused row so
   * the caller can forward it to the list-keyboard hook.
   */
  const handleKeyboardExtend = useCallback(
    (
      direction: 'up' | 'down',
      orderedIds: readonly string[],
      focusedId: string | null,
    ): string | null => {
      if (bulkAction) return null;
      const result = reduceKeyboardExtend(
        orderedIds,
        anchorRef.current,
        focusedId,
        direction,
        visibleTaskIds,
      );
      if (!result) return null;
      setSelectedIds(result.next);
      if (result.nextAnchor !== anchorRef.current) {
        setAnchorId(result.nextAnchor);
      }
      return result.nextFocusedId;
    },
    [bulkAction, visibleTaskIds],
  );

  return {
    anchorId,
    clearSelection,
    handleClickWithModifiers,
    handleKeyboardExtend,
    invertSelection,
    selectAll,
    selectedIds,
    selectionMode,
    setSelectedIds,
    setSelectionModeEnabled,
    toggleTaskSelected,
  };
}
