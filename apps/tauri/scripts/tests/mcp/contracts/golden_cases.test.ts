import assert from 'node:assert/strict';
import test from 'node:test';

import {
  GOLDEN_CASES_PATH,
  asToolResultPayload,
  createHarness,
  getFirstTextContent,
  readJsonFixture,
  type GoldenCase,
} from './shared.ts';

test('golden behavior cases keep stable output shape for representative tools', async (t) => {
  const harness = await createHarness('golden-cases');
  t.after(async () => {
    await harness.cleanup();
  });

  const fixture = readJsonFixture<{ cases: GoldenCase[] }>(GOLDEN_CASES_PATH);
  for (const c of fixture.cases) {
    const rawResult = await harness.client.callTool({
      name: c.tool,
      arguments: c.arguments ?? {},
    });
    const payload = asToolResultPayload(rawResult);
    const firstText = getFirstTextContent(payload);
    if (payload.isError) {
      assert.fail(`[${c.name}] MCP returned an error payload: ${firstText}`);
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(firstText);
    } catch {
      assert.fail(`[${c.name}] expected JSON response, got: ${firstText}`);
    }

    if (c.expect.type === 'object') {
      assert.equal(typeof parsed, 'object', `[${c.name}] expected object result`);
      assert.ok(parsed !== null && !Array.isArray(parsed), `[${c.name}] expected non-null object result`);
      const obj = parsed as Record<string, unknown>;
      for (const key of c.expect.required_keys ?? []) {
        assert.ok(key in obj, `[${c.name}] missing required key: ${key}`);
      }
      for (const [key, value] of Object.entries(c.expect.equals ?? {})) {
        assert.deepEqual(obj[key], value, `[${c.name}] expected ${key} to match fixture`);
      }
      continue;
    }

    assert.ok(Array.isArray(parsed), `[${c.name}] expected array result`);
    if (typeof c.expect.min_length === 'number') {
      assert.ok(parsed.length >= c.expect.min_length, `[${c.name}] expected min length ${c.expect.min_length}`);
    }
  }
});
