import { useCallback } from 'react';

import type { TranslationKey } from '@/lib/i18n';
// Settings now navigates inline (same as mobile) rather than opening a separate window.
import type { SidebarModule } from '@/lib/sidebarModules';
import type { View } from '@/lib/types';
import { GearIcon } from '../ui/icons';

import NavItem from './NavItem';
import SidebarToolbox from './SidebarToolbox';
import { SECONDARY_MODULES, renderSecondaryModules } from './secondaryModules';

interface SecondaryNavProps {
  availableVersion: string | null;
  canShowModule: (module: SidebarModule) => boolean;
  currentView: View;
  isModuleInToolbox: (module: SidebarModule) => boolean;
  navShortcuts: Record<string, string | undefined>;
  onNavigate: (view: View) => void;
  showDesktopFeatures: boolean;
  t: (key: TranslationKey) => string;
  unseenErrorLogCount: number | null;
}

export default function SecondaryNav({
  availableVersion,
  canShowModule,
  currentView,
  isModuleInToolbox,
  navShortcuts,
  onNavigate,
  showDesktopFeatures,
  t,
  unseenErrorLogCount,
}: SecondaryNavProps) {
  const handleSettingsClick = useCallback(() => {
    onNavigate({ type: 'settings' });
  }, [onNavigate]);

  return (
    <nav className="px-2 space-y-0.5 mb-1" aria-label={t('nav.more')}>
      <span className="block text-xs font-medium text-text-muted px-2 mb-0.5">{t('nav.views')}</span>

      {renderSecondaryModules({
        modules: SECONDARY_MODULES,
        filter: (def) => canShowModule(def.module) && !isModuleInToolbox(def.module),
        showDesktopFeatures,
        currentView,
        onNavigate,
        navShortcuts,
        t,
      })}

      <SidebarToolbox
        showDesktopFeatures={showDesktopFeatures}
        canShowModule={canShowModule}
        isModuleInToolbox={isModuleInToolbox}
        currentView={currentView}
        onNavigate={onNavigate}
        navShortcuts={navShortcuts}
        t={t}
      />

      <NavItem
        label={t('nav.settings')}
        description={unseenErrorLogCount ? t('nav.settingsUnseenErrors') : undefined}
        icon={<GearIcon />}
        badge={unseenErrorLogCount}
        badgeVariant="danger"
        dot={availableVersion !== null}
        active={currentView.type === 'settings'}
        onClick={handleSettingsClick}
      />
    </nav>
  );
}
