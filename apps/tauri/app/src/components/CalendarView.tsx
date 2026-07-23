import { CalendarViewContent } from './calendar/CalendarViewContent';
import { useCalendarViewController } from './calendar/useCalendarViewController';

export default function CalendarView() {
  const controller = useCalendarViewController();
  return <CalendarViewContent controller={controller} />;
}
