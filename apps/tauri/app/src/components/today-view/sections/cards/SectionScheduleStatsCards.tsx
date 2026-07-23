import { memo } from 'react';

import { useI18n } from '@/lib/i18n';
import ScheduleTimeline from '@/components/schedule-timeline/ScheduleTimelineContent';
import { CollapsibleSection } from '@/components/ui/CollapsibleSection';
import { StatGrid } from '@/components/ui/StatGrid';
import { SectionHeader, StatCard } from '@/components/today-view/primitives';
import type { DashboardCardCommonProps, SectionOf } from './types';

/** Schedule timeline section. */
export const SectionScheduleCard = memo(function SectionScheduleCard({
  focusSchedule,
  onSelectTask,
  collapsed,
  toggle,
}: { section: SectionOf<'schedule'> } & DashboardCardCommonProps) {
  const { t } = useI18n();
  if (!focusSchedule || focusSchedule.blocks.length === 0) return null;
  return (
    <section>
      <SectionHeader title={t('today.schedule')} collapsed={collapsed} onToggleCollapse={toggle} />
      <CollapsibleSection collapsed={collapsed}>
        <ScheduleTimeline schedule={focusSchedule} onSelectTask={onSelectTask} />
      </CollapsibleSection>
    </section>
  );
});

/** Weekly stats card — rolling KPIs at the bottom of the dashboard. */
export const SectionStatsCard = memo(function SectionStatsCard({
  overview,
  collapsed,
  toggle,
}: { section: SectionOf<'stats'> } & DashboardCardCommonProps) {
  const { t } = useI18n();
  if (!overview?.stats) return null;
  return (
    <section className="mt-4">
      <SectionHeader title={t('today.thisWeek')} collapsed={collapsed} onToggleCollapse={toggle} />
      <CollapsibleSection collapsed={collapsed}>
        {/* Shared StatGrid primitive — see ui/StatGrid.tsx. */}
        <StatGrid density="compact">
          <StatCard label={t('today.open')} value={overview.stats.open_count} />
          <StatCard
            label={t('today.completed')}
            value={overview.stats.completed_this_week}
            accent="success"
          />
          <StatCard label={t('today.someday')} value={overview.stats.someday_count} />
          {overview.stats.completion_streak > 1 && (
            <StatCard
              label={t('today.dayStreak')}
              value={overview.stats.completion_streak}
              accent="accent"
            />
          )}
        </StatGrid>
      </CollapsibleSection>
    </section>
  );
});
