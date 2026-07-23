import { useId, useState, type ReactNode } from 'react';
import { useI18n } from '@/lib/i18n';
import { Pill, type PillTone } from '@/components/ui/Pill';
import {
  CheckIcon,
  WarningIcon,
  RecurrenceIcon,
  ThoughtBubbleIcon,
  CalendarUpcomingIcon,
  TargetIcon,
  FlameIcon,
  ChartIcon,
} from '@/components/ui/icons';

function PauseIcon(props: React.SVGProps<SVGSVGElement>) {
  return (
    <svg width={16} height={16} viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" {...props}>
      <rect x="4" y="3" width="2.5" height="10" rx="0.75" fill="currentColor" />
      <rect x="9.5" y="3" width="2.5" height="10" rx="0.75" fill="currentColor" />
    </svg>
  );
}

function ChevronIcon({ expanded, className }: { expanded: boolean; className?: string }) {
  return (
    <svg
      width={16}
      height={16}
      viewBox="0 0 16 16"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
      className={`transition-transform duration-200 ${expanded ? 'rotate-0' : '-rotate-90'} ${className ?? ''}`}
    >
      <path d="M4 6l4 4 4-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

const SECTION_ICONS: Record<string, (props: { className?: string }) => ReactNode> = {
  checkmark: (p) => <CheckIcon {...p} />,
  warning: (p) => <WarningIcon {...p} />,
  pause: (p) => <PauseIcon {...p} />,
  defer: (p) => <RecurrenceIcon {...p} />,
  someday: (p) => <ThoughtBubbleIcon {...p} />,
  calendar: (p) => <CalendarUpcomingIcon {...p} />,
  target: (p) => <TargetIcon {...p} />,
  flame: (p) => <FlameIcon {...p} />,
  chart: (p) => <ChartIcon {...p} />,
};

type SectionVariant = 'default' | 'success' | 'warning' | 'danger';

const VARIANT_ICON_BG: Record<SectionVariant, string> = {
  default: 'bg-surface-3/60 text-text-muted',
  success: 'chip-success',
  warning: 'chip-warning',
  danger: 'chip-danger',
};

interface ReviewSectionProps {
  title: string;
  subtitle: string;
  icon: string;
  variant?: SectionVariant;
  collapsible?: boolean;
  defaultExpanded?: boolean;
  badge?: number | string | undefined;
  children: ReactNode;
}

export default function ReviewSection({
  title,
  subtitle,
  icon,
  variant = 'default',
  collapsible = false,
  defaultExpanded = true,
  badge,
  children,
}: ReviewSectionProps) {
  const [expanded, setExpanded] = useState(defaultExpanded);
  const contentId = useId();
  const { formatNumber } = useI18n();
  const IconComponent = SECTION_ICONS[icon];

  const headerContent = (
    <>
      <span className={`w-7 h-7 rounded-r-control inline-flex items-center justify-center shrink-0 ${VARIANT_ICON_BG[variant]}`}>
        {IconComponent ? <IconComponent className="w-4 h-4" /> : <span className="text-xs">{'\u00B7'}</span>}
      </span>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <h2 className="heading-section">{title}</h2>
          {badge != null && (
            <Pill
              tone={(variant === 'default' ? 'muted' : variant) satisfies PillTone}
              size="sm"
              tabular={typeof badge === 'number'}
              className="font-bold leading-none"
            >
              {typeof badge === 'number' ? formatNumber(badge) : badge}
            </Pill>
          )}
        </div>
        <p className="text-text-muted text-xs mt-0.5">{subtitle}</p>
      </div>
      {collapsible && (
        <ChevronIcon expanded={expanded} className="text-text-muted shrink-0" />
      )}
    </>
  );

  return (
    // swap the Tailwind v3 `animate-in fade-in
    // duration-300` and `animate-in fade-in slide-in-from-top-1
    // duration-200` utilities (silently inert under Tailwind v4
    // without the `tailwindcss-animate` plugin we don't ship) for
    // the v4-native arbitrary `animate-[fade-in_…]` and
    // `animate-[slide-in-up_…]` shorthands that resolve against the
    // keyframes already defined in index.css.
    <section className="animate-[fade-in_0.3s_ease-out]">
      {collapsible ? (
        <button
          type="button"
          onClick={() => setExpanded((prev) => !prev)}
          aria-expanded={expanded}
          aria-controls={contentId}
          className="w-full flex items-center gap-3 mb-3 text-start rounded-r-control -mx-1 px-1 py-1 hover:bg-surface-2/50 transition-colors focus-ring-soft"
        >
          {headerContent}
        </button>
      ) : (
        <div className="flex items-center gap-3 mb-3">
          {headerContent}
        </div>
      )}
      <div
        id={contentId}
        hidden={collapsible && !expanded}
        className="animate-[slide-in-up_0.2s_ease-out]"
      >
        {children}
      </div>
    </section>
  );
}
