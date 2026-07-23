export interface LearningInsightsPayload {
  window_days: number;
  top_n: number;
  metrics: {
    frequently_deferred: number;
    stalled_lists: number;
    overdue_backlog: number;
  };
  representative_samples: {
    frequently_deferred: Array<{ id: string }>;
    stalled_lists: Array<{ id: string }>;
    overdue_backlog: Array<{ id: string }>;
  };
  insights: Array<{
    type: 'frequently_deferred' | 'stalled_lists' | 'overdue_backlog';
    severity: 'low' | 'medium' | 'high';
    source_refs: string[];
  }>;
  source_refs: string[];
}
