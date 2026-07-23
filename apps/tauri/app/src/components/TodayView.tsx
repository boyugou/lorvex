import { useConfiguredDayContext } from '../lib/dayContext';
import { useRuntimeProfile } from '../lib/useRuntimeProfile';

import TodayViewContent from './today-view/TodayViewContent';
import { useTodayViewController } from './today-view/useTodayViewController';
import type { TodayViewProps } from './today-view/types';

export default function TodayView({ overview, onNavigate, onSelectTask, onAddTask }: TodayViewProps) {
  const runtimeProfile = useRuntimeProfile();
  const dayContext = useConfiguredDayContext();
  const controller = useTodayViewController({
    dayContext,
    usesMobileLayout: runtimeProfile.runtimeClass === 'mobile',
    onSelectTask,
    overview,
  });

  return (
    <div className="h-full flex flex-col overflow-hidden clarity-first-surface">
      <TodayViewContent {...controller} onNavigate={onNavigate} onAddTask={onAddTask} />
    </div>
  );
}
