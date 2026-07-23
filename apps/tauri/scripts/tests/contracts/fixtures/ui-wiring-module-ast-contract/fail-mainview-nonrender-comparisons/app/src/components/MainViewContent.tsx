function hasKnownViewType(view: { type: string }) {
  return view.type === 'today'
    || view.type === 'upcoming'
    || view.type === 'all'
    || view.type === 'someday'
    || view.type === 'calendar'
    || view.type === 'eisenhower'
    || view.type === 'daily_review'
    || view.type === 'memory'
    || view.type === 'review'
    || view.type === 'changelog';
}

export function MainViewContent({ view }: { view: { type: string } }) {
  void hasKnownViewType(view);
  return null;
}
