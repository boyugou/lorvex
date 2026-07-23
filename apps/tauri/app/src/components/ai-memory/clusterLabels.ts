import type { TranslationKey } from '@/lib/i18n';
import type { AIMemoryEntry } from '@/lib/ipc/memory';
import { clusterForKey, MEMORY_CLUSTER_ORDER, type MemoryCluster } from './helpers';

// Editorial cluster labels keyed off MemoryCluster. Kept inline
// rather than a separate registry because the cluster taxonomy lives
// in helpers.ts and the memory view is the only consumer of the
// labels.
export const CLUSTER_LABEL_KEY: Record<MemoryCluster, TranslationKey> = {
  preferences: 'memory.cluster.preferences',
  people: 'memory.cluster.people',
  projects: 'memory.cluster.projects',
  facts: 'memory.cluster.facts',
};

// CTA copy per cluster — shown as a faded "teach me about …" row
// when the user has no entries in that cluster yet. Lets a fresh
// user discover the cluster taxonomy without first persuading their
// assistant to populate it.
export const CLUSTER_EMPTY_CTA_KEY: Record<MemoryCluster, TranslationKey> = {
  preferences: 'memory.cluster.preferencesEmptyCta',
  people: 'memory.cluster.peopleEmptyCta',
  projects: 'memory.cluster.projectsEmptyCta',
  facts: 'memory.cluster.factsEmptyCta',
};

// Placeholder key segment paired with each cluster prefix. The AI
// memory key namespace is conventionally dotted (`people.alice_pm`,
// `preferences.coffee`, etc.) — `clusterForKey()` matches the
// leading segment to infer the cluster. Pre-filling the AddMemoryForm
// with `<cluster>.<placeholder>` gives the user a concrete starting
// point in the right cluster instead of a blank input that they have
// to guess the namespace for.
export const CLUSTER_KEY_PLACEHOLDER: Record<MemoryCluster, string> = {
  preferences: 'preferences.',
  people: 'people.',
  projects: 'projects.',
  facts: 'facts.',
};

export interface ClusteredEntries {
  cluster: MemoryCluster;
  entries: AIMemoryEntry[];
}

export function groupEntriesByCluster(entries: AIMemoryEntry[]): ClusteredEntries[] {
  const buckets = new Map<MemoryCluster, AIMemoryEntry[]>();
  for (const entry of entries) {
    const cluster = clusterForKey(entry.key);
    const existing = buckets.get(cluster);
    if (existing) existing.push(entry);
    else buckets.set(cluster, [entry]);
  }
  const groups: ClusteredEntries[] = [];
  for (const cluster of MEMORY_CLUSTER_ORDER) {
    const items = buckets.get(cluster);
    if (items && items.length > 0) {
      groups.push({ cluster, entries: items });
    }
  }
  return groups;
}
