import assert from 'node:assert/strict';
import test from 'node:test';

import { parseDateFromText } from '../../../app/src/lib/dateParser';

const referenceDate = new Date('2026-04-22T15:00:00Z');

test('parseDateFromText strips English filler phrases and keeps trailing punctuation tight', () => {
  const parsed = parseDateFromText('Finish proposal by Friday!', 'en', referenceDate);
  assert.ok(parsed);
  assert.equal(parsed?.cleanTitle, 'Finish proposal!');
  assert.equal(parsed?.matchedText.toLowerCase(), 'by friday');
});

test('parseDateFromText returns null when the date phrase consumes the whole title', () => {
  assert.equal(parseDateFromText('tomorrow', 'en', referenceDate), null);
  assert.equal(parseDateFromText('  by friday  ', 'en', referenceDate), null);
  assert.equal(parseDateFromText('tomorrow!', 'en', referenceDate), null);
  assert.equal(parseDateFromText('(tomorrow)', 'en', referenceDate), null);
});

test('parseDateFromText falls back from regional locale codes to language-specific parser', () => {
  const parsed = parseDateFromText('ship checklist by tomorrow', 'en-US', referenceDate);
  assert.ok(parsed);
  assert.equal(parsed?.cleanTitle, 'ship checklist');

  const unsupportedLocaleEnglish = parseDateFromText('ship checklist by tomorrow', 'ko', referenceDate);
  assert.ok(unsupportedLocaleEnglish);
  assert.equal(unsupportedLocaleEnglish?.cleanTitle, 'ship checklist');

  assert.equal(parseDateFromText('Prepare slides for Friday review', 'ko', referenceDate), null);
});

test('parseDateFromText rejects time-only matches', () => {
  assert.equal(parseDateFromText('Call Sam at 5', 'en', referenceDate), null);
  assert.equal(parseDateFromText('Call Sam 5pm', 'en', referenceDate), null);

  const withLaterDate = parseDateFromText('Call Sam at 5, due Friday', 'en', referenceDate);
  assert.ok(withLaterDate);
  assert.equal(withLaterDate?.cleanTitle, 'Call Sam at 5,');
});

test('parseDateFromText does not strip weekdays out of plain English noun phrases', () => {
  const forTomorrow = parseDateFromText('Finish report for tomorrow', 'en', referenceDate);
  assert.ok(forTomorrow);
  assert.equal(forTomorrow?.cleanTitle, 'Finish report');

  const nextMonth = parseDateFromText('plan next month', 'en', referenceDate);
  assert.ok(nextMonth);
  assert.equal(nextMonth?.cleanTitle, 'plan');

  const nextYear = parseDateFromText('review next year', 'en', referenceDate);
  assert.ok(nextYear);
  assert.equal(nextYear?.cleanTitle, 'review');

  const thisMonth = parseDateFromText('revisit this month', 'en', referenceDate);
  assert.ok(thisMonth);
  assert.equal(thisMonth?.cleanTitle, 'revisit');

  const laterRealDate = parseDateFromText('Friday review tomorrow', 'en', referenceDate);
  assert.ok(laterRealDate);
  assert.equal(laterRealDate?.cleanTitle, 'Friday review');

  const laterNumericDate = parseDateFromText('Friday review on 4/23', 'en', referenceDate);
  assert.ok(laterNumericDate);
  assert.equal(laterNumericDate?.cleanTitle, 'Friday review');

  assert.equal(parseDateFromText('March roadmap', 'en', referenceDate), null);
  assert.equal(parseDateFromText('April notes', 'en', referenceDate), null);
  assert.equal(parseDateFromText('April 2027 roadmap', 'en', referenceDate), null);
  assert.equal(parseDateFromText('budget for April 2027', 'en', referenceDate), null);
  assert.equal(parseDateFromText('Prepare slides for Friday review', 'en', referenceDate), null);
  assert.equal(parseDateFromText('draft agenda for monday sync', 'en', referenceDate), null);
  assert.equal(parseDateFromText('Prepare slides before Friday review', 'en', referenceDate), null);
  assert.equal(parseDateFromText('Finish report by Friday review', 'en', referenceDate), null);
  assert.equal(parseDateFromText('monday.com migration', 'en', referenceDate), null);
  assert.equal(parseDateFromText('friday.js cleanup', 'en', referenceDate), null);
  assert.equal(parseDateFromText('thursday-review', 'en', referenceDate), null);
  assert.equal(parseDateFromText('Freitag Review', 'de', referenceDate), null);
  assert.equal(parseDateFromText('lundi revue', 'fr', referenceDate), null);
  assert.equal(parseDateFromText('金曜日レビュー', 'ja', referenceDate), null);
});

test('parseDateFromText strips locale-specific affixes around supported non-English date phrases', () => {
  const spanish = parseDateFromText('terminar informe antes de mañana', 'es', referenceDate);
  assert.ok(spanish);
  assert.equal(spanish?.cleanTitle, 'terminar informe');

  const german = parseDateFromText('Aufgabe bis morgen erledigen', 'de', referenceDate);
  assert.ok(german);
  assert.equal(german?.cleanTitle, 'Aufgabe erledigen');

  const japanese = parseDateFromText('報告を明日までに仕上げる', 'ja', referenceDate);
  assert.ok(japanese);
  assert.equal(japanese?.cleanTitle, '報告を仕上げる');

  const shorthandJapanese = parseDateFromText('明日やる', 'ja', referenceDate);
  assert.ok(shorthandJapanese);
  assert.equal(shorthandJapanese?.cleanTitle, 'やる');

  const chinese = parseDateFromText('付款在明天之前', 'zh', referenceDate);
  assert.ok(chinese);
  assert.equal(chinese?.cleanTitle, '付款');

  const traditionalChinese = parseDateFromText('付款在明天之前', 'zh-Hant', referenceDate);
  assert.ok(traditionalChinese);
  assert.equal(traditionalChinese?.cleanTitle, '付款');

  assert.equal(parseDateFromText('重构明天前端', 'zh', referenceDate), null);
  assert.equal(parseDateFromText('重构明天前端', 'zh-Hant', referenceDate), null);
  assert.equal(parseDateFromText('明日葉サラダ', 'ja', referenceDate), null);
});
