import { getRuntimeProfile } from '@/lib/platform/platform';
import type { TranslationKey } from '@/lib/i18n';
import { formatShortcut } from '@/lib/shortcuts';
import { useNetworkStatus } from '@/lib/useNetworkStatus';
import { Button } from '../ui/Button';
import { Pill } from '../ui/Pill';
import { Tooltip } from '../ui/Tooltip';

const runtimeProfile = getRuntimeProfile();

interface SidebarHeaderProps {
  showDesktopFeatures: boolean;
  quickCaptureShortcut: string;
  onQuickCapture: () => void;
  onOpenPalette?: (() => void) | undefined;
  onWindowDragStart: (() => void) | undefined;
  t: (key: TranslationKey) => string;
}

export default function SidebarHeader({
  showDesktopFeatures,
  quickCaptureShortcut,
  onQuickCapture,
  onOpenPalette,
  onWindowDragStart,
  t,
}: SidebarHeaderProps) {
  const captureTitle = showDesktopFeatures
    ? `${t('capture.addTask')} (${quickCaptureShortcut})`
    : t('capture.addTask');
  // fix-direction #3: a permanent ⌘K affordance in the
  // sidebar header. Previously, the only way to discover the
  // command palette was the menu accelerator or the keyboard
  // shortcut panel — invisible to first-time users. Surfacing it
  // next to the quick-capture button makes the palette the second
  // most prominent interaction in the sidebar, matching how often
  // power users reach for it.
  const paletteShortcut = formatShortcut(['Mod', 'K']);
  const paletteTitle = showDesktopFeatures
    ? `${t('shortcuts.commandPalette')} (${paletteShortcut})`
    : t('shortcuts.commandPalette');

  // when the browser reports offline we surface an inline
  // badge next to the app title so the user has one stable, always-
  // visible place to see "sync is paused because I'm offline, not
  // because something is broken." The Sync settings screen has its own
  // offline hint on the Sync Now button; this is the global signal.
  const { online } = useNetworkStatus();

  return (
    <>
      {showDesktopFeatures && (
        // Tauri title-bar drag region — window-chrome affordance.
        // eslint-disable-next-line jsx-a11y/no-static-element-interactions
        <div
          className={`shrink-0 ${runtimeProfile.supportsTitleBarOverlay ? 'h-10' : 'h-2'}`}
          data-tauri-drag-region={showDesktopFeatures ? true : undefined}
          onMouseDown={(event) => { if (event.button === 0 && onWindowDragStart) onWindowDragStart(); }}
        />
      )}
      {/* Sidebar header band doubles as a Tauri drag region on desktop;
          inner buttons are separately interactive. */}
      {/* eslint-disable-next-line jsx-a11y/no-static-element-interactions */}
      <div
        className="px-4 pb-4 flex items-center justify-between gap-2"
        data-tauri-drag-region={showDesktopFeatures ? true : undefined}
        onMouseDown={showDesktopFeatures ? (event) => { if (event.button === 0 && onWindowDragStart) onWindowDragStart(); } : undefined}
      >
        <div className="flex items-center gap-2 min-w-0">
          <span className="text-text-primary font-semibold text-sm tracking-wide">Lorvex</span>
          {!online && (
            <Tooltip label={t('settings.syncOfflineTooltip')}>
              <Pill
                tone="warning"
                size="sm"
                role="status"
                aria-label={t('settings.syncOffline')}
                onMouseDown={(event) => event.stopPropagation()}
                className="border border-warning/30"
              >
                <OfflineIcon />
                {t('settings.syncOffline')}
              </Pill>
            </Tooltip>
          )}
        </div>
        <div className="flex items-center gap-1.5">
          {onOpenPalette && (
            <Tooltip label={paletteTitle}>
              {/* canonical `monoChip` size carries the 36×36 +
                  text-3xs font-mono recipe so the ⌘K glyph reads as a
                  keystroke. Folded into Button.tsx (#3814) replacing the
                  prior className override stack. */}
              <Button
                variant="outline"
                size="monoChip"
                onClick={onOpenPalette}
                onMouseDown={(event) => event.stopPropagation()}
                aria-label={paletteTitle}
              >
                <PaletteSearchIcon />
                {showDesktopFeatures && (
                  <span aria-hidden="true">{paletteShortcut}</span>
                )}
              </Button>
            </Tooltip>
          )}
          <Tooltip label={captureTitle}>
            <button
              type="button"
              onClick={onQuickCapture}
              onMouseDown={(event) => event.stopPropagation()}
              className="min-tap p-2.5 rounded-r-control bg-accent/20 hover:bg-accent/40 active:scale-[0.97] text-accent flex items-center justify-center text-lg leading-none transition-colors focus-ring-soft"
              aria-label={captureTitle}
            >
              +
            </button>
          </Tooltip>
        </div>
      </div>
    </>
  );
}

// Inline magnifying-glass glyph for the ⌘K affordance. Inlining (vs.
// pulling in the shared icon component) keeps the sidebar header
// lean — it would otherwise be the only consumer of `SearchIcon`
// in this file.
function PaletteSearchIcon() {
  return (
    <svg
      width="11"
      height="11"
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      aria-hidden="true"
    >
      <circle cx="7" cy="7" r="5" />
      <path d="M11 11L14 14" />
    </svg>
  );
}

// Inline cloud-with-slash glyph. Inlining (vs. pulling in a lucide-react
// icon component) keeps the hot path cheap and avoids a bundle import
// just for the offline badge.
function OfflineIcon() {
  return (
    <svg
      width="10"
      height="10"
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M4.5 13.5h7a3 3 0 0 0 .6-5.94A4 4 0 0 0 5 6.5" />
      <line x1="2" y1="2" x2="14" y2="14" />
    </svg>
  );
}
