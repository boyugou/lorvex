import { useMemo, useState, type KeyboardEvent } from 'react';
import { useI18n, type TranslationKey } from '@/lib/i18n';
import { isImeComposing } from '@/lib/ime';

interface SettingsNavSection {
  id: string;
  label: string;
  /**
   * Free-form keyword index used by the section-search input. Each
   * section ships a small bag of synonyms (e.g. "appearance" matches
   * "theme", "color", "font") so a user who types the noun they care
   * about lands on the right section even when the section's display
   * label uses a different word. The list is intentionally short —
   * curated, not exhaustive — and trimmed/lowercased before matching.
   */
  keywords?: readonly string[];
}

interface SettingsScrollSpyNavProps {
  sections: SettingsNavSection[];
  activeSection: string;
  onNavigate: (sectionId: string) => void;
  usesMobileLayout: boolean;
}

/**
 * Keyword aliases per section. Mapped by section id so the parent
 * doesn't have to recompute them; the section labels themselves are
 * already matched, this only adds extra "synonym → section" hops for
 * concepts the user is more likely to type than the canonical label.
 * Translation keys (not literal strings) so the index follows locale.
 */
const SECTION_KEYWORD_KEYS: Record<string, readonly TranslationKey[]> = {
  'settings-section-general': [
    'settings.timezone',
    'settings.weeklyReviewDay',
    'settings.workingHours',
    'settings.advanced',
    'settings.aiBriefing',
  ],
  'settings-section-appearance': [
    'settings.appearanceProfileClarity',
    'settings.appearanceProfileLiquidGlass',
    'settings.appearanceProfileStudio',
    'settings.appearanceProfileFocusCompact',
  ],
  'settings-section-sync': [
    'settings.sync',
  ],
  'settings-section-mcp': [
    'settings.mcpConnect',
  ],
  'settings-section-calendar': [
    'settings.calendar',
    'settings.calendarSubscriptions',
  ],
  'settings-section-data': [
    'settings.scopeData',
    'settings.about',
    'settings.changelogRetention',
    'settings.dangerGroupReset',
  ],
};

export function SettingsScrollSpyNav({
  sections,
  activeSection,
  onNavigate,
  usesMobileLayout,
}: SettingsScrollSpyNavProps) {
  const { t } = useI18n();
  const [query, setQuery] = useState('');
  const trimmed = query.trim().toLowerCase();

  // Build the matchable haystack once per render: the section's
  // display label plus the resolved keyword aliases for that id. Keys
  // that don't exist in the locale fall back to the raw key string —
  // a missing entry yields an empty match rather than a runtime
  // throw, which keeps the search resilient as labels rename.
  const haystack = useMemo(() => {
    return sections.map((section) => {
      const keywordKeys = SECTION_KEYWORD_KEYS[section.id] ?? [];
      const aliasText = keywordKeys
        .map((key) => {
          try {
            return t(key).toLowerCase();
          } catch {
            return '';
          }
        })
        .join(' ');
      return {
        section,
        text: `${section.label.toLowerCase()} ${aliasText}`,
      };
    });
  }, [sections, t]);

  const filtered = useMemo(() => {
    if (!trimmed) return haystack.map(({ section }) => section);
    return haystack
      .filter(({ text }) => text.includes(trimmed))
      .map(({ section }) => section);
  }, [haystack, trimmed]);

  const handleKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (isImeComposing(event)) return;
    if (event.key !== 'Enter') return;
    event.preventDefault();
    const first = filtered[0];
    if (first) {
      onNavigate(first.id);
    }
  };

  return (
    <aside className={`${usesMobileLayout ? 'border-b border-popover' : 'border-e border-popover overflow-y-auto'} bg-surface-1/40 p-3`}>
      <div className={`sticky top-0 flex flex-col gap-2 ${usesMobileLayout ? '' : ''}`}>
        <label className="block">
          <span className="sr-only">{t('settings.searchSectionsLabel')}</span>
          <input
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={t('settings.searchSectionsPlaceholder')}
            // the search lives above a scroll-spy nav, not a
            // tablist; the input narrows what's visible in the nav
            // (and on Enter, jumps to the first match). The combobox
            // pattern isn't a fit because we don't expose a popup of
            // suggestions — the nav itself is the result surface.
            aria-label={t('settings.searchSectionsLabel')}
            className="w-full bg-surface-1 border border-card rounded-r-control px-2.5 py-1 text-xs text-text-primary placeholder:text-text-muted focus-ring-soft"
          />
        </label>
        <nav
          aria-label={t('settings.sectionsNav')}
          className={`gap-2 ${usesMobileLayout ? 'flex flex-wrap' : 'flex flex-col'}`}
        >
          {filtered.length === 0 ? (
            <p className="text-text-muted text-2xs px-1 py-2 italic">
              {t('settings.searchSectionsNoResults')}
            </p>
          ) : (
            filtered.map((section) => {
              const isActive = activeSection === section.id;
              return (
                <button
                  key={section.id}
                  type="button"
                  onClick={() => onNavigate(section.id)}
                  // this list is structurally a `<nav>` of
                  // section anchors (scroll-spy), not a tablist — there's no
                  // `tabpanel` swap, all sections render in one scroll
                  // container. The right ARIA cue is `aria-current="location"`
                  // on the active item so SR users hear "current location"
                  // instead of having to infer activity from color alone.
                  aria-current={isActive ? 'location' : undefined}
                  className={`text-start rounded-r-card border px-3 py-2 transition-[color,background-color,border-color,box-shadow,transform] duration-150 active:scale-[0.97] focus-ring-soft ${
                    isActive
                      ? 'bg-[var(--accent-tint-sm)] border-accent/30 text-accent shadow-[var(--shadow-tooltip)]'
                      : 'bg-transparent border-transparent text-text-secondary hover:bg-surface-2 hover:border-surface-3'
                  }`}
                >
                  <p className="text-xs font-medium">{section.label}</p>
                </button>
              );
            })
          )}
        </nav>
      </div>
    </aside>
  );
}
