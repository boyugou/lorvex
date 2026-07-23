import { createPortal } from 'react-dom';

/**
 * Simple portal wrapper that renders children into document.body.
 * Every modal/overlay should use this for consistent layering.
 */
export function OverlayPortal({ children }: { children: React.ReactNode }) {
  return createPortal(children, document.body);
}
