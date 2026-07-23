import { useEffect, useRef, useState, type ReactNode } from 'react';

interface CollapsibleSectionProps {
  collapsed: boolean;
  children: ReactNode;
}

/**
 * Animated collapsible wrapper.
 *
 * Modern browsers (Safari 17.4+, Chrome 118+, Firefox 124+) animate
 * `grid-template-rows: 0fr → 1fr` correctly, which gives us the cleanest
 * "auto height" transition without measuring.
 *
 * Safari ≤16.3 — and any release of Safari 17 prior to
 * 17.4 — DOES NOT interpolate that fr-based transition; the grid track
 * snapped open/shut without any animation, costing the affordance the
 * very feel it exists for. We keep the fr-based grid as the primary
 * mechanism (still the best on every modern browser) but also drive a
 * `max-height` transition off a measured pixel value as a fallback. On
 * modern engines both run together harmlessly; on Safari ≤16.3 only the
 * max-height transition produces visible motion.
 *
 * Usage:
 *   <CollapsibleSection collapsed={collapsed}>
 *     <div>content that collapses</div>
 *   </CollapsibleSection>
 */
export function CollapsibleSection({ collapsed, children }: CollapsibleSectionProps) {
  const innerRef = useRef<HTMLDivElement | null>(null);
  // Measured natural pixel height of the inner content. Drives the
  // max-height fallback. Re-measured whenever the content's bounding
  // box changes (children resize, fonts load, locale flips a longer
  // string in, etc.) so the open state always tracks reality.
  // The `<number>` type parameter is redundant — TS infers from the
  // literal `0`. Dropped per the frontend-cleanup pass.
  const [contentHeight, setContentHeight] = useState(0);

  useEffect(() => {
    const node = innerRef.current;
    if (!node) return;
    if (typeof ResizeObserver === 'undefined') {
      // Older browsers — fall back to a one-shot measurement; the
      // primary fr-based transition still works on modern engines that
      // also lack ResizeObserver only in deeply niche configurations.
      setContentHeight(node.scrollHeight);
      return;
    }
    const observer = new ResizeObserver(() => {
      setContentHeight(node.scrollHeight);
    });
    observer.observe(node);
    setContentHeight(node.scrollHeight);
    return () => { observer.disconnect(); };
  }, [children]);

  return (
    <div
      className={`grid transition-[grid-template-rows] duration-200 ease-out ${collapsed ? 'grid-rows-[0fr]' : 'grid-rows-[1fr]'}`}
      style={{
        // max-height fallback for Safari ≤16.3. Add a small buffer so
        // a sub-pixel rounding error never clips the last line of text.
        maxHeight: collapsed ? 0 : contentHeight + 4,
        transition: 'grid-template-rows 200ms ease-out, max-height 200ms ease-out',
      }}
    >
      <div ref={innerRef} className="overflow-hidden">{children}</div>
    </div>
  );
}
