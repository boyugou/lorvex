import OnboardingChecklist from '../onboarding/OnboardingChecklist';

import ListSection from './ListSection';
import PrimaryNav from './PrimaryNav';
import SecondaryNav from './SecondaryNav';
import SidebarHeader from './SidebarHeader';
import UpdateBanner from './UpdateBanner';
import { type SidebarControllerState } from './useSidebarController';

interface SidebarContentProps {
  controller: SidebarControllerState;
}

export default function SidebarContent({ controller }: SidebarContentProps) {
  const {
    availableVersion,
    canShowModule,
    creatingList,
    currentView,
    handleCreateList,
    handleOpenReleaseNotes,
    isCreatingList,
    isModuleInToolbox,
    lists,
    navShortcuts,
    onNavigate,
    onOpenPalette,
    onQuickCapture,
    onWindowDragStart,
    quickCaptureShortcut,
    setCreatingList,
    showDesktopFeatures,
    stats,
    t,
    todayBadge,
    unseenErrorLogCount,
  } = controller;

  return (
    <aside className={`liquid-sidebar-shell profile-material-shell w-full min-h-0 flex-1 bg-surface-1/90 flex flex-col ${showDesktopFeatures ? '' : 'pt-6'} shrink-0`}>
      <SidebarHeader
        showDesktopFeatures={showDesktopFeatures}
        quickCaptureShortcut={quickCaptureShortcut}
        onQuickCapture={onQuickCapture}
        onOpenPalette={onOpenPalette}
        onWindowDragStart={onWindowDragStart}
        t={t}
      />

      {/* onboarding checklist sits between the sidebar
          header and the primary navigation. It auto-hides when every
          step is satisfied, re-surfaces on regression, and the user can
          dismiss it manually (the `?` Help button below brings it
          back). Placed above primary-nav so a brand-new user sees the
          scaffolded path before the navigation rows. */}
      <OnboardingChecklist
        onNavigate={onNavigate}
        onQuickCapture={onQuickCapture}
      />

      {/* `<nav aria-label>` promotes this region to a screen-reader
          landmark so users can jump straight to navigation (VoiceOver
          rotor, JAWS / NVDA landmark cycle). Keep the outer `<aside>` as
          the overall sidebar region because it also contains the header
          and the update banner, which aren't navigation. */}
      <nav
        aria-label={t('nav.primary')}
        className="flex-1 min-h-0 overflow-y-auto overflow-x-hidden overscroll-contain"
      >
      <PrimaryNav
        canShowModule={canShowModule}
        currentView={currentView}
        navShortcuts={navShortcuts}
        onNavigate={onNavigate}
        stats={stats}
        t={t}
        todayBadge={todayBadge}
      />

      {/* Dividers track the `px-2` nav inset (`mx-2`) so they
          line up with the `NavItem` row backgrounds rather than drifting
          inward by ~8px (the previous `mx-4` rendered a noticeable
          shoulder above and below each separator). */}
      <div className="mx-2 my-2.5 border-t border-card" />

      <ListSection
        lists={lists}
        currentView={currentView}
        creatingList={creatingList}
        isCreatingList={isCreatingList}
        onNavigate={onNavigate}
        handleCreateList={handleCreateList}
        setCreatingList={setCreatingList}
        t={t}
      />

      {/* Dividers track the `px-2` nav inset (`mx-2`) so they
          line up with the `NavItem` row backgrounds rather than drifting
          inward by ~8px (the previous `mx-4` rendered a noticeable
          shoulder above and below each separator). */}
      <div className="mx-2 my-2.5 border-t border-card" />

      <SecondaryNav
        availableVersion={availableVersion}
        canShowModule={canShowModule}
        currentView={currentView}
        isModuleInToolbox={isModuleInToolbox}
        navShortcuts={navShortcuts}
        onNavigate={onNavigate}
        showDesktopFeatures={showDesktopFeatures}
        t={t}
        unseenErrorLogCount={unseenErrorLogCount}
      />
      </nav>

      {showDesktopFeatures && availableVersion && (
        <UpdateBanner
          availableVersion={availableVersion}
          onOpenReleaseNotes={handleOpenReleaseNotes}
          t={t}
        />
      )}
    </aside>
  );
}
