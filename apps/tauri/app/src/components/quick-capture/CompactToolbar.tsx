import { CalendarDayIcon } from '../ui/icons';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { useI18n } from '@/lib/i18n';
import { DatePills } from './toolbar/DatePills';
import { InlineDetectedDateChip } from './toolbar/DetectedDateChip';
import { DurationDropdown } from './toolbar/DurationDropdown';
import { PriorityDropdown } from './toolbar/PriorityDropdown';
import { TagsToggle } from './toolbar/TagsToggle';
import type { CompactToolbarProps } from './toolbar/types';

export default function CompactToolbar(props: CompactToolbarProps) {
  const { locale } = useI18n();
  const dayContext = useConfiguredDayContext();
  const {
    dateOption, customDate, setCustomDate, setDateOption, toggleDateOption, clearDate,
    activeNlDate, clearNlDate,
    priority, togglePriority, clearPriority,
    estimatedMinutes, setEstimatedMinutes, toggleDuration, clearDuration,
    tagsInput, setTagsInput,
    t,
  } = props;

  return (
    <div className="px-4 pb-2">
      <div className="flex items-center gap-1 flex-wrap rounded-r-control bg-surface-3/40 px-3 py-2">
        {/* Date preset pills */}
        <CalendarDayIcon className="w-3.5 h-3.5 text-text-muted shrink-0" />
        <DatePills
          dateOption={dateOption}
          customDate={customDate}
          setCustomDate={setCustomDate}
          setDateOption={setDateOption}
          toggleDateOption={toggleDateOption}
          clearDate={clearDate}
          t={t}
        />

        {/* Separator */}
        <div className="w-px h-4 bg-surface-3/80 mx-1 shrink-0" />

        {/* Priority dropdown */}
        <PriorityDropdown
          priority={priority}
          togglePriority={togglePriority}
          clearPriority={clearPriority}
          t={t}
        />

        {/* Separator */}
        <div className="w-px h-4 bg-surface-3/80 mx-1 shrink-0" />

        {/* Duration dropdown */}
        <DurationDropdown
          estimatedMinutes={estimatedMinutes}
          toggleDuration={toggleDuration}
          setEstimatedMinutes={setEstimatedMinutes}
          clearDuration={clearDuration}
          t={t}
        />

        {/* Separator */}
        <div className="w-px h-4 bg-surface-3/80 mx-1 shrink-0" />

        {/* Tags toggle */}
        <TagsToggle
          tagsInput={tagsInput}
          setTagsInput={setTagsInput}
          t={t}
        />

        {/* Detected date chip - inline at the end */}
        <InlineDetectedDateChip
          activeNlDate={activeNlDate}
          clearNlDate={clearNlDate}
          locale={locale}
          t={t}
          timezone={dayContext.timezone}
        />
      </div>
    </div>
  );
}
