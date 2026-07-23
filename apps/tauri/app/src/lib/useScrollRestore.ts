import { useCallback, useLayoutEffect, useRef } from 'react';
import { createScrollRestoreController } from './useScrollRestore.logic';
import { useLazyRef } from './useLazyRef';

export function useScrollRestore(key: string) {
  const ref = useRef<HTMLDivElement>(null);
  const controllerRef = useLazyRef(() => createScrollRestoreController());

  // `useLayoutEffect` runs synchronously after DOM mutation but BEFORE
  // the browser paints — so the restored `scrollTop` is in place
  // before the first frame the user sees. The previous `useEffect`
  // ran AFTER paint, leaving a one-frame flash of `scrollTop = 0`
  // every time a remembered key remounted.
  useLayoutEffect(() => {
    controllerRef.current.restore(key, ref.current);
    // controllerRef is a stable MutableRefObject from useLazyRef.
  }, [key, controllerRef]);

  const handleScroll = useCallback(() => {
    const el = ref.current;
    if (el) {
      controllerRef.current.remember(key, el.scrollTop);
    }
    // controllerRef is a stable MutableRefObject from useLazyRef.
  }, [key, controllerRef]);

  return { ref, onScroll: handleScroll };
}
