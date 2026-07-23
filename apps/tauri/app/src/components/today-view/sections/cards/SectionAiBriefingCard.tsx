import { memo } from 'react';

import { useI18n } from '@/lib/i18n';
import { CollapsibleSection } from '@/components/ui/CollapsibleSection';
import type { DashboardCardCommonProps, SectionOf } from './types';

interface Props extends DashboardCardCommonProps {
  section: SectionOf<'ai_briefing'>;
}

/**
 * AI briefing card — the accent-tinted morning-context blurb at the
 * top of the Today dashboard.
 */
export const SectionAiBriefingCard = memo(function SectionAiBriefingCard({
  aiBriefingEnabled,
  plan,
  collapsed,
  toggle,
}: Props) {
  const { t } = useI18n();
  if (!aiBriefingEnabled || !plan?.briefing) return null;
  return (
    <section>
      <div className={`bg-gradient-to-br from-[var(--accent-tint-xxs)] to-surface-2 border border-accent/25 rounded-r-card ${collapsed ? 'px-4 py-2.5' : 'px-4 py-3'}`}>
        <h2 className="m-0">
          <button
            type="button"
            className="text-text-muted text-xs font-medium cursor-pointer select-none group flex items-center gap-1.5 bg-transparent border-none p-0"
            onClick={toggle}
            aria-expanded={!collapsed}
          >
            <span className={`text-xs transition-transform duration-150 ${collapsed ? '' : 'rotate-90'}`}>›</span>
            <span className="text-accent" aria-hidden="true">✦</span> {t('today.aiBriefing')}
          </button>
        </h2>
        <CollapsibleSection collapsed={collapsed}>
          <p className="text-text-primary text-sm leading-relaxed mt-2 line-clamp-6">{plan.briefing}</p>
        </CollapsibleSection>
      </div>
    </section>
  );
});
