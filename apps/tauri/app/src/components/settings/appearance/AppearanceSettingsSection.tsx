import { useCallback } from 'react';
import {
  APPEARANCE_PROFILE_OPTIONS,
  THEME_OPTIONS,
  useTheme,
  type AppearanceProfile,
  type ThemeMode,
} from '@/lib/theme';
import {
  DEFAULT_APPEARANCE_PROFILE,
  DEFAULT_THEME_MODE,
  normalizeAppearanceProfile,
  normalizeThemeMode,
} from '@/lib/theme/model';
import { usePreferenceMutationWithUndo } from '@/lib/hooks/usePreferenceMutationWithUndo';
import { useI18n } from '@/lib/i18n';
import { localeTextDirection, type LocaleTextDirection } from '@/locales/registry';
import { PREF_APPEARANCE_PROFILE, PREF_FONT_SCALE, PREF_THEME } from '@/lib/preferences/keys';
import { useFontScale, FONT_SCALE_OPTIONS } from '@/lib/useFontScale';
import { APPEARANCE_DEFAULT_KEYS } from '@/lib/preferences/defaults';
import type { TranslationKey } from '@/locales';
import { RestoreDefaultsButton } from '../RestoreDefaultsButton';
import { SettingsSection } from '../SettingsPrimitives';
import { ThemeOptionLane } from './cards/themeLane';
import { resolveSliderTrackBackground } from '@/components/ui/sliderGeometry.logic';

/** Slider-style font scale control with discrete snap points (like macOS/WeChat). */
function FontScaleSlider({ scale, setScale, t, textDirection }: {
  scale: number;
  setScale: (v: number) => void;
  t: (key: TranslationKey) => string;
  textDirection: LocaleTextDirection;
}) {
  const currentIndex = FONT_SCALE_OPTIONS.findIndex((o) => o.value === scale);
  const activeIdx = currentIndex >= 0 ? currentIndex : 2;
  const lastStop = FONT_SCALE_OPTIONS.length - 1;
  const fillPct = (activeIdx / lastStop) * 100;

  const handleChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const idx = Number(e.target.value);
    const opt = FONT_SCALE_OPTIONS[idx];
    if (opt) setScale(opt.value);
  }, [setScale]);

  return (
    <div className="space-y-2">
      <div className="flex items-center gap-3">
        {/* Small A — fixed px so it doesn't scale with the setting */}
        <span className="text-2xs text-text-muted shrink-0 w-5 text-center font-medium select-none">A</span>
        <div className="flex-1 relative px-[11px]">
          <input
            data-testid="settings-font-scale-slider"
            type="range"
            min={0}
            max={lastStop}
            step={1}
            value={activeIdx}
            onChange={handleChange}
            dir={textDirection}
            className="w-full h-1.5 appearance-none rounded-full cursor-pointer
              [&::-webkit-slider-thumb]:appearance-none
              [&::-webkit-slider-thumb]:w-[22px] [&::-webkit-slider-thumb]:h-[22px]
              [&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:bg-surface-1
              [&::-webkit-slider-thumb]:border-2 [&::-webkit-slider-thumb]:border-accent
              [&::-webkit-slider-thumb]:shadow-[var(--shadow-tooltip)] [&::-webkit-slider-thumb]:cursor-grab
              [&::-webkit-slider-thumb]:active:cursor-grabbing
              [&::-webkit-slider-thumb]:active:scale-110
              [&::-webkit-slider-thumb]:transition-[transform,box-shadow] [&::-webkit-slider-thumb]:duration-150
              [&::-webkit-slider-thumb]:hover:shadow-[var(--shadow-popover)]
              focus-ring-soft rounded-full"
            style={{
              background: resolveSliderTrackBackground({
                fillPercent: fillPct,
                textDirection,
              }),
            }}
            aria-label={t('settings.fontSize')}
            aria-valuetext={t(FONT_SCALE_OPTIONS[activeIdx]?.labelKey ?? 'settings.fontScaleDefault')}
          />
          {/* Tick marks aligned to slider stops. */}
          <div className="relative h-3 mt-1">
            {FONT_SCALE_OPTIONS.map((opt, i) => (
              <div
                key={opt.value}
                className="cv-inline-center absolute flex flex-col items-center"
                style={{ insetInlineStart: `${(i / lastStop) * 100}%` }}
              >
                <div className={`w-1 h-1 rounded-full transition-colors duration-150 ${
                  i === activeIdx ? 'bg-accent' : 'bg-text-muted/30'
                }`} />
              </div>
            ))}
          </div>
        </div>
        {/* Large A — fixed px */}
        <span className="text-xl text-text-muted shrink-0 w-5 text-center font-medium select-none">A</span>
      </div>

      {/* Current value label + optional reset */}
      <div className="flex items-center justify-center gap-2">
        <p className="text-xs text-text-muted">
          {t(FONT_SCALE_OPTIONS[activeIdx]?.labelKey ?? 'settings.fontScaleDefault')}
        </p>
        {scale !== 1.0 && (
          <button
            type="button"
            onClick={() => setScale(1.0)}
            className="text-xs text-accent hover:text-accent/80 transition-colors rounded-r-control focus-ring-soft"
          >
            {t('settings.fontScaleReset')}
          </button>
        )}
      </div>
    </div>
  );
}

export function AppearanceSettingsSection() {
  const { t, locale } = useI18n();
  const {
    mode,
    setMode,
    appearanceProfile,
    setAppearanceProfile,
  } = useTheme();
  const { scale, setScale } = useFontScale();
  const textDirection = localeTextDirection(locale);

  // wrap theme and font-scale writes with a success
  // toast + Undo button. Theme selection updates the provider state
  // optimistically without persisting; `runThemeUndo` is the single
  // persistence path, so its snapshot cannot race a provider write.
  const { run: runThemeUndo } = usePreferenceMutationWithUndo({
    key: PREF_THEME,
    errorKeyPrefix: 'settings.appearance.theme',
    onUndoValue: (previousValue) => {
      const previousMode = typeof previousValue === 'string'
        ? normalizeThemeMode(previousValue)
        : null;
      setMode(previousMode ?? DEFAULT_THEME_MODE, { persist: false });
    },
  });
  const { run: runProfileUndo } = usePreferenceMutationWithUndo({
    key: PREF_APPEARANCE_PROFILE,
    errorKeyPrefix: 'settings.appearance.profile',
    onUndoValue: (previousValue) => {
      const previousProfile = typeof previousValue === 'string'
        ? normalizeAppearanceProfile(previousValue)
        : null;
      setAppearanceProfile(previousProfile ?? DEFAULT_APPEARANCE_PROFILE, { persist: false });
    },
  });
  const { run: runScaleUndo } = usePreferenceMutationWithUndo({
    key: PREF_FONT_SCALE,
    errorKeyPrefix: 'settings.appearance.fontScale',
  });

  const handleSelectMode = useCallback((nextMode: ThemeMode) => {
    if (nextMode === mode) return;
    setMode(nextMode, { persist: false });
    void runThemeUndo(nextMode);
  }, [mode, setMode, runThemeUndo]);

  const handleSelectProfile = useCallback((nextProfile: AppearanceProfile) => {
    if (nextProfile === appearanceProfile) return;
    setAppearanceProfile(nextProfile, { persist: false });
    void runProfileUndo(nextProfile);
  }, [appearanceProfile, setAppearanceProfile, runProfileUndo]);

  const handleSelectScale = useCallback((nextScale: number) => {
    if (nextScale === scale) return;
    setScale(nextScale);
    void runScaleUndo(nextScale);
  }, [scale, setScale, runScaleUndo]);

  const darkThemes = THEME_OPTIONS.filter((opt) => opt.tone === 'dark');
  const lightThemes = THEME_OPTIONS.filter((opt) => opt.tone === 'light');
  const systemThemes = THEME_OPTIONS.filter((opt) => opt.tone === 'system');

  return (
    <>
      <SettingsSection title={t('settings.theme')} description={t('settings.themeDesc')}>
        <div className="space-y-4">
          <ThemeOptionLane
            title={t('settings.themeLaneDark')}
            options={darkThemes}
            activeMode={mode}

            onSelect={handleSelectMode}
            translate={t}
          />
          <ThemeOptionLane
            title={t('settings.themeLaneLight')}
            options={lightThemes}
            activeMode={mode}

            onSelect={handleSelectMode}
            translate={t}
          />
          <ThemeOptionLane
            title={t('settings.themeLaneSystem')}
            options={systemThemes}
            activeMode={mode}

            onSelect={handleSelectMode}
            translate={t}
          />

          <div className="flex flex-wrap items-center gap-2 pt-2 border-t border-surface-3">
            <button
              type="button"
              onClick={() => handleSelectMode('system')}
              className="text-xs px-3 py-1.5 rounded-r-control bg-surface-1 border border-surface-3 text-text-secondary hover:bg-surface-3 transition-colors focus-ring-soft"
            >
              {t('settings.themeResetSystem')}
            </button>
            {/* per-category Restore Defaults. Rolls back theme,
                appearance profile, and font scale as a single bundle
                with a shared Undo toast. */}
            <RestoreDefaultsButton
              keys={APPEARANCE_DEFAULT_KEYS}
              categoryLabel={t('settings.restoreDefaultsAppearance')}
              errorKeyPrefix="settings.appearance.restoreDefaults"
            />
          </div>

          <div className="pt-2 border-t border-surface-3">
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
              {APPEARANCE_PROFILE_OPTIONS.map((option) => {
                const active = option.value === appearanceProfile;
                return (
                  <button
                    key={option.value}
                    type="button"
                    aria-pressed={active}
                    onClick={() => handleSelectProfile(option.value)}
                    className={`min-h-9 rounded-r-control border px-3 py-2 text-sm font-medium transition-colors focus-ring-soft ${
                      active
                        ? 'border-accent bg-accent/10 text-accent'
                        : 'border-surface-3 bg-surface-1 text-text-secondary hover:bg-surface-2 hover:text-text-primary'
                    }`}
                  >
                    {t(option.labelKey)}
                  </button>
                );
              })}
            </div>
          </div>
        </div>
      </SettingsSection>
      <SettingsSection title={t('settings.fontSize')} description={t('settings.fontSizeDesc')}>
        <FontScaleSlider
          scale={scale}
          setScale={handleSelectScale}
          t={t}
          textDirection={textDirection}
        />
      </SettingsSection>
    </>
  );
}
