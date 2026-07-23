/**
 * Drag-image helper. The browser default for `draggable` elements is to
 * snapshot the full element bounding box and render that as a
 * translucent rectangle following the pointer — for a Kanban card or an
 * Eisenhower row this means a 200-300 px wide opaque slab obscures the
 * drop targets the user is trying to aim at. The fix is `setDragImage`
 * with a small, custom DOM node ("compact pill") so the cursor stays
 * unobstructed and the visual feedback is honest about what's moving.
 *
 * Implementation notes:
 *  - The drag image must be in the DOM at the moment `setDragImage` is
 *    called or some browsers (notably Safari) will paint nothing. We
 *    parent the pill off-screen on `<body>` and remove it on the next
 *    microtask, well after the browser has rasterized the snapshot.
 *  - Setting `pointer-events: none` keeps the helper from intercepting
 *    the in-flight drag events that fire on the source element.
 */

export interface DragPillOptions {
  /** Short title that goes after the icon. Truncated to ~32 chars. */
  title: string;
  /**
   * Optional leading glyph (e.g. ✦, →). A single emoji or short SVG
   * symbol keeps the pill recognizable without expanding it.
   */
  icon?: string | undefined;
}

const MAX_TITLE_CHARS = 32;

function truncateTitle(title: string): string {
  const normalized = title.trim();
  if (normalized.length <= MAX_TITLE_CHARS) return normalized;
  // Trim on a word boundary when possible so the ellipsis lands
  // cleanly. Falls back to a hard slice if no whitespace is nearby.
  const slice = normalized.slice(0, MAX_TITLE_CHARS - 1);
  const lastSpace = slice.lastIndexOf(' ');
  const cut = lastSpace > MAX_TITLE_CHARS / 2 ? slice.slice(0, lastSpace) : slice;
  return `${cut}…`;
}

/**
 * Attach a compact pill drag image to the given DragEvent. Call this
 * inside `onDragStart` right after `dataTransfer.setData` so the same
 * frame the drag begins also carries the custom snapshot. Safe to call
 * in non-browser environments (SSR) — bails when `document` is missing.
 */
export function applyCompactDragImage(
  event: React.DragEvent<HTMLElement> | DragEvent,
  options: DragPillOptions,
): void {
  if (typeof document === 'undefined') return;
  const dt = (event as DragEvent).dataTransfer ?? (event as React.DragEvent).dataTransfer;
  if (!dt || typeof dt.setDragImage !== 'function') return;

  const pill = document.createElement('div');
  pill.setAttribute('aria-hidden', 'true');
  // Inline styles so the pill renders identically regardless of which
  // stylesheet has loaded by drag-start time. The colors track the
  // accent / surface token family so themes pick up the same depth as
  // the rest of the UI.
  pill.style.cssText = [
    'position: fixed',
    'top: -1000px',
    'left: -1000px',
    'pointer-events: none',
    'display: inline-flex',
    'align-items: center',
    'gap: 6px',
    'max-width: 240px',
    'padding: 6px 10px',
    'border-radius: var(--radius-r-control, 0.5rem)',
    'background: var(--accent-tint-md, rgba(96, 96, 96, 0.92))',
    'color: var(--color-on-accent, #fff)',
    'font-family: var(--font-sans, system-ui)',
    'font-size: 12px',
    'font-weight: 600',
    'line-height: 1.2',
    'white-space: nowrap',
    'overflow: hidden',
    'box-shadow: var(--shadow-tooltip, 0 4px 12px rgba(0, 0, 0, 0.18))',
  ].join('; ');

  if (options.icon) {
    const icon = document.createElement('span');
    icon.textContent = options.icon;
    icon.style.cssText = 'flex: 0 0 auto; opacity: 0.9;';
    pill.appendChild(icon);
  }
  const title = document.createElement('span');
  title.textContent = truncateTitle(options.title);
  title.style.cssText = 'overflow: hidden; text-overflow: ellipsis;';
  pill.appendChild(title);

  document.body.appendChild(pill);
  try {
    dt.setDragImage(pill, 12, 12);
  } catch {
    // Older browsers without `setDragImage` will already have skipped
    // out via the typeof check above; this catch protects against
    // permission errors (Firefox throws if dataTransfer is read-only).
  }
  // Pull the helper out of the DOM on the next task so it doesn't sit
  // around for the lifetime of the drag. The browser has already
  // captured the snapshot by the time the drag event handler returns.
  setTimeout(() => {
    if (pill.parentNode) pill.parentNode.removeChild(pill);
  }, 0);
}
