import type { QuadrantKey } from './quadrants';

// per-quadrant empty-state border tint. Picks up
// the same accent vocabulary as `QUADRANT_STYLE` (danger / warning /
// accent / surface-3) so the empty placeholder still reads as part of
// its parent quadrant rather than a uniform "nothing here" panel.
const QUADRANT_EMPTY_BORDER: Record<QuadrantKey, string> = {
  urgent_important: 'border-danger/15',
  not_urgent_important: 'border-warning/20',
  urgent_not_important: 'border-accent/15',
  not_urgent_not_important: 'border-surface-3',
};

/**
 * Per-quadrant empty placeholder. Each of the four panels picks up a
 * tint of its own accent + a per-quadrant copy line, so the empty
 * matrix doesn't read as four identical placeholders.
 */
export function EmptyQuadrant({
  quadrantKey,
  isDragOver,
  emptyLabel,
  dropHint,
}: {
  quadrantKey: QuadrantKey;
  isDragOver: boolean;
  emptyLabel: string;
  dropHint: string;
}) {
  return (
    <div className={`flex-1 rounded-r-card border border-dashed flex items-center justify-center text-center px-3 ${
      isDragOver ? 'border-accent/50 bg-accent/10' : QUADRANT_EMPTY_BORDER[quadrantKey]
    }`}>
      <p className="text-text-muted text-xs leading-relaxed">
        {isDragOver ? dropHint : emptyLabel}
      </p>
    </div>
  );
}
