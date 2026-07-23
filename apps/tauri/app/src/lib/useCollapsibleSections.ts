/**
 * Shared hook for managing collapsible section state with localStorage persistence.
 * Extracts the common pattern used by AllTasks, Upcoming, and Someday controllers.
 */

import { useCallback, useRef, useState } from 'react';
import { getUIState, setUIState } from './storage/uiState';
import {
  collapseAllSections,
  expandAllSections,
  isCollapsedSectionKeyArray,
  readCollapsedSectionSet,
  serializeCollapsedSectionSet,
  toggleCollapsedSection,
} from './collapsibleSections.logic';

export function useCollapsibleSections(storageKey: string): {
  collapsed: Set<string>;
  toggle: (key: string) => void;
  collapseAll: (keys: string[]) => void;
  expandAll: () => void;
} {
  const [collapsed, setCollapsed] = useState<Set<string>>(() => {
    // Validate the stored shape at runtime — a malformed blob (from a
    // pre-migration version, hand-edited devtools value, or crash
    // mid-write) must not propagate to `new Set()`, which would happily
    // build a Set<unknown> and silently poison every downstream
    // comparison. Invalid → empty set, matching the fresh-install
    // behavior.
    const stored = getUIState<string[]>(storageKey, [], isCollapsedSectionKeyArray);
    return readCollapsedSectionSet(stored);
  });
  const collapsedRef = useRef(collapsed);

  const commit = useCallback((next: Set<string>) => {
    collapsedRef.current = next;
    setCollapsed(next);
    setUIState(storageKey, serializeCollapsedSectionSet(next));
  }, [storageKey]);

  const toggle = useCallback((key: string) => {
    commit(toggleCollapsedSection(collapsedRef.current, key));
  }, [commit]);

  const collapseAll = useCallback((keys: string[]) => {
    commit(collapseAllSections(keys));
  }, [commit]);

  const expandAll = useCallback(() => {
    commit(expandAllSections());
  }, [commit]);

  return { collapsed, toggle, collapseAll, expandAll };
}
