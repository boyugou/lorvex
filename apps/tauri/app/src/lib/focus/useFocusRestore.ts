import { useEffect, useRef } from 'react';
import {
  createHTMLElementFocusRestoreMachine,
  type FocusRestoreMachine,
} from './focusRestore.logic';
import { readActiveHTMLElement } from './useFocusRestore.runtime';

interface UseFocusRestoreOptions {
  shouldRestore?: (() => boolean) | undefined;
}

/**
 * Saves a ref to `document.activeElement` on mount and restores focus to it on
 * unmount. This ensures that when a modal/overlay closes, keyboard focus returns
 * to the element that triggered it (WCAG 2.4.3).
 */
export function useFocusRestore(options: UseFocusRestoreOptions = {}) {
  const machineRef = useRef<FocusRestoreMachine<HTMLElement> | null>(null);
  if (machineRef.current === null) {
    machineRef.current = createHTMLElementFocusRestoreMachine();
  }
  const machine = machineRef.current;
  const shouldRestoreRef = useRef(options.shouldRestore);
  shouldRestoreRef.current = options.shouldRestore;

  useEffect(() => {
    machine.open(readActiveHTMLElement());

    return () => {
      if (shouldRestoreRef.current && !shouldRestoreRef.current()) {
        machine.open(null);
        return;
      }
      machine.close();
    };
    // `machine` is a singleton stored via a ref initialized once on mount;
    // its identity never changes for the life of this component.
  }, [machine]);
}
