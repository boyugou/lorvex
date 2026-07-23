import type { ReactNode } from 'react';
import { useCallback, useEffect, useState } from 'react';

import {
  reconcileDailyReviewReflectionExpansionState,
  toggleDailyReviewReflectionSection,
  type DailyReviewReflectionSectionKey,
} from '../controller/controller.logic';
import type { DailyReviewController } from '../controller/useDailyReviewController';
import { AutosizingTextarea } from '@/components/ui/AutosizingTextarea';
import { CollapsibleSection } from '@/components/ui/CollapsibleSection';
import { BarrierIcon, CheckIcon, LightbulbIcon, NotebookIcon } from '@/components/ui/icons';

export function ReflectionSection({ c }: { c: DailyReviewController }) {
  const [expandedState, setExpandedState] = useState(() => c.reflectionExpansion);

  useEffect(() => {
    setExpandedState((previous) => reconcileDailyReviewReflectionExpansionState(
      previous,
      c.reflectionExpansion,
    ));
  }, [c.reflectionExpansion]);

  const toggleSection = useCallback((key: DailyReviewReflectionSectionKey) => {
    setExpandedState(prev => toggleDailyReviewReflectionSection(prev, key));
  }, []);

  const completedTitles = c.showTodayScopedInsights
    ? c.daySummary.completedTasks.slice(0, 5).map(t => t.title)
    : [];

  return (
    <section className="bg-surface-2 rounded-r-card border border-card overflow-hidden">
      <div className="px-5 py-3.5 border-b border-card flex items-center gap-2">
        <NotebookIcon className="w-4 h-4 text-accent" />
        <h2 className="heading-section">{c.t('dailyReview.reflection')}</h2>
      </div>

      <div className="divide-y divide-surface-3/30">
        <div className="px-5 py-4">
          <label htmlFor="review-summary" className="block text-text-muted text-xs font-medium mb-1.5">
            {c.t('dailyReview.summary')} <span className="text-danger">*</span>
          </label>
          <AutosizingTextarea
            id="review-summary"
            value={c.summary}
            onChange={e => {
              c.markDirty();
              c.setSummary(e.target.value);
              if (e.target.value.trim()) c.setShowValidation(false);
            }}
            placeholder={c.t('dailyReview.summaryPlaceholder')}
            minRows={3}
            maxRows={10}
            data-theme-form-control="true"
            className={`w-full bg-surface-1 border rounded-r-card p-3 text-sm text-text-primary outline-hidden focus-ring-soft transition-colors ${
              c.showValidation && !c.summary.trim() ? 'border-danger/60' : 'border-surface-3'
            }`}
          />
          {c.showValidation && !c.summary.trim() && (
            <p className="text-danger text-xs mt-1">{c.t('dailyReview.summaryRequired')}</p>
          )}
        </div>

        <CollapsibleReflection
          id="review-wins"
          icon={<CheckIcon className="w-3.5 h-3.5 text-success" />}
          title={c.t('dailyReview.whatWentWell')}
          expanded={expandedState.sections.wins}
          onToggle={() => toggleSection('wins')}
          value={c.wins}
          onChange={v => { c.markDirty(); c.setWins(v); }}
          placeholder={c.t('dailyReview.winsPlaceholder')}
          chips={completedTitles}
          onChipClick={chip => {
            c.markDirty();
            c.setWins(prev => prev ? `${prev}\n- ${chip}` : `- ${chip}`);
          }}
        />

        <CollapsibleReflection
          id="review-blockers"
          icon={<BarrierIcon className="w-3.5 h-3.5 text-warning" />}
          title={c.t('dailyReview.whatWasChallenging')}
          expanded={expandedState.sections.blockers}
          onToggle={() => toggleSection('blockers')}
          value={c.blockers}
          onChange={v => { c.markDirty(); c.setBlockers(v); }}
          placeholder={c.t('dailyReview.blockersPlaceholder')}
        />

        <CollapsibleReflection
          id="review-learnings"
          icon={<LightbulbIcon className="w-3.5 h-3.5 text-accent" />}
          title={c.t('dailyReview.whatDidILearn')}
          expanded={expandedState.sections.learnings}
          onToggle={() => toggleSection('learnings')}
          value={c.learnings}
          onChange={v => { c.markDirty(); c.setLearnings(v); }}
          placeholder={c.t('dailyReview.learningsPlaceholder')}
        />
      </div>
    </section>
  );
}

function CollapsibleReflection({
  id,
  icon,
  title,
  expanded,
  onToggle,
  value,
  onChange,
  placeholder,
  chips,
  onChipClick,
}: {
  id: string;
  icon: ReactNode;
  title: string;
  expanded: boolean;
  onToggle: () => void;
  value: string;
  onChange: (v: string) => void;
  placeholder: string;
  chips?: string[];
  onChipClick?: (chip: string) => void;
}) {
  return (
    <div className="px-5 py-3.5">
      <button
        type="button"
        onClick={onToggle}
        className="flex items-center gap-2 w-full text-start group focus-ring-soft rounded-r-control"
        aria-expanded={expanded}
      >
        <span className={`text-text-muted text-xs transition-transform duration-150 ${expanded ? 'rotate-90' : ''}`}>
          ›
        </span>
        <span className="inline-flex w-3.5 h-3.5 shrink-0">{icon}</span>
        <span className="text-text-secondary text-xs font-medium">{title}</span>
        {!expanded && value && (
          <span className="text-text-muted text-3xs ms-auto truncate max-w-[200px]">
            {value.split('\n')[0]}
          </span>
        )}
      </button>

      <CollapsibleSection collapsed={!expanded}>
        <div className="pt-2.5">
          {chips && chips.length > 0 && onChipClick && (
            <div className="flex flex-wrap gap-1.5 mb-2.5">
              {chips.map((chip, i) => (
                // Suggestion chips are dynamic — entries can be
                // added / removed / reordered between renders, so an
                // index key would retain DOM state (focus, animation)
                // on the wrong row when the list mutates. The chip
                // text is unique within one row in this UI; the
                // `${chip}-${i}` fallback handles the rare duplicate
                // case.
                <button
                  key={`${chip}-${i}`}
                  type="button"
                  onClick={() => onChipClick(chip)}
                  className="px-2.5 py-1 rounded-full chip-success-subtle chip-success-interactive text-2xs focus-ring-soft-success truncate max-w-[200px]"
                >
                  {chip}
                </button>
              ))}
            </div>
          )}
          <AutosizingTextarea
            id={id}
            value={value}
            onChange={e => onChange(e.target.value)}
            placeholder={placeholder}
            minRows={3}
            maxRows={10}
            data-theme-form-control="true"
            className="w-full bg-surface-1 border border-surface-3 rounded-r-card p-3 text-sm text-text-primary outline-hidden transition-colors focus-ring-soft focus-visible:border-accent/30"
          />
        </div>
      </CollapsibleSection>
    </div>
  );
}
