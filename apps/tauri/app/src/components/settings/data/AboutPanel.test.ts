import { describe, expect, it } from 'vitest';
import { buildAboutVersionsLine } from './AboutPanel';
import type { DiagnosticsVersions } from '@/lib/ipc/settings';

describe('buildAboutVersionsLine', () => {
  it('includes app build MCP schema and payload versions', () => {
    const versions: DiagnosticsVersions = {
      app_version: '1.2.3',
      mcp_server_version: '1.2.4',
      schema_version: 42,
      payload_schema_version: 7,
    };

    expect(buildAboutVersionsLine(versions, 'abc1234')).toBe(
      'Lorvex app v1.2.3 (build abc1234) / MCP v1.2.4 / schema 42 / payload-schema 7',
    );
  });
});
