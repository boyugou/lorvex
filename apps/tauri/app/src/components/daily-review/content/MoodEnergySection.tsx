import { useId, useMemo, useState } from 'react';

import type { TranslationKey } from '@/lib/i18n';
import { formatCalendarDateInTimeZone } from '@/lib/dates/dateLocale';
import type { DailyReviewController } from '../controller/useDailyReviewController';
import {
  DAILY_REVIEW_ENERGY_SCALE,
  DAILY_REVIEW_MOOD_SCALE,
  formatDailyReviewScaleAriaLabel,
} from '../controller/scaleMetadata.logic';
import { BoltIcon } from '@/components/ui/icons';

export function MoodEnergySection({ c }: { c: DailyReviewController }) {
  return (
    <section className="bg-surface-2 rounded-r-card border border-card overflow-hidden">
      <div className="px-5 py-3.5 border-b border-card flex items-center gap-2">
        <BoltIcon className="w-4 h-4 text-warning" />
        <h2 className="heading-section">{c.t('dailyReview.moodEnergy')}</h2>
      </div>

      <div className="px-5 py-4 space-y-5">
        <div>
          <p className="text-text-muted text-xs font-medium mb-2.5">{c.t('dailyReview.mood')}</p>
          <div className="flex gap-2">
            {DAILY_REVIEW_MOOD_SCALE.map(option => (
              <button
                key={option.value}
                type="button"
                onClick={() => { c.markDirty(); c.setMood(c.mood === option.value ? null : option.value); }}
                aria-label={formatDailyReviewScaleAriaLabel({
                  kind: 'mood',
                  locale: c.locale,
                  t: c.t,
                  value: option.value,
                })}
                aria-pressed={c.mood === option.value}
                className={`flex-1 flex flex-col items-center gap-1 py-2.5 rounded-r-card border transition-[color,background-color,border-color,box-shadow,transform] duration-150 active:scale-95 ${
                  c.mood === option.value
                    ? 'border-accent/50 bg-accent/8 ring-1 ring-accent/20 scale-105'
                    : 'border-card bg-surface-1/50 hover:border-surface-3 hover:bg-surface-1'
                }`}
              >
                <span className={`text-xl transition-transform duration-150 ${c.mood === option.value ? 'scale-110' : ''}`}>
                  {option.icon}
                </span>
              </button>
            ))}
          </div>
        </div>

        <div>
          <p className="text-text-muted text-xs font-medium mb-2.5">{c.t('dailyReview.energy')}</p>
          <div className="flex gap-2">
            {DAILY_REVIEW_ENERGY_SCALE.map(option => {
              const isActive = c.energy === option.value;
              return (
                <button
                  key={option.value}
                  type="button"
                  onClick={() => { c.markDirty(); c.setEnergy(isActive ? null : option.value); }}
                  aria-label={formatDailyReviewScaleAriaLabel({
                    kind: 'energy',
                    locale: c.locale,
                    t: c.t,
                    value: option.value,
                  })}
                  aria-pressed={isActive}
                  className={`flex-1 py-2 px-1 rounded-r-card border transition-[color,background-color,border-color,box-shadow,transform] duration-150 ${option.bg} ${
                    isActive
                      ? `scale-105 ring-1 ${option.activeRing} ${option.activeBorder}`
                      : 'border-card hover:border-surface-3'
                  }`}
                >
                  <span className={`block text-center text-3xs font-medium leading-tight ${
                    isActive ? 'text-text-primary' : 'text-text-muted'
                  }`}>
                    {c.t(option.labelKey)}
                  </span>
                </button>
              );
            })}
          </div>
        </div>

        {c.last7DaysTrend.length >= 2 && (
          <MiniTrend data={c.last7DaysTrend} locale={c.locale} timezone={c.timezone} t={c.t} />
        )}
      </div>
    </section>
  );
}

function MiniTrend({
  data,
  locale,
  timezone,
  t,
}: {
  data: { date: string; mood: number | null; energy: number | null }[];
  locale: string;
  timezone: string;
  t: (k: TranslationKey) => string;
}) {
  const dotSize = 6;
  const spacing = 32;
  const height = 40;
  const padding = 8;

  const moodDots = useMemo(() => {
    return data.map((d, i) => ({
      x: padding + i * spacing,
      y: d.mood != null ? padding + (height - padding * 2) - ((d.mood - 1) / 4) * (height - padding * 2) : null,
      value: d.mood,
      date: d.date,
    }));
  }, [data]);

  const energyDots = useMemo(() => {
    return data.map((d, i) => ({
      x: padding + i * spacing,
      y: d.energy != null ? padding + (height - padding * 2) - ((d.energy - 1) / 4) * (height - padding * 2) : null,
      value: d.energy,
      date: d.date,
    }));
  }, [data]);

  const width = padding * 2 + (data.length - 1) * spacing;
  // Today is the rightmost entry in the rolling 7-day window.
  const todayIndex = data.length - 1;
  // Median y-axis projection: collected from both series so the
  // reference line reads as a baseline across all logged days, not a
  // per-series median.
  const medianY = useMemo(() => {
    const values: number[] = [];
    for (const d of data) {
      if (d.mood != null) values.push(d.mood);
      if (d.energy != null) values.push(d.energy);
    }
    if (values.length === 0) return null;
    values.sort((a, b) => a - b);
    const mid = values.length / 2;
    let median: number;
    if (values.length % 2 === 0) {
      const lo = values[mid - 1] ?? 0;
      const hi = values[mid] ?? 0;
      median = (lo + hi) / 2;
    } else {
      median = values[Math.floor(mid)] ?? 0;
    }
    return padding + (height - padding * 2) - ((median - 1) / 4) * (height - padding * 2);
  }, [data]);

  // Build closed-area paths so a linear-gradient fill reads under each
  // line. Fall back to the line-only behaviour when fewer than 2 dots
  // are plottable.
  const moodArea = useMemo(() => buildAreaPath(moodDots.filter(d => d.y != null) as PlottedDot[], height - padding), [moodDots, padding, height]);
  const energyArea = useMemo(() => buildAreaPath(energyDots.filter(d => d.y != null) as PlottedDot[], height - padding), [energyDots, padding, height]);

  const formatLabel = (dateStr: string): string => {
    return formatCalendarDateInTimeZone(dateStr, locale, timezone, {
      weekday: 'short',
    });
  };

  // Hover state lives at the SVG level; a single tooltip surface
  // floats above whichever dot the pointer is over. Storing the
  // hovered index in state (rather than mixing SVG-native `<title>`
  // and a custom tooltip) keeps keyboard-focus parity straightforward.
  const [hoverIdx, setHoverIdx] = useState<number | null>(null);
  const moodGradId = useId();
  const energyGradId = useId();

  return (
    <div className="pt-2 border-t border-card">
      <p className="text-text-muted text-3xs font-medium mb-2">{t('dailyReview.last7days')}</p>
      <div className="relative overflow-x-auto">
        <svg
          width={width}
          height={height + 16}
          className="block"
          onMouseLeave={() => setHoverIdx(null)}
        >
          <defs>
            <linearGradient id={moodGradId} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="var(--warning-tint-sm)" />
              <stop offset="100%" stopColor="var(--warning-tint-sm)" stopOpacity="0" />
            </linearGradient>
            <linearGradient id={energyGradId} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="var(--accent-tint-sm)" />
              <stop offset="100%" stopColor="var(--accent-tint-sm)" stopOpacity="0" />
            </linearGradient>
          </defs>

          {/* Median reference gridline */}
          {medianY != null && (
            <line
              x1={padding}
              x2={width - padding}
              y1={medianY}
              y2={medianY}
              stroke="var(--color-surface-3)"
              strokeWidth="1"
              strokeDasharray="2 3"
              opacity="0.7"
            />
          )}

          {moodArea && <path d={moodArea} fill={`url(#${moodGradId})`} />}
          {energyArea && <path d={energyArea} fill={`url(#${energyGradId})`} />}

          {moodDots.filter(d => d.y != null).length >= 2 && (
            <path
              d={moodDots.filter(d => d.y != null).map((d, i) => `${i === 0 ? 'M' : 'L'}${d.x},${d.y!}`).join(' ')}
              fill="none"
              stroke="var(--color-warning)"
              strokeWidth="1.5"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          )}
          {energyDots.filter(d => d.y != null).length >= 2 && (
            <path
              d={energyDots.filter(d => d.y != null).map((d, i) => `${i === 0 ? 'M' : 'L'}${d.x},${d.y!}`).join(' ')}
              fill="none"
              stroke="var(--color-accent)"
              strokeWidth="1.5"
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeDasharray="4 2"
              opacity="0.7"
            />
          )}

          {moodDots.map((d, i) => d.y != null && (
            <g key={`m${i}`}>
              {i === todayIndex && (
                <circle
                  cx={d.x}
                  cy={d.y}
                  r={dotSize}
                  fill="none"
                  stroke="var(--color-warning)"
                  strokeOpacity="0.4"
                  className="motion-safe:animate-pulse"
                />
              )}
              <circle
                cx={d.x}
                cy={d.y}
                r={i === todayIndex ? (dotSize / 2) * 1.5 : dotSize / 2}
                fill="var(--color-warning)"
              />
            </g>
          ))}
          {energyDots.map((d, i) => d.y != null && (
            <g key={`e${i}`}>
              {i === todayIndex && (
                <circle
                  cx={d.x}
                  cy={d.y}
                  r={dotSize}
                  fill="none"
                  stroke="var(--color-accent)"
                  strokeOpacity="0.4"
                  className="motion-safe:animate-pulse"
                />
              )}
              <circle
                cx={d.x}
                cy={d.y}
                r={i === todayIndex ? (dotSize / 2) * 1.5 : dotSize / 2}
                fill="var(--color-accent)"
                opacity="0.85"
              />
            </g>
          ))}

          {/* Invisible hover targets — one wide column per data point
              so the user does not need to land precisely on a 6px dot. */}
          {data.map((d, i) => (
            // role="button" so keyboard tab carries an interactive
            // affordance; Enter/Space re-surfaces the tooltip (idempotent
            // with the onFocus path) and satisfies the button-activation
            // contract that role="img" would have violated.
            <rect
              key={`hit-${i}`}
              x={padding + i * spacing - spacing / 2}
              y={0}
              width={spacing}
              height={height}
              fill="transparent"
              onMouseEnter={() => setHoverIdx(i)}
              onFocus={() => setHoverIdx(i)}
              onBlur={() => setHoverIdx(null)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' || e.key === ' ') {
                  e.preventDefault();
                  setHoverIdx(i);
                }
              }}
              tabIndex={0}
              aria-label={tooltipLabel(d, formatLabel, t)}
              role="button"
            />
          ))}

          {data.map((d, i) => (
            <text
              key={`label-${i}`}
              x={padding + i * spacing}
              y={height + 12}
              textAnchor="middle"
              className="fill-text-muted/50"
              fontSize="8"
            >
              {formatLabel(d.date)}
            </text>
          ))}
        </svg>

        {hoverIdx != null && data[hoverIdx] && (
          <div
            role="tooltip"
            className="pointer-events-none absolute z-[var(--z-tooltip)] -translate-x-1/2 -translate-y-full rounded-r-control bg-surface-2 border border-card px-2 py-1 text-3xs text-text-primary shadow-[var(--shadow-tooltip)] animate-[fade-in_0.12s_ease-out]"
            style={{
              left: `${padding + hoverIdx * spacing}px`,
              top: `${(moodDots[hoverIdx]?.y ?? energyDots[hoverIdx]?.y ?? height / 2) - 6}px`,
            }}
          >
            <div className="font-medium">{formatLabel(data[hoverIdx].date)}</div>
            <div className="flex items-center gap-2 mt-0.5">
              <span className="flex items-center gap-1">
                <span className="w-1.5 h-1.5 rounded-full bg-warning inline-block" />
                <span className="tabular-nums">{data[hoverIdx].mood ?? '—'}</span>
              </span>
              <span className="flex items-center gap-1">
                <span className="w-1.5 h-1.5 rounded-full bg-accent inline-block" />
                <span className="tabular-nums">{data[hoverIdx].energy ?? '—'}</span>
              </span>
            </div>
          </div>
        )}
      </div>
      <div className="flex items-center gap-3 mt-1.5 text-3xs text-text-muted/60">
        <span className="flex items-center gap-1">
          <span className="w-3 h-0.5 rounded-r-control bg-warning inline-block" />
          {t('dailyReview.mood')}
        </span>
        <span className="flex items-center gap-1">
          <span className="w-3 inline-block" style={{ height: '2px', backgroundImage: 'linear-gradient(to right, var(--color-accent) 60%, transparent 40%)', backgroundSize: '6px 2px', backgroundRepeat: 'repeat-x' }} />
          {t('dailyReview.energy')}
        </span>
      </div>
    </div>
  );
}

type PlottedDot = { x: number; y: number; value: number | null; date: string };

/**
 * Closed SVG path that walks the line dots left-to-right and returns
 * to the baseline so the resulting shape can be filled with a vertical
 * linear gradient. Returns `null` when fewer than two plottable dots
 * exist (no area to fill).
 */
function buildAreaPath(dots: PlottedDot[], baselineY: number): string | null {
  if (dots.length < 2) return null;
  const first = dots[0]!;
  const last = dots[dots.length - 1]!;
  const line = dots.map((d, i) => `${i === 0 ? 'M' : 'L'}${d.x},${d.y}`).join(' ');
  return `${line} L${last.x},${baselineY} L${first.x},${baselineY} Z`;
}

function tooltipLabel(
  d: { date: string; mood: number | null; energy: number | null },
  formatLabel: (s: string) => string,
  t: (k: TranslationKey) => string,
): string {
  return `${formatLabel(d.date)} — ${t('dailyReview.mood')}: ${d.mood ?? '—'}, ${t('dailyReview.energy')}: ${d.energy ?? '—'}`;
}
