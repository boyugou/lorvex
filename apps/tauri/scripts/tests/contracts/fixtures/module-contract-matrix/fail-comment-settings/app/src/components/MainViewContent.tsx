export default function MainViewContent({ view }: { view: { type: string } }) {
  return (
    <div>
      {view.type === 'today' && null}
      {view.type === 'upcoming' && null}
      {view.type === 'all' && null}
      {view.type === 'someday' && null}
      {view.type === 'calendar' && null}
      {view.type === 'eisenhower' && null}
      {view.type === 'daily_review' && null}
      {view.type === 'memory' && null}
      {view.type === 'review' && null}
      {view.type === 'changelog' && null}
    </div>
  );
}
