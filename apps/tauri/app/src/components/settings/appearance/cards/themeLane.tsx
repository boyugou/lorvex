import type { ThemeMode, ThemeOption } from '@/lib/theme';
import { CheckIcon } from '@/components/ui/icons';
import type { TranslationKey } from '@/locales';
import { resolveThemePalette } from '../catalog';


export function ThemeOptionLane({
  title,
  options,
  activeMode,
  onSelect,
  translate,
}: {
  title: string;
  options: ThemeOption[];
  activeMode: ThemeMode;
  onSelect: (mode: ThemeMode) => void;
  translate: (key: TranslationKey) => string;
}) {
  if (options.length === 0) return null;

  return (
    <div className="space-y-2">
      <p className="text-xs font-medium text-text-muted">{title}</p>
      <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2 xl:grid-cols-3">
        {options.map((opt) => (
          <ThemeOptionCard
            key={opt.value}
            value={opt.value}
            label={translate(opt.labelKey)}
            selected={activeMode === opt.value}
            activeMode={activeMode}
            onSelect={() => onSelect(opt.value)}
          />
        ))}
      </div>
    </div>
  );
}

function ThemeOptionCard({
  value,
  label,
  selected,
  activeMode,
  onSelect,
}: {
  value: ThemeMode;
  label: string;
  selected: boolean;
  /// Currently active theme so the swatch for that theme can resolve
  /// canvas / panel / accent / text live from the document root's
  /// computed style (and never drift from a `themes.css` retune).
  activeMode: ThemeMode;
  onSelect: () => void;
}) {
  const isSystem = value === 'system';
  const resolvedActive: Exclude<ThemeMode, 'system'> =
    activeMode === 'system' ? 'light' : (activeMode as Exclude<ThemeMode, 'system'>);
  const palette = !isSystem
    ? resolveThemePalette(value as Exclude<ThemeMode, 'system'>, resolvedActive)
    : null;
  // Derive system preview swatches from the same registered palettes
  // the rest of the lane uses, so the half/half System chip cannot
  // drift from the actual `dark` and `light` previews when the dark
  // canvas is retuned.
  const darkPalette = resolveThemePalette('dark', resolvedActive);
  const lightPalette = resolveThemePalette('light', resolvedActive);

  return (
    <button
      type="button"
      onClick={onSelect}
      aria-pressed={selected}
      className={`group rounded-r-card border p-2.5 text-start transition-[color,background-color,border-color,box-shadow] focus-ring-strong ${
        selected
          ? 'border-accent bg-accent/8 ring-1 ring-accent/25'
          : 'border-card bg-surface-2/60 hover:border-accent/40 hover:bg-surface-2'
      }`}
    >
      <div className="flex items-center justify-between gap-2">
        <span className={`text-sm ${selected ? 'text-text-primary' : 'text-text-secondary group-hover:text-text-primary'}`}>
          {label}
        </span>
        <div className="flex items-center gap-1.5">
          {selected && <CheckIcon className="w-3.5 h-3.5 text-accent" />}
        </div>
      </div>

      {isSystem ? (
        <div className="mt-2.5 grid grid-cols-2 overflow-hidden rounded-r-control border border-card">
          <div className="p-2" style={{ background: darkPalette.canvas }}>
            <div className="h-1.5 w-7 rounded-full" style={{ background: darkPalette.accent }} />
            <div
              className="mt-1.5 h-1.5 w-10 rounded-full"
              style={{ background: `color-mix(in oklch, ${darkPalette.text} 72%, transparent)` }}
            />
          </div>
          <div className="border-s border-card p-2" style={{ background: lightPalette.canvas }}>
            <div className="h-1.5 w-7 rounded-full" style={{ background: lightPalette.accent }} />
            <div
              className="mt-1.5 h-1.5 w-10 rounded-full"
              style={{ background: `color-mix(in oklch, ${lightPalette.text} 60%, transparent)` }}
            />
          </div>
        </div>
      ) : (
        <div
          className="mt-2.5 rounded-r-control border border-popover p-2"
          style={{ background: `linear-gradient(150deg, ${palette!.canvas}, ${palette!.panel})` }}
        >
          {/* traffic-light dots use the palette's text color at
              three alpha tiers via OKLCH-space color-mix so they remain
              visible on both light and dark canvases. Pre-fix the alpha
              was a raw hex-suffix string (`${text}66`) which silently
              fails on any non-hex palette source (e.g. an oklch palette
              entry) and breaks for css-var palette inputs. */}
          <div className="flex items-center gap-1">
            <span
              className="h-1.5 w-1.5 rounded-full"
              style={{ background: `color-mix(in oklch, ${palette!.text} 40%, transparent)` }}
            />
            <span
              className="h-1.5 w-1.5 rounded-full"
              style={{ background: `color-mix(in oklch, ${palette!.text} 30%, transparent)` }}
            />
            <span
              className="h-1.5 w-1.5 rounded-full"
              style={{ background: `color-mix(in oklch, ${palette!.text} 20%, transparent)` }}
            />
          </div>
          <div className="mt-2 h-1.5 w-12 rounded-full" style={{ background: palette!.accent }} />
          <div
            className="mt-1.5 h-1.5 w-20 rounded-full"
            style={{ background: `color-mix(in oklch, ${palette!.text} 72%, transparent)` }}
          />
          <div
            className="mt-1 h-1.5 w-14 rounded-full"
            style={{ background: `color-mix(in oklch, ${palette!.text} 53%, transparent)` }}
          />
        </div>
      )}
    </button>
  );
}
