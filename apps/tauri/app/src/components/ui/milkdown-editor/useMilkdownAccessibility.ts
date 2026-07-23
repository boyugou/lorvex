import { useEffect, type RefObject } from 'react';

export function useMilkdownAccessibility(
  wrapperRef: RefObject<HTMLDivElement | null>,
  ariaLabel: string,
) {
  useEffect(() => {
    const el = wrapperRef.current;
    if (!el) return;
    const apply = () => {
      const editable = el.querySelector<HTMLElement>('[contenteditable="true"]');
      if (editable && editable.getAttribute('aria-label') !== ariaLabel) {
        editable.setAttribute('aria-label', ariaLabel);
      }
    };
    apply();
    const observer = new MutationObserver(apply);
    observer.observe(el, { childList: true, subtree: true, attributes: true, attributeFilter: ['contenteditable'] });
    return () => observer.disconnect();
  }, [ariaLabel, wrapperRef]);
}
