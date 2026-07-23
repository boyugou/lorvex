import { useI18n } from '@/lib/i18n';
import { Bar } from '@/components/ui/SkeletonShimmer';

/**
 * Loading scaffold for `SettingsView`. Mirrors the real view's
 * two-pane layout (160px nav rail + scrollable content) so the chrome
 * does not jump when the loaded view replaces the skeleton. The
 * shimmer fades to a static surface under `prefers-reduced-motion`
 * via the `Bar` primitive.
 */
export function SettingsViewSkeleton() {
  const { t } = useI18n();
  return (
    <div
      className="h-full min-h-0 px-4 sm:px-8"
      role="status"
      aria-label={t('settings.loading')}
    >
      <div className="h-full rounded-r-panel border border-surface-3 bg-surface-2/20 overflow-hidden">
        <div className="h-full min-h-0 grid grid-cols-[160px_minmax(0,1fr)] animate-pulse">
          {/* Left nav rail: 5-6 section labels */}
          <div className="border-e border-surface-3 px-3 py-4 space-y-2">
            {Array.from({ length: 6 }).map((_, i) => (
              <Bar key={i} className="h-5 w-24" />
            ))}
          </div>
          {/* Right pane: alternating section headers + form rows */}
          <div className="overflow-hidden px-4 pe-3 py-4 space-y-6">
            {Array.from({ length: 3 }).map((_, section) => (
              <div key={section} className="space-y-3">
                <Bar className="h-5 w-40" />
                <Bar className="h-4 w-3/4" />
                <div className="space-y-2 pt-1">
                  <Bar className="h-9 w-full rounded-r-control" />
                  <Bar className="h-9 w-full rounded-r-control" />
                </div>
                {section < 2 ? (
                  <div className="border-t border-surface-3/60 mt-3 pt-3" />
                ) : null}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
