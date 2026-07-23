import { describe, expect, it } from 'vitest';

type FsNS = { readFileSync: (path: string, encoding: 'utf8') => string };

const fs = (await import(/* @vite-ignore */ 'node:fs' as string)) as unknown as FsNS;

const syncSettingsDir = 'src/components/settings/assistant/sync-settings';

function readSyncSettingsSource(fileName: string): string {
  return fs.readFileSync(`${syncSettingsDir}/${fileName}`, 'utf8');
}

describe('SyncMethodCard source boundaries', () => {
  it('keeps SyncMethodCard as a thin composer over focused sync settings components', () => {
    const source = readSyncSettingsSource('SyncMethodCard.tsx');

    for (const componentName of [
      'SyncRunControls',
      'SyncProgressStatus',
      'SyncBackendSelector',
      'FilesystemBridgePathEditor',
      'LastSyncSummary',
    ]) {
      expect(source).toContain(`./${componentName}`);
      expect(source).toContain(`<${componentName}`);
      expect(readSyncSettingsSource(`${componentName}.tsx`)).toContain(
        `export function ${componentName}`,
      );
    }

    expect(source.split('\n').length).toBeLessThanOrEqual(220);
    expect(source).not.toContain('cancelSync(');
    expect(source).not.toContain('useSyncProgress(');
    expect(source).not.toContain('lastSyncRunResult.backendResult');
  });
});
