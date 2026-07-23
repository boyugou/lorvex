import { useCallback } from 'react';
import type { TranslationKey } from '@/lib/i18n';
import type { Stats } from '@/lib/ipc/tasks/models';
import type { SidebarModule } from '@/lib/sidebarModules';
import type { View } from '@/lib/types';
import {
  CalendarUpcomingIcon,
  ClipboardIcon,
  SunIcon,
  ThoughtBubbleIcon,
} from '../ui/icons';

import NavItem from './NavItem';

interface PrimaryNavProps {
  canShowModule: (module: SidebarModule) => boolean;
  currentView: View;
  navShortcuts: Record<string, string | undefined>;
  onNavigate: (view: View) => void;
  stats: Stats | null;
  t: (key: TranslationKey) => string;
  todayBadge: number | null;
}

export default function PrimaryNav({
  canShowModule,
  currentView,
  navShortcuts,
  onNavigate,
  stats,
  t,
  todayBadge,
}: PrimaryNavProps) {
  const navigateToday = useCallback(() => onNavigate({ type: 'today' }), [onNavigate]);
  const navigateUpcoming = useCallback(() => onNavigate({ type: 'upcoming' }), [onNavigate]);
  const navigateAll = useCallback(() => onNavigate({ type: 'all_tasks' }), [onNavigate]);
  const navigateSomeday = useCallback(() => onNavigate({ type: 'someday' }), [onNavigate]);

  return (
    <nav className="px-2 space-y-0.5" aria-label={t('nav.views')}>
      {canShowModule('today') && (
        <NavItem
          label={t('nav.today')}
          description={t('nav.today.desc')}
          icon={<SunIcon />}
          badge={todayBadge}
          active={currentView.type === 'today'}
          onClick={navigateToday}
          shortcut={navShortcuts.today}
        />
      )}
      {canShowModule('upcoming') && (
        <NavItem
          label={t('nav.upcoming')}
          description={t('nav.upcoming.desc')}
          icon={<CalendarUpcomingIcon />}
          badge={stats?.upcoming_week_count || null}
          active={currentView.type === 'upcoming'}
          onClick={navigateUpcoming}
          shortcut={navShortcuts.upcoming}
        />
      )}
      {canShowModule('all_tasks') && (
        <NavItem
          label={t('nav.allTasks')}
          description={t('nav.allTasks.desc')}
          icon={<ClipboardIcon />}
          badge={stats?.open_count || null}
          active={currentView.type === 'all_tasks'}
          onClick={navigateAll}
          shortcut={navShortcuts.allTasks}
        />
      )}
      {canShowModule('someday') && (
        <NavItem
          label={t('nav.someday')}
          description={t('nav.someday.desc')}
          icon={<ThoughtBubbleIcon />}
          badge={stats?.someday_count || null}
          active={currentView.type === 'someday'}
          onClick={navigateSomeday}
          shortcut={navShortcuts.someday}
        />
      )}
    </nav>
  );
}
