export function formatKey(key: string): string {
  return key.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
}

export function keyIcon(key: string): string {
  const icons: Record<string, string> = {
    user_profile: '👤',
    list_summaries: '📋',
    behavioral_patterns: '📊',
    recent_activity: '🕐',
    pending_followups: '📌',
  };
  return icons[key] ?? '✦';
}

/**
 * Editorial cluster a memory entry belongs to in the read view. Inferred
 * from the entry's `key` (assistants write a small, conventional
 * vocabulary), so the read surface can group 50+ entries into scannable
 * sections without a schema change.
 *
 * Buckets:
 *   - `preferences`: tastes, dislikes, working hours, communication style
 *   - `people`: relationships, contacts, family/friends, pets
 *   - `projects`: list summaries, ongoing work, project state
 *   - `facts`: catch-all for everything not matched above — profile data,
 *      behavioural patterns, recent activity, pending followups, custom
 *      seeded facts.
 *
 * The matcher is intentionally conservative: an unrecognized key falls
 * into `facts` rather than being dropped, so no entry hides off-screen.
 */
export type MemoryCluster = 'preferences' | 'people' | 'projects' | 'facts';

const CLUSTER_KEYWORDS: Array<{ cluster: MemoryCluster; needles: readonly string[] }> = [
  {
    cluster: 'preferences',
    needles: [
      'preference', 'pref_', 'work_hours', 'working_hours', 'dislike',
      'likes', 'tone', 'style', 'communication',
    ],
  },
  {
    cluster: 'people',
    needles: [
      'person', 'people', 'contact', 'pets', 'pet_', 'family', 'partner',
      'spouse', 'friend', 'colleague', 'manager', 'team_',
    ],
  },
  {
    cluster: 'projects',
    needles: [
      'list_summaries', 'project', 'projects', 'workstream', 'initiative',
      'goal_', 'goals',
    ],
  },
];

export function clusterForKey(key: string): MemoryCluster {
  const lower = key.toLowerCase();
  for (const { cluster, needles } of CLUSTER_KEYWORDS) {
    for (const needle of needles) {
      if (lower.includes(needle)) return cluster;
    }
  }
  return 'facts';
}

/**
 * Stable cluster order for the AI Memory read view. Editorial choice:
 * preferences first (most personal, most often consulted), then people
 * (who the assistant interacts with on the user's behalf), then projects
 * (what the user is currently doing), then facts (general background).
 */
export const MEMORY_CLUSTER_ORDER: readonly MemoryCluster[] = [
  'preferences',
  'people',
  'projects',
  'facts',
];
