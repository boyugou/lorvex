import WeeklyReviewContent from './weekly-review/WeeklyReviewContent';
import { useWeeklyReviewController, type WeeklyReviewViewProps } from './weekly-review/useWeeklyReviewController';

export default function WeeklyReviewView(props: WeeklyReviewViewProps) {
  const controller = useWeeklyReviewController(props);
  return <WeeklyReviewContent controller={controller} />;
}
