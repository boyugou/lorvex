export const BASE_TRIGGER_CLASSES = [
  'w-full',
  'min-w-0',
  'outline-hidden',
  'disabled:opacity-50',
  'disabled:cursor-not-allowed',
  'inline-flex',
  'items-center',
  'justify-between',
  'gap-2',
  'border',
  'transition-colors',
  'focus-ring-soft',
].join(' ');

export const VARIANT_TRIGGER_CLASSES = {
  default: 'bg-surface-2 text-text-primary text-sm px-2.5 py-1.5 rounded-r-card border-surface-3 shadow-[var(--shadow-tooltip)] hover:border-accent/30',
  muted: 'bg-surface-3 text-text-secondary text-xs px-2 py-1.5 rounded-r-control border-surface-3 hover:border-accent/20',
  inline: 'bg-surface-2/60 text-text-secondary text-sm px-1.5 py-1 rounded-r-control border-card hover:border-accent/25',
} as const;

export const OPEN_TRIGGER_CLASSES = 'border-accent/40 bg-surface-1 shadow-[var(--shadow-popover)]';

export const LISTBOX_CLASSES = [
  'max-h-64',
  'overflow-y-auto',
  'overscroll-contain',
  'rounded-r-card',
  'border',
  'border-surface-3',
  'bg-surface-1',
  'shadow-[var(--shadow-popover)]',
  'p-1',
].join(' ');

const LAYOUT_CLASS_PREFIXES = [
  'w-',
  'min-w-',
  'max-w-',
  'flex-',
  'basis-',
  'grow',
  'shrink',
  'self-',
] as const;

export function joinClasses(...classes: Array<string | undefined | false>) {
  return classes.filter(Boolean).join(' ');
}

export function extractLayoutClasses(className?: string): string {
  if (!className) return '';
  return className
    .split(/\s+/)
    .filter(Boolean)
    .filter(
      (token) =>
        token === 'flex-1' ||
        token === 'w-full' ||
        LAYOUT_CLASS_PREFIXES.some((prefix) => token.startsWith(prefix)),
    )
    .join(' ');
}
