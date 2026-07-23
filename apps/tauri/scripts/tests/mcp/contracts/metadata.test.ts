import assert from 'node:assert/strict';
import test from 'node:test';

import { createHarness } from './shared.ts';

type JsonSchemaNode = {
  $ref?: string;
  anyOf?: JsonSchemaNode[];
  properties?: Record<string, JsonSchemaNode>;
  description?: string;
};

function resolveNodeProperty(
  root: { $defs?: Record<string, JsonSchemaNode> },
  node: JsonSchemaNode | undefined,
  propertyName: string,
): JsonSchemaNode | undefined {
  if (!node) {
    return undefined;
  }

  const direct = node.properties?.[propertyName];
  if (direct) {
    return direct;
  }

  const ref = node.$ref ?? node.anyOf?.find((candidate) => typeof candidate.$ref === 'string')?.$ref;
  if (!ref?.startsWith('#/$defs/')) {
    return undefined;
  }

  const defName = ref.slice('#/$defs/'.length);
  return root.$defs?.[defName]?.properties?.[propertyName];
}

test('calendar tool metadata documents recurrence format', async (t) => {
  const harness = await createHarness('tool-metadata');
  t.after(async () => {
    await harness.cleanup();
  });

  const listToolsResult = await harness.client.listTools();
  const createCalendarEvent = listToolsResult.tools.find((tool) => tool.name === 'create_calendar_event');

  assert.ok(createCalendarEvent, 'Expected create_calendar_event tool');
  assert.match(
    createCalendarEvent!.description ?? '',
    /Create a calendar event/i,
    'create_calendar_event should describe its purpose in the tool description',
  );
  assert.match(
    createCalendarEvent!.description ?? '',
    /recurrence accepts DAILY\|WEEKLY\|MONTHLY\|YEARLY|RRULE-aligned JSON object string/i,
    'create_calendar_event should document the RRULE-aligned recurrence format in the top-level tool description',
  );
  const calendarSchema = createCalendarEvent!.inputSchema as {
    properties?: Record<string, { description?: string; type?: string | string[] }>;
  };

  assert.ok(
    !('source' in (calendarSchema.properties ?? {})),
    'create_calendar_event schema should not advertise a removed source field',
  );
  assert.match(
    calendarSchema.properties?.recurrence?.description ?? '',
    /plain string DAILY\|WEEKLY\|MONTHLY\|YEARLY|RRULE-aligned JSON object string/i,
    'create_calendar_event.recurrence should document RRULE-aligned format',
  );
  assert.match(
    calendarSchema.properties?.event_type?.description ?? '',
    /event.*birthday.*anniversary.*memorial/i,
    'create_calendar_event.event_type should document the canonical event-type set',
  );
  assert.doesNotMatch(
    calendarSchema.properties?.event_type?.description ?? '',
    /meeting|task|block/i,
    'create_calendar_event.event_type should not document removed non-canonical types',
  );
  const allDaySchema = calendarSchema.properties?.all_day;
  assert.ok(Array.isArray(allDaySchema?.type), 'create_calendar_event.all_day schema should publish strict type variants');
  assert.deepEqual(
    allDaySchema?.type,
    ['boolean', 'null'],
    'create_calendar_event.all_day schema should advertise only boolean and null variants explicitly',
  );
});

test('calendar batch creation tool is exposed in MCP contracts', async (t) => {
  const harness = await createHarness('calendar-batch-contract');
  t.after(async () => {
    await harness.cleanup();
  });

  const listToolsResult = await harness.client.listTools();
  const batchCreateCalendarEvents = listToolsResult.tools.find((tool) => tool.name === 'batch_create_calendar_events');

  assert.ok(batchCreateCalendarEvents, 'Expected batch_create_calendar_events tool');
  assert.match(
    batchCreateCalendarEvents!.description ?? '',
    /same recurrence format as create_calendar_event/i,
    'batch_create_calendar_events should document that it shares the same recurrence format',
  );
  const schema = batchCreateCalendarEvents.inputSchema as {
    properties?: Record<string, unknown>;
  };
  assert.ok(schema.properties && 'events' in schema.properties, 'batch_create_calendar_events should accept an events array');
});

test('control_app_ui metadata documents supported actions and allowlisted argument values', async (t) => {
  const harness = await createHarness('control-app-ui-contract');
  t.after(async () => {
    await harness.cleanup();
  });

  const listToolsResult = await harness.client.listTools();
  const controlAppUi = listToolsResult.tools.find((tool) => tool.name === 'control_app_ui');

  assert.ok(controlAppUi, 'Expected control_app_ui tool');
  assert.match(
    controlAppUi!.description ?? '',
    /enter_focus_mode\|exit_focus_mode\|focus_task\|open_task\|switch_view\|set_theme\|set_appearance_profile\|set_language/i,
    'control_app_ui should document supported UI actions in the top-level tool description',
  );
  assert.match(
    controlAppUi!.description ?? '',
    /view, theme, appearance_profile, and language/i,
    'control_app_ui should document the main allowlisted argument families in the top-level tool description',
  );

  const schema = controlAppUi!.inputSchema as {
    properties?: Record<string, { description?: string }>;
  };

  assert.match(
    schema.properties?.view?.description ?? '',
    /today[\/|, ]+upcoming[\/|, ]+(?:ai_)?changelog[\/|, ]+all(?:_tasks)?[\/|, ]+someday[\/|, ]+calendar[\/|, ]+eisenhower[\s\S]*settings[\/|, ]+list[\/|, ]+habits/i,
    'control_app_ui.view should document valid view values',
  );
  assert.match(
    schema.properties?.task_id?.description ?? '',
    /focus_task\/open_task.*enter_focus_mode.*open task/i,
    'control_app_ui.task_id should document enter_focus_mode targeting semantics',
  );
  assert.match(
    schema.properties?.theme?.description ?? '',
    /paper[\s\S]*dark[\s\S]*ember[\s\S]*midnight[\s\S]*liquid[\s\S]*mica[\s\S]*adwaita[\s\S]*system/i,
    'control_app_ui.theme should document valid theme values',
  );
  assert.match(
    schema.properties?.appearance_profile?.description ?? '',
    /clarity[\/|, ]+studio[\/|, ]+focus_compact[\/|, ]+liquid_glass/i,
    'control_app_ui.appearance_profile should document valid appearance profile values',
  );
  assert.match(
    schema.properties?.language?.description ?? '',
    /system[\/|, ]+en[\/|, ]+zh[\/|, ]+zh-Hant[\/|, ]+es[\/|, ]+fr[\/|, ]+de[\/|, ]+ja[\/|, ]+ko[\/|, ]+pt[\/|, ]+ru[\/|, ]+hi[\/|, ]+ar[\/|, ]+id[\/|, ]+it[\/|, ]+nl[\/|, ]+tr[\/|, ]+pl[\/|, ]+uk[\/|, ]+vi[\/|, ]+th[\/|, ]+ms[\/|, ]+bn[\/|, ]+te[\/|, ]+mr[\/|, ]+ta[\/|, ]+ml[\/|, ]+el[\/|, ]+ro[\/|, ]+ur[\/|, ]+fa[\/|, ]+he/i,
    'control_app_ui.language should document valid language values',
  );
});
