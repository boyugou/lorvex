import assert from 'node:assert/strict';
import test from 'node:test';

import { buildAssistantSnippets } from '../../../app/src/components/settings/controller/assistant/mcp';
import { formatTranslation, loadLocale, type Locale, type TranslationKey, type TranslationVars } from '../../../app/src/locales';

function formatter(locale: Locale) {
  return (key: TranslationKey, vars?: TranslationVars) => formatTranslation(locale, key, vars);
}

const status = {
  resolved: true,
  command: '/Applications/Lorvex.app/Contents/MacOS/lorvex-mcp-server',
  args: ['--profile', 'default'],
  cwd: '/Users/example/Lorvex Data',
};

test('assistant MCP setup prompt uses locale catalog prose', async () => {
  await loadLocale('zh');

  const snippets = buildAssistantSnippets(status, formatter('zh'));

  assert.ok(snippets);
  assert.match(snippets.setupPrompt, /请帮我在本机配置 Lorvex MCP 服务器/);
  assert.match(snippets.setupPrompt, /## 服务器详情/);
  assert.match(snippets.setupPrompt, /## 要做什么/);
  assert.match(snippets.setupPrompt, /合并，不要覆盖。/);
  assert.match(snippets.setupPrompt, /调用 `get_overview` 工具验证/);
  assert.doesNotMatch(snippets.setupPrompt, /I need you to configure/);
  assert.doesNotMatch(snippets.setupPrompt, /Server Details/);
  assert.doesNotMatch(snippets.setupPrompt, /What To Do/);
  assert.doesNotMatch(snippets.setupPrompt, /Merge, don't overwrite/);
});

test('assistant MCP setup prompt preserves generated config literals', () => {
  const snippets = buildAssistantSnippets(status, formatter('en'));

  assert.ok(snippets);
  assert.match(snippets.setupPrompt, /"command": "\/Applications\/Lorvex\.app\/Contents\/MacOS\/lorvex-mcp-server"/);
  assert.match(snippets.setupPrompt, /args = \["--profile", "default"\]/);
  assert.match(snippets.setupPrompt, /set it to: \/Users\/example\/Lorvex Data/);
});
