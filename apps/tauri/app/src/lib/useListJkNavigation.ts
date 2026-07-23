import { useEffect, useRef } from 'react';

/**
 * Lightweight j/k list navigation for view surfaces that don't use the
 * full `useTaskListKeyboard` machinery (Habits, AI Memory, Dependency
 * Graph). Mounts a window-scoped keydown listener and walks the
 * registered nodes in document order:
 *
 *   - j / ArrowDown → focus the next node
 *   - k / ArrowUp   → focus the previous node
 *   - Enter         → click the currently focused node
 *
 * The hook deliberately keys off whatever element is focusable inside
 * each list item — callers register the focusable child via the
 * returned `register(index)` ref callback. When the user presses j/k
 * while focus is outside the list, the first node is focused.
 *
 * Editable surfaces are skipped so the bindings don't fight inline
 * inputs / textareas / contentEditable.
 */
export function useListJkNavigation(itemCount: number): {
  register: (index: number) => (node: HTMLElement | null) => void;
} {
  const nodesRef = useRef<Array<HTMLElement | null>>([]);

  // Keep the array length in lock-step with itemCount so a list whose
  // contents reorder doesn't leak stale slots into navigation.
  if (nodesRef.current.length !== itemCount) {
    nodesRef.current = Array.from({ length: itemCount }, (_, index) => nodesRef.current[index] ?? null);
  }

  useEffect(() => {
    const findActiveIndex = (): number => {
      const active = document.activeElement;
      if (!(active instanceof HTMLElement)) return -1;
      for (let i = 0; i < nodesRef.current.length; i++) {
        const node = nodesRef.current[i];
        if (node && (node === active || node.contains(active))) return i;
      }
      return -1;
    };
    const focusAt = (index: number) => {
      const node = nodesRef.current[index];
      if (node) node.focus();
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.defaultPrevented) return;
      if (event.metaKey || event.ctrlKey || event.altKey) return;
      const target = event.target;
      if (
        target instanceof HTMLElement &&
        (target.isContentEditable ||
          target.tagName === 'INPUT' ||
          target.tagName === 'TEXTAREA' ||
          target.tagName === 'SELECT')
      ) {
        return;
      }
      if (nodesRef.current.length === 0) return;
      const current = findActiveIndex();
      if (event.key === 'j' || event.key === 'ArrowDown') {
        event.preventDefault();
        const next = current < 0 ? 0 : Math.min(current + 1, nodesRef.current.length - 1);
        focusAt(next);
      } else if (event.key === 'k' || event.key === 'ArrowUp') {
        event.preventDefault();
        const next = current < 0 ? 0 : Math.max(current - 1, 0);
        focusAt(next);
      } else if (event.key === 'Enter' && current >= 0) {
        const node = nodesRef.current[current];
        if (node && document.activeElement === node) {
          event.preventDefault();
          node.click();
        }
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => { window.removeEventListener('keydown', onKeyDown); };
  }, []);

  const register = (index: number) => (node: HTMLElement | null) => {
    nodesRef.current[index] = node;
  };

  return { register };
}
