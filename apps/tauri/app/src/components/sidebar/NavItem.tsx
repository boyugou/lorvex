import { memo, type ReactNode } from 'react';
import { themedSwatch } from '@/lib/colors/themedSwatch';
import { useI18n } from '@/lib/i18n';
import { localeTextDirection } from '@/locales/registry';
import { Tooltip } from '../ui/Tooltip';
import { navItemTooltipSideForDirection } from './NavItem.logic';

const BADGE_VARIANT_CLASSES: Record<string, string> = {
  default: 'bg-surface-3 text-text-secondary',
  danger: 'bg-[var(--danger-tint-md)] text-danger',
};

const TONE_INACTIVE_CLASSES: Record<string, string> = {
  default: 'text-text-secondary hover:bg-surface-3 hover:text-text-primary',
  accent: 'text-accent hover:bg-accent/10',
};

interface NavItemProps {
  label: string;
  onKeyDown?: (e: React.KeyboardEvent<HTMLButtonElement>) => void;
  /**
   * optional one-line explanation of what the view does,
   * surfaced through the `title` tooltip. Advanced modules like
   * Secondary modules had
   * only a label — a first-time user hovering got a redundant copy
   * of the label, not a hint about what the view is for.
   */
  description?: string | undefined;
  icon: ReactNode;
  badge?: number | null | undefined;
  badgeVariant?: 'default' | 'danger';
  dot?: boolean;
  active: boolean;
  accentColor?: string | undefined;
  shortcut?: string | undefined;
  tone?: 'default' | 'accent';
  onClick: () => void;
  onContextMenu?: (e: React.MouseEvent) => void;
}

export default memo(function NavItem({
  label,
  description,
  icon,
  badge,
  badgeVariant = 'default',
  dot,
  active,
  accentColor,
  shortcut,
  tone = 'default',
  onClick,
  onContextMenu,
  onKeyDown,
}: NavItemProps) {
  // surface the keyboard shortcut in the tooltip so
  // mouse-first users discover the binding without opening the
  // shortcut panel. The inline shortcut chip already renders the
  // combo, but only when there is no badge — many views (Today,
  // Upcoming, All Tasks) hide the chip behind their count badge,
  // leaving no visible hint that a shortcut exists.
  const { locale } = useI18n();
  const head = description ? `${label} — ${description}` : label;
  const tooltip = shortcut ? `${head} · ${shortcut}` : head;
  const tooltipSide = navItemTooltipSideForDirection(localeTextDirection(locale));

  return (
    <Tooltip label={tooltip} side={tooltipSide}>
      <button
        type="button"
        onClick={onClick}
        onContextMenu={onContextMenu}
        onKeyDown={onKeyDown}
        aria-current={active ? 'page' : undefined}
        aria-label={label}
        data-active={active || undefined}
        className={`relative w-full grid grid-cols-[1.5rem_minmax(0,1fr)_auto] items-center gap-2 px-2 py-1.5 rounded-r-control text-sm transition-colors text-start active:scale-[0.97] focus-ring-soft data-[active]:bg-accent/20 data-[active]:text-text-primary data-[active]:shadow-[var(--shadow-nav-active)] ${
          active ? '' : TONE_INACTIVE_CLASSES[tone]
        }`}
      >
        <span className="absolute start-0 top-1/2 -translate-y-1/2 h-5 w-[3px] rounded-full bg-accent opacity-0 data-[active]:opacity-100 transition-opacity" data-active={active || undefined} />
        <span className="h-6 w-6 shrink-0 inline-flex items-center justify-center text-base leading-none">
          {accentColor ? (
            <span className="h-2.5 w-2.5 rounded-full shrink-0" style={{ backgroundColor: themedSwatch(accentColor, 'dot') }} />
          ) : icon}
        </span>
        <span className="min-w-0 truncate leading-5">{label}</span>
        <span className="ms-1 shrink-0 flex items-center gap-1">
          {shortcut && !badge && (
            <span className="text-text-muted text-xs">{shortcut}</span>
          )}
          {dot && (
            <span className="h-2 w-2 rounded-full bg-accent" />
          )}
          {badge != null && badge > 0 && (
            // Use the variant classes uniformly. The earlier
            // `accentColor`-driven pill produced a dark-on-dark
            // result for list rows whose `accentColor` was the
            // default muted CSS variable — `hexWithAlpha` can't
            // resolve a `var(--…)` token at runtime, so the badge
            // collapsed to a single near-invisible dark dot. Plain
            // text-muted on surface-3 stays legible in every theme,
            // every list color, and reads as a count rather than a
            // status pill.
            <span
              className={`tabular-nums text-2xs px-1.5 rounded-full min-w-[18px] text-center ${BADGE_VARIANT_CLASSES[badgeVariant]}`}
            >
              {badge}
            </span>
          )}
        </span>
      </button>
    </Tooltip>
  );
})
