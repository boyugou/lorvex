/**
 * drop-zone `dragleave` flicker.
 *
 * The naïve dragleave handler used across Eisenhower / Kanban / Upcoming /
 * Calendar pages was:
 *
 *   onDragLeave={(e) => {
 *     if (e.currentTarget.contains(e.relatedTarget as Node)) return;
 *     onDragOverColumn(null);
 *   }}
 *
 * That works when `relatedTarget` is a sibling element, but the HTML5 DnD
 * spec lets browsers fire `dragleave` with `relatedTarget === null` in
 * several cases:
 *
 *   - the cursor crossed into a descendant element that has been re-styled
 *     mid-drag (Tooltip portals, focus rings, drag-image artifacts);
 *   - the cursor moved into the native drag image overlay;
 *   - the cursor briefly left the document chrome (Chromium quirk on macOS).
 *
 * `null.contains(...)` is `false`, so the previous code interpreted these
 * spurious leaves as real ones and cleared the drop highlight. The visible
 * result was a fast strobing of the `ring-2 bg-accent/5` style as
 * dragenter / dragleave fired in alternation — what the audit called the
 * "drag-leave flicker".
 *
 * Fix: when `relatedTarget` is null but the cursor is still inside the
 * drop zone's bounding rect, treat the leave as spurious and ignore it.
 * This needs `event.clientX/Y` so the helper takes a `DragEvent` directly.
 */

export function isSpuriousDragLeave(event: {
  currentTarget: Element;
  relatedTarget: EventTarget | null;
  clientX: number;
  clientY: number;
}): boolean {
  // Real DOM descendant — definitely still inside.
  if (event.relatedTarget instanceof Node && event.currentTarget.contains(event.relatedTarget)) {
    return true;
  }
  // No relatedTarget: fall back to a geometry check. Only treat as
  // spurious when the cursor is unambiguously inside the rect; coordinates
  // exactly at 0,0 (some browsers report this when leaving the window)
  // count as a true leave.
  if (event.relatedTarget == null && (event.clientX !== 0 || event.clientY !== 0)) {
    const rect = event.currentTarget.getBoundingClientRect();
    if (
      event.clientX >= rect.left &&
      event.clientX <= rect.right &&
      event.clientY >= rect.top &&
      event.clientY <= rect.bottom
    ) {
      return true;
    }
  }
  return false;
}
