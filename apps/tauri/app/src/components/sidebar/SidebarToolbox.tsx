import { useEffect, useId, useState } from 'react';

import type { TranslationKey } from '@/lib/i18n';
import { SIDEBAR_MODULES, type SidebarModule } from '@/lib/sidebarModules';
import type { View } from '@/lib/types';
import { getUIStateBoolean, setUIState } from '@/lib/storage/uiState';

import { SECONDARY_MODULES, renderSecondaryModules } from './secondaryModules';

const TOOLBOX_STORAGE_KEY = 'sidebar:toolboxOpen';

interface SidebarToolboxProps {
  showDesktopFeatures: boolean;
  canShowModule: (m: SidebarModule) => boolean;
  isModuleInToolbox: (m: SidebarModule) => boolean;
  currentView: View;
  onNavigate: (view: View) => void;
  navShortcuts: Record<string, string | undefined>;
  t: (key: TranslationKey) => string;
}

export default function SidebarToolbox({
  showDesktopFeatures,
  canShowModule,
  isModuleInToolbox,
  currentView,
  onNavigate,
  navShortcuts,
  t,
}: SidebarToolboxProps) {
  const [open, setOpen] = useState(() => getUIStateBoolean(TOOLBOX_STORAGE_KEY, false));

  const currentModule = currentView.type as SidebarModule;
  const activeInToolbox = isModuleInToolbox(currentModule);

  // Auto-expand when user navigates to a toolbox item (but don't lock it open)
  useEffect(() => {
    if (activeInToolbox && !open) {
      setOpen(true);
      setUIState(TOOLBOX_STORAGE_KEY, true);
    }
  }, [activeInToolbox, open]);

  const isOpen = open;
  // the disclosure button carried `aria-expanded`
  // but no `aria-controls`, and the panel had no matching `id`. AT
  // users got no programmatic relationship between the trigger and
  // the panel — the button announced "expanded" but the user could
  // not navigate to what was expanded. `useId()` mints a stable id;
  // the button references it via `aria-controls` and the panel
  // exposes it as its DOM `id`.
  const panelId = useId();

  // Only render if there are visible toolbox items
  const toolboxModules = SIDEBAR_MODULES.filter((m) => isModuleInToolbox(m));
  const hasItems = toolboxModules.some((vt) => showDesktopFeatures && canShowModule(vt));
  if (!hasItems) return null;

  function toggle(): void {
    const next = !open;
    setOpen(next);
    setUIState(TOOLBOX_STORAGE_KEY, next);
  }

  return (
    <>
      <button
        type="button"
        onClick={toggle}
        className="relative w-full grid grid-cols-[1.5rem_minmax(0,1fr)_auto] items-center gap-2 px-2 py-1.5 rounded-r-control text-sm text-text-secondary hover:bg-surface-3 hover:text-text-primary transition-colors text-start active:scale-[0.97] focus-ring-soft"
        aria-expanded={isOpen}
        aria-controls={panelId}
      >
        <span className="h-6 w-6 shrink-0 inline-flex items-center justify-center text-base leading-none">
          <svg
            width="14" height="14" viewBox="0 0 14 14" fill="none"
            className={`shrink-0 transition-transform duration-150 ${isOpen ? 'rotate-90' : ''}`}
            aria-hidden="true"
          >
            <path d="M5 3L9.5 7L5 11" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </span>
        <span className="min-w-0 truncate leading-5">{t('nav.more')}</span>
      </button>
      {isOpen && (
        <div id={panelId} className="space-y-0.5">
          {renderSecondaryModules({
            modules: SECONDARY_MODULES,
            filter: (def) => canShowModule(def.module) && isModuleInToolbox(def.module),
            showDesktopFeatures,
            currentView,
            onNavigate,
            navShortcuts,
            t,
          })}
        </div>
      )}
    </>
  );
}
