import {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useLayoutEffect,
  useRef,
  type ChangeEvent,
  type KeyboardEvent as ReactKeyboardEvent,
  type TextareaHTMLAttributes,
} from 'react';
import { isImeComposing } from '@/lib/ime';

/*
 * `<AutosizingTextarea>` primitive.
 *
 * Lorvex's long-form text inputs (event description, daily-review
 * reflection, capture notes, memory notes) all want the same
 * behaviour: start at a small minRows, grow as the user types up to
 * maxRows, then become scrollable. Each call site reinvented the same
 * scrollHeight measurement dance with subtle drift in border-box
 * accounting and reset semantics. The primitive consolidates the
 * recipe so layout-sensitive textareas grow consistently.
 *
 * Behaviour:
 *   - Mounts at `minRows`-tall regardless of initial content (which
 *     then triggers a measurement pass and snaps to the content
 *     height bounded by `maxRows`).
 *   - Each value change resets `height: auto` (so shrink works) and
 *     then sets `height` to `min(scrollHeight, maxRows * lineHeight)`.
 *   - Optional `resize` prop exposes the standard CSS resize control
 *     for the cases where the user should be allowed to override the
 *     auto-size — Notes-for-AI's `resize-y` is the canonical case.
 *
 * Forwards refs so callers (e.g. focus on mount, imperative scroll
 * sync) can still address the underlying `<textarea>`.
 */

type AutosizingTextareaResize = 'none' | 'vertical';

interface AutosizingTextareaProps
  extends Omit<TextareaHTMLAttributes<HTMLTextAreaElement>, 'rows' | 'style'> {
  /** Floor height. Defaults to `2`. */
  minRows?: number;
  /**
   * Ceiling height. Above this, the textarea becomes scrollable.
   * Defaults to `12` — past that, the form usually wants a different
   * affordance (Markdown editor, dialog).
   */
  maxRows?: number;
  /**
   * `none` (default) clamps to the auto-sized box;
   * `vertical` exposes the native CSS resize handle so the user can
   * override the auto-size — pair with a `min-h` style if the
   * primitive's floor isn't enough.
   */
  resize?: AutosizingTextareaResize;
  /**
   * Optional inline style merged after the auto-size measurement.
   * Use sparingly — most callers should compose via `className`.
   */
  style?: React.CSSProperties;
  /**
   * Optional Escape handler that is automatically IME-guarded — when the
   * user is mid-composition (CJK candidate window open), Escape closes
   * the candidate window and is NOT forwarded. Without this guard,
   * pressing Escape to dismiss the candidate would also fire the
   * caller's cancel/close path and drop the draft. Consumers that wire
   * their own `onKeyDown` should prefer this prop for the cancel path so
   * the IME guard stays consistent across every long-form textarea.
   */
  onEscape?: () => void;
}

const RESIZE_CLASS: Record<AutosizingTextareaResize, string> = {
  none: 'resize-none',
  vertical: 'resize-y',
};

export const AutosizingTextarea = forwardRef<HTMLTextAreaElement, AutosizingTextareaProps>(
  function AutosizingTextarea(
    {
      minRows = 2,
      maxRows = 12,
      resize = 'none',
      onChange,
      onKeyDown,
      onEscape,
      value,
      defaultValue,
      className = '',
      style,
      ...rest
    },
    ref,
  ) {
    const innerRef = useRef<HTMLTextAreaElement | null>(null);
    // rAF coalescing handle. A burst of synchronous keystrokes
    // (paste, IME flush, repeat-key) would otherwise call `measure()`
    // once per keystroke, each forcing two style reads + writes
    // (height: auto then height: Npx) inside the same task. Coalescing
    // to the next animation frame turns N measurements per task into
    // exactly one — the user's eye still sees the height update on
    // the next paint, but the synchronous layout work collapses.
    const rafIdRef = useRef<number | null>(null);
    // Forward both our internal ref and the caller's ref.
    useImperativeHandle(ref, () => innerRef.current as HTMLTextAreaElement, []);

    const measureNow = useCallback(() => {
      const el = innerRef.current;
      if (!el) return;
      // Reset to `auto` so the scrollHeight measurement reflects the
      // *content* height rather than the previously-set value. Without
      // this the textarea ratchets up but never shrinks back when text
      // is deleted.
      el.style.height = 'auto';
      const computed = window.getComputedStyle(el);
      const lineHeight = Number.parseFloat(computed.lineHeight) || 20;
      const paddingTop = Number.parseFloat(computed.paddingTop) || 0;
      const paddingBottom = Number.parseFloat(computed.paddingBottom) || 0;
      const borderTop = Number.parseFloat(computed.borderTopWidth) || 0;
      const borderBottom = Number.parseFloat(computed.borderBottomWidth) || 0;
      const isBorderBox = computed.boxSizing === 'border-box';
      const chrome = paddingTop + paddingBottom + (isBorderBox ? borderTop + borderBottom : 0);
      const max = lineHeight * maxRows + chrome;
      const min = lineHeight * minRows + chrome;
      const next = Math.max(min, Math.min(el.scrollHeight, max));
      el.style.height = `${next}px`;
      // Toggle the scroll affordance only when we hit the cap so the
      // textarea doesn't show a redundant gutter while it's still
      // growing.
      el.style.overflowY = el.scrollHeight > max ? 'auto' : 'hidden';
    }, [minRows, maxRows]);

    // coalesce repeated calls into a single rAF callback. The
    // pending handle is cancelled on unmount and on every new
    // schedule so a paste-during-paste collapses to one measurement.
    const measure = useCallback(() => {
      if (rafIdRef.current != null) return;
      rafIdRef.current = window.requestAnimationFrame(() => {
        rafIdRef.current = null;
        measureNow();
      });
    }, [measureNow]);

    // Initial mount + every render where `value` changes. Measure
    // synchronously on layout effect so the first paint already has
    // the correct height (no rAF flash). Subsequent value changes
    // route through `measure()` which is rAF-coalesced.
    useLayoutEffect(() => {
      // drop any pending rAF before a synchronous re-measure so
      // the queued frame doesn't fire after this layout pass and stomp
      // the height we just wrote. Without this, a fast value update can
      // race the in-flight rAF callback and leave the textarea sized to
      // the previous value for one paint.
      if (rafIdRef.current != null) {
        cancelAnimationFrame(rafIdRef.current);
        rafIdRef.current = null;
      }
      measureNow();
    }, [measureNow, value, defaultValue]);

    useEffect(() => {
      if (typeof document === 'undefined') return;
      const fontsReady = document.fonts?.ready;
      if (fontsReady == null) return;
      let didFire = false;
      fontsReady
        .then(() => {
          if (didFire) return;
          didFire = true;
          // The component may have unmounted between the await and the
          // resolution; bail if the ref is gone.
          if (!innerRef.current) return;
          measureNow();
        })
        .catch(() => {
          /* font-load rejection is non-fatal — the initial measurement still applies */
        });
      return () => {
        didFire = true;
      };
      // Intentionally mount-only: webfonts resolve once per document
      // lifetime, so a re-subscription on every value change would
      // accumulate handlers without benefit.
      // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    // Cleanup any pending rAF on unmount so the callback doesn't fire
    // against a torn-down ref.
    useEffect(() => {
      return () => {
        if (rafIdRef.current != null) {
          cancelAnimationFrame(rafIdRef.current);
          rafIdRef.current = null;
        }
      };
    }, []);

    // Window resize can change line-height / padding (responsive
    // typography), so re-measure on viewport changes. Routed through
    // the rAF coalescer so a drag-resize burst measures once per
    // frame, not once per resize event.
    useEffect(() => {
      const onResize = () => measure();
      window.addEventListener('resize', onResize);
      return () => window.removeEventListener('resize', onResize);
    }, [measure]);

    const handleChange = useCallback(
      (event: ChangeEvent<HTMLTextAreaElement>) => {
        // measurement is rAF-coalesced so a burst of input
        // events (IME compose, fast paste) only triggers one layout
        // pass. The visual update still lands on the next paint, so
        // the user doesn't see a flicker between keystroke and grow.
        measure();
        onChange?.(event);
      },
      [measure, onChange],
    );

    const handleKeyDown = useCallback(
      (event: ReactKeyboardEvent<HTMLTextAreaElement>) => {
        // IME-guarded Escape: while the candidate window is open
        // (CJK input), the first Escape closes that window and must NOT
        // bubble to the caller's cancel path. `isImeComposing` covers
        // every browser+OS combination (Chromium clears `isComposing`
        // on the Escape keydown itself; Safari keeps it set; both
        // report keyCode 229 mid-composition).
        if (onEscape && event.key === 'Escape') {
          if (!isImeComposing(event)) {
            event.preventDefault();
            onEscape();
          }
        }
        onKeyDown?.(event);
      },
      [onEscape, onKeyDown],
    );

    return (
      <textarea
        ref={innerRef}
        rows={minRows}
        value={value}
        defaultValue={defaultValue}
        onChange={handleChange}
        onKeyDown={handleKeyDown}
        className={`${RESIZE_CLASS[resize]} ${className}`.trim()}
        style={style}
        {...rest}
      />
    );
  },
);
