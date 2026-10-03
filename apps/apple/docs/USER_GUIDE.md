# Lorvex User Guide

## Welcome to Lorvex

Lorvex is an AI-first task manager built for the Apple platform. Rather than
replacing your thinking, it serves as a structured memory that AI clients can
read and write through the Model Context Protocol (MCP). Your tasks,
calendar events, habits, and reviews live in Lorvex-managed local
storage; an external AI client such as Claude connects to the Lorvex MCP
host and acts as your intelligent co-pilot — capturing, organizing, and
reviewing work on your behalf. The native SwiftUI app surfaces the same data
for glancing, confirming, and acting when you want to stay hands-on.

---

## Setup

### First Launch

1. Build or install `Lorvex.app` and open it.
2. On first launch the app creates managed local storage so you can start
   working immediately.
3. A short setup follows. It asks whether to sync through iCloud: sync stays
   off until you turn it on, there or later in **Settings → Cloud Sync**, and
   starts as soon as you do. Setup then offers the optional permissions
   (Notifications for reminders, and Calendar on the Mac) and ends by naming
   the two ways work gets in: capture it yourself, or connect an assistant. On
   the Mac, **Connect an Assistant…** on that last page opens **Settings →
   Assistant**.

### Storage

Lorvex keeps your data in a single managed local SQLite database. Every surface
— the app, widgets, App Intents, notifications, and the MCP helper — uses this
same managed store, and cross-device sync is handled entirely by iCloud
(CloudKit). There is no storage picker or external-file option.

To move your data between installs or keep a backup, use **Settings → Data →
Export** to write a file and **Settings → Data → Import Data** to bring it back.
Export/import is the supported way to carry your data to another machine — live
SQLite files must not be shared through a sync folder.

### MCP Client Configuration

With Lorvex installed, open **Settings → Assistant** and use **Copy Setup
Prompt**, or expand **Advanced** to copy a config for your client. In Claude
Code, install the Lorvex plugin instead; it connects the helper and adds skills
for planning a day, capturing tasks, weekly reviews, and tidying the
assistant's memory:

```
/plugin marketplace add boyugou/lorvex
/plugin install lorvex@lorvex
```

Once an assistant has connected, Settings → Assistant lists it under
**Assistants on This Mac** with when it last used Lorvex, so you can tell the
connection works.

After building or packaging the app from source, run the following script to
generate an MCP client config for Claude or any other MCP-capable client:

```bash
python3 script/generate_mcp_client_config.py \
  --app-bundle /Applications/Lorvex.app
```

The script writes a JSON file you can paste into your Claude or Codex MCP
configuration. The bundled helper ships as
`Contents/Helpers/LorvexMCPHost.app`, a minimal app bundle rather than a bare
executable (so the App Sandbox can initialize a container for it); the
config points at its inner binary,
`Contents/Helpers/LorvexMCPHost.app/Contents/MacOS/LorvexMCPHost`, so the AI
client launches it over stdio the same way. The JSON also includes a
`lorvex` metadata block declaring the Apple-only Swift-native MCP host
strategy and the official `modelcontextprotocol/swift-sdk`.

Local packaging via `./script/package_local.sh` also emits
`dist/lorvex-apple-mcp-client.json` automatically.

Every install — packaged or built from source — opens only the single
Lorvex-managed App Group store, so the generated config carries no database
override. A dev/source build may point the MCP host at a fixture database with
`LORVEX_APPLE_DB_PATH` (see `docs/setup/ASSISTANT_MCP_SETUP.md`); this is a
development affordance only and is never part of a shipping config.

### Permissions

Lorvex may request the following permissions on first use:

| Permission | When requested | Purpose |
|---|---|---|
| **Calendar** | Opening the Calendar workspace or exporting events | Read Apple Calendar events; write Lorvex planning blocks back to system calendar |
| **Notifications** | Scheduling a task reminder | Deliver task reminder alerts |

Grant each permission in **System Settings → Privacy & Security** if the
system dialog does not appear. Denying Calendar access does not
block core Lorvex data; it only affects the corresponding EventKit overlay.
On iPhone and iPad, the Notifications row in Lorvex's Settings shows whether
notifications are allowed: **Allow** asks for access when iOS has not asked
yet, and **Open Settings** goes to Lorvex's page in the Settings app after
access was declined.

---

### Language, Clock, and Time Zone

Settings (General on Mac) sets the app's language, its clock, and its time
zone. **Clock**
follows your system's 12- or 24-hour setting unless you choose **12-Hour** or
**24-Hour**; each choice shows a sample time. The clock applies at once to
every time Lorvex shows, including widgets and time pickers. Times you give
the assistant, and times it reports, stay in 24-hour `HH:MM` form.

**Time Zone** is the zone Lorvex counts days in on all your devices, so
"today" and "tomorrow" mean the same days on your Mac and your iPhone. Setup
starts it at your device's zone. Choose another from the searchable list when
you move; reminders keep their clock time in the new zone, so a 9 AM reminder
still rings at 9 AM there. When a device is in a different zone from Lorvex's,
the setting offers a one-tap switch to the device's zone; on a short trip you
can keep your home zone instead.

## Quick Capture

Quick Capture is the fastest way to get a task into Lorvex without interrupting
your current activity.

### Keyboard Shortcut

With Lorvex active, press **⌘N** (or **File → New Task**) to focus the inline
quick-add field — under today's tasks on Today, at the top of the Tasks list.
Lorvex switches to Tasks first if you are on another workspace. Type a task title and press **Return** to
save it; the field clears and keeps focus so you can add several in a row.

### Words Quick Capture Understands

Every capture field reads a few details out of what you type and shows them
under the field before you save; the rest becomes the title. English and
Chinese both work. Chinese needs no spaces ("明天开会30分钟") and reads the same
in Traditional characters ("後天開會", "下週三", "30分鐘"); the title keeps the
characters you typed.

| Detail | English | Chinese |
|---|---|---|
| Day | today, tonight, tomorrow, Friday, this Friday, next Friday, next week, weekend, in 3 days | 今天, 明天, 后天, 大后天, 周三 / 星期三 / 礼拜三, 这周三, 下周三, 下周, 周末, 3天后 |
| Date | Oct 5, October 5th, 5 Oct, 2026-10-05 | 10月5日, 10月5号, 5号 |
| Due day | by Friday, due tomorrow, by Oct 5 | 周五前, 明天之前, 10月5日前 |
| Time | 3pm, 3:30 pm, at 15:30, noon, at midnight; 3-4pm, 11am to 1pm, 15:00–16:30 | 下午3点, 晚上8点半, 晚上12点, 三点一刻, 9点20分, 15:30; 下午3点到5点, 下午3-5点 |
| Repeat | every day, every weekday, every other week, every 3 days, every Monday, every Mon and Thu, every month, every year; daily, weekly, monthly, yearly at the end | 每天, 每隔一天, 每3天, 每周, 每两周, 每周一, 每周一三五, 每个工作日, 每月, 每月5号, 每年 |
| Length | 20 min, 1.5h, 20m, 1h30m, half an hour | 30分钟, 2小时, 2个钟头, 半小时, 半个钟头, 一个半小时 |
| Priority | !, !!, !!!, p1–p3, high priority, low priority, urgent (at the end, or "Urgent:" at the start) | 紧急 |
| List or tag | #listname (a list when the name matches one, a tag otherwise) | #清单名 |

A weekday's short form ("sat", "wed") counts only when it is capitalized or
follows on, for, this, next, or by, and a capitalized weekday in the middle of
a title ("Monday Morning Memo") stays part of the title.

A date without a year that has already passed means next year's, and "5号"
means the coming 5th. A time plans the task at that time for its length, or
for half an hour, on the day you wrote or today when you wrote none. A time
from 1 to 6 o'clock with no AM, PM, or part of the day (下午, 晚上) is in the
afternoon.

A time range plans the task from its start for as long as the range lasts,
unless the line also names a length: "3-4pm" plans an hour from 3 PM. A side
written without AM, PM, or a part of the day follows the other side, so
"11-1pm" runs from 11 AM to 1 PM and 下午3点到5点 ends at 5 PM. In English a
range needs AM, PM, a colon, noon, or midnight on one side, so "Room 3-4"
stays a title.

A day's night runs past midnight. After 晚上, 半夜, "tonight", or 今晚, 6 to 11
o'clock is that evening, while 12 o'clock and 1 to 5 o'clock come after
midnight, on the next day: 今晚12点 and "at midnight" mean 00:00 tomorrow,
周五晚上12点 means Saturday at 00:00, and 今晚1点 means 1:00 tomorrow. A
repeat moves with its time, so 每周五晚上12点 repeats on Saturdays at 00:00.

A repeating task is due on its first occurrence: the next of the weekdays or
the day of the month it names (today counts), else the day you wrote, else
today. "Weekly review" and other titles that open with a cadence word keep it;
daily, weekly, monthly, and yearly repeat only at the end of the line.

When a line names two days, two times, or two lengths, the first one counts
and the later one stays in the title: "明天准备周五的汇报" plans "准备周五的汇报"
for tomorrow.

Japanese and Korean words are read too when Japanese or Korean is among your
device's preferred languages (Language & Region in Settings). Japanese needs
no spaces, and the particle after a day or a time goes with it: "金曜日に資料を送る"
plans "資料を送る" for Friday. A Korean phrase stands as its own word, with its
particle: "금요일에 회의" plans "회의" for Friday, while "긴급회의" stays in the
title.

| Detail | Japanese | Korean |
|---|---|---|
| Day | 今日, 今朝, 今夜, 明日, 明後日, 金曜 / 金曜日, 今週の金曜, 来週の金曜, 来週, 再来週, 週末, 来週末, 3日後 | 오늘, 오늘 밤, 내일, 모레, 내일모레, 글피, 금요일, 이번 주 금요일, 다음 주 금요일, 다음 주, 주말, 다음 주말, 3일 후 |
| Date | 10月5日, 10/5, 10/5(月) | 10월 5일, 10/5 |
| Due day | 金曜までに, 今日中, 10/5締切 | 금요일까지, 내일까지, 10월 5일 마감 |
| Time | 午後3時, 3時半, 9時20分, 夜8時, 午後3:30, 正午; 15時から16時まで, 3〜5時 | 오후 3시, 3시 반, 9시 20분, 저녁 7시, 오후 세 시, 오후 3:30, 정오, 자정; 3시부터 4시까지, 오후 3시~5시 |
| Repeat | 毎日, 毎週, 隔週, 毎週月曜, 毎週月・水・金, 平日毎日, 毎月, 毎月5日, 毎年, 3日ごと, 1日おき | 매일, 매주, 격주, 매주 월요일, 매주 월수금, 월요일마다, 평일마다, 매달, 매달 5일, 매년, 3일마다 |
| Length | 30分, 2時間, 1時間半, 1時間30分 | 30분, 2시간, 1시간 반, 1시간 30분, 한 시간 |
| Priority | 至急, 急ぎ, 緊急 | 긴급 |

The night runs past midnight in both, as in Chinese: 夜12時 and 밤 12시 mean
00:00 the next day, and 今夜8時 and 오늘 밤 8시 mean 8 PM today.

French and Portuguese words are read when French or Portuguese is among your
device's preferred languages. Accents are optional ("apres-demain",
"amanha"). Both languages write a clock time with the letter h, so "15h" and
"15h30" are times, and an hour from 1 to 6 with no part of the day is in the
afternoon ("3h" is 3 PM) unless it is written with a zero ("06h"). A length
says that it is one: "pendant 2h" or "por 2h", minutes ("1h30min"), or a word
("2 heures", "2 horas"). An hour that could be either a time or a length
("réunion de 2h") and an hour that names a deadline ("avant 18h", "até 18h")
stay in the title. With French or Portuguese among your languages, English
leaves "2h" to them as well, so it plans 2 PM; write "2 hours" or "120 min"
for a length.

| Detail | French | Portuguese |
|---|---|---|
| Day | aujourd'hui, ce soir, demain, demain soir, après-demain, vendredi, ce vendredi, vendredi prochain, la semaine prochaine, ce week-end, dans 3 jours | hoje, hoje à noite, amanhã, depois de amanhã, sexta / sexta-feira, na sexta, nesta sexta, sexta que vem, próxima semana, fim de semana, daqui a 3 dias |
| Date | 5 octobre, le 1er octobre, lundi 5 octobre, 5 oct. | 5 de outubro, 1º de outubro, dia 5 |
| Due day | pour vendredi, d'ici demain, avant le 5 octobre, jusqu'au 5 octobre, vendredi au plus tard | até sexta, para o dia 5, prazo: 5 de outubro |
| Time | 15h, 15h30, à 9h, vers 18h, 8h du soir, 3h de l'après-midi, midi, à minuit; de 14h à 16h, 14h-16h30, entre 14h et 16h | 15h, às 15h30, por volta das 18h, às 3 da tarde, às 8 da noite, meio-dia, à meia-noite; das 14h às 16h, entre 14h e 16h |
| Repeat | tous les jours, chaque lundi, tous les lundis et jeudis, les lundis, un lundi sur deux, en semaine, tous les 15 jours, tous les mois, le 5 de chaque mois, chaque année; hebdomadairement at the end | todo dia, toda segunda, todas as segundas e quartas, aos sábados, às terças (at the end), dias úteis, a cada 15 dias, de 2 em 2 semanas, todo dia 5, todo ano; semanalmente at the end |
| Length | pendant 2h, 1h30min, 1,5 h, 30 min, 2 heures, une demi-heure, un quart d'heure | por 2h, 1h30min, 1,5 h, 30 min, 2 horas, meia hora, uma hora e meia |
| Priority | priorité haute, basse priorité, urgente | prioridade alta, baixa prioridade, urgente |

Both languages count a fortnight as fifteen days, so "tous les 15 jours" and
"a cada 15 dias" repeat every two weeks. A Portuguese weekday's short form is
also an ordinal ("a segunda parte"), so "segunda" alone counts only at the
end of the line after a word that is not an article, while "segunda-feira",
"na segunda", and "toda segunda" always count. A date written in digits
("5/10") stays in the title, since the order of its day and month depends on
the region.

Spanish and Italian words are read when Spanish or Italian is among your
device's preferred languages, in any regional variant. Accents are optional
("manana", "lunedi"). Neither language writes a clock time with the letter
h, so "2h" stays a length, as in English, and a time says "a las" or
"alle": "a las 15:30", "alle 15", "ore 15:30". An hour from 1 to 6 with no
part of the day is in the afternoon ("a las 3" is 3 PM) unless it is
written with a zero ("06:30"), and a part of the day sets the hour: "de la
tarde", "del pomeriggio", and "di sera" are the afternoon or the evening,
while "de la mañana" and "di mattina" are the morning. A bare hour counts
only at the end of the line or before a word that can follow a time ("a las
3 con Ana"), so "a las 3 hermanas" and "alle 3 amiche" stay in the title,
and so does a bare hour that names a deadline ("antes de las 6", "entro le
18"). A time written without a Spanish or Italian word ("3pm",
"14:00-16:30") is read by English, which also takes an English "at" or
"from" in front of it.

| Detail | Spanish | Italian |
|---|---|---|
| Day | hoy, esta noche, mañana, mañana por la tarde, pasado mañana, viernes, el viernes, este viernes, el próximo viernes, la semana que viene, el fin de semana, en 3 días | oggi, stasera, domani, domani sera, dopodomani, venerdì, questo venerdì, venerdì prossimo, la settimana prossima, nel weekend, il fine settimana, tra 3 giorni |
| Date | 5 de octubre, el 5 de octubre, 1º de octubre, lunes 5 de octubre, 5 oct., el día 5 | 5 ottobre, il 5 ottobre, 1º novembre, lunedì 5 ottobre, 5 ott., il 5 |
| Due day | para el viernes, antes del viernes, hasta mañana, vence el 5 de octubre, el viernes a más tardar | entro venerdì, per venerdì, entro il 5 ottobre, scade il 5 ottobre, venerdì al più tardi |
| Time | a las 15:30, a las 3 de la tarde, a las 9 de la mañana, a las 8 de la noche, a las 3 y media, a la una, mediodía, a medianoche; de 3 a 4, de las 3 a las 4 de la tarde, entre las 3 y las 4 | alle 15, ore 15:30, alle 3 del pomeriggio, alle 9 di mattina, alle 8 di sera, alle 3 e mezza, all'una, mezzogiorno, a mezzanotte; dalle 3 alle 4, tra le 3 e le 4 |
| Repeat | todos los días, cada lunes, todos los lunes y jueves, los lunes (at the end), cada dos lunes, entre semana, cada 15 días, cada mes, el 5 de cada mes, cada año; diariamente at the end | ogni giorno, ogni lunedì, tutti i lunedì e giovedì, il lunedì (at the end), un lunedì sì e uno no, nei giorni feriali, ogni 15 giorni, ogni mese, il 5 di ogni mese, ogni anno; quotidianamente at the end |
| Length | durante 2 horas, por 2h, de 2 horas, 1h30, 30 min, 2 horas y media, media hora, una hora y media | per 2 ore, di 2 ore, 1h30, 30 min, 2 ore e mezza, mezz'ora, un'ora e mezza |
| Priority | prioridad alta, baja prioridad, urgente | priorità alta, bassa priorità, urgente |

A weekday alone is the coming one ("el lunes", "lunedì"), while the plural or
the name after an article is a habit: "los lunes", "cada lunes", "il lunedì",
"ogni lunedì", and "tutti i lunedì" repeat. A habit written with an article
repeats only at the end of the line, so "los lunes de agosto" and "la riunione
del lunedì" stay in the title, a weekday after "de" or "del" ("reunión de
lunes") is never a day, and neither is a capitalized "Domingo" or "Domenica"
in the middle of a line, which is a name. "Mañana" is tomorrow on its own,
but "a las 9 de la mañana" is 9 AM, "por la mañana" stays in the title,
"cada mañana" repeats every day, and "mañana por la mañana" is tomorrow
morning. "Próximo" and "prossimo" mean next week's, so "el próximo viernes"
and "venerdì prossimo" are the Friday of next week, while "este viernes" and
"questo venerdì" are this week's. Both languages count a fortnight as fifteen
days, so "cada 15 días" and "ogni 15 giorni" repeat every two weeks. A date
written in digits ("5/10") stays in the title, since the order of its day
and month depends on the region. Italian reads "weekend" only after an
article or "questo" ("nel weekend"), so an English "this weekend" is left to
English.

### From the Menu Bar Icon

Click the Lorvex icon in the menu bar. The compact menu shows an inline
quick-add field — type a title and press **Return** to save it to your inbox.

### From Home Screen Shortcuts (iOS/iPadOS)

On iPhone and iPad, long-press the Lorvex icon and choose **Quick Capture** from
the context menu. This opens the capture sheet directly, bypassing the main app
navigation. You can also add the **Capture Task** shortcut from the Shortcuts
app to your Home Screen for single-tap capture.

The Shortcuts app also exposes **Create List**, **Update List**, **Delete List**,
**Create Habit**, **Update Habit**, **Delete Habit**, **Create Event**,
**Update Event**, **Delete Event**, **Complete Task**, **Cancel Task**,
**Reopen Task**, **Defer Task**, **Complete Habit**, **Reset Habit**,
**Daily Review**, **Start Task**, **Pause Task**, **Plan Task for Today**,
**Read Schedule**, **Suggest Times**, **Save Suggested Times**, **Save Memory**,
**Read Memory**, and **Delete Memory**. Use them from
iPhone, iPad, Mac, or Siri to create, rename, update, or delete empty lists,
create/update/delete habits, create/update/delete Lorvex-owned calendar events,
complete, cancel, reopen, or defer tasks, complete or reset today's habit progress, save a review summary,
start or pause a task, plan a task for today, read the day's times, suggest
times for today's tasks, save the times you accept back to Lorvex, or write,
read, or delete a memory key, through the same Lorvex-managed storage used by
the native app and MCP tools.

The read actions return what they read, so a shortcut can pass it to its next
step: **Read Overview** returns the most important open tasks, **Read Lists**
the lists, **Read Schedule** the day's timed tasks, **Read Weekly Review** the
week's latest completed tasks, the reminder reads their reminders, and the
calendar reads their events. **Read Task Dependencies** returns the unfinished
tasks a task waits on, or every task still waiting on another, and **Find Lists
with Overdue Tasks** returns the lists that need attention.

The **Open Lorvex** shortcut can jump directly to Today, Tasks, Lists, Calendar,
Habits, Reviews, or Memory. On iPhone and iPad, destinations
that do not have a dedicated tab route into the closest native mobile workspace.

On Apple Watch, the companion app includes a compact **Capture** section for
adding an inbox task from your wrist. The snapshot-backed watch forwards the new
task to the paired iPhone over WatchConnectivity; capture is read-only only when
no forwarder is wired, as in SwiftUI previews.

---

## Today

### Daily Routine

The **Today** workspace is your day in one list, read top to bottom:

- The date, one line of facts (tasks left, meetings, planned time, and what is
  done), and the assistant's briefing when it wrote one
- When today holds more estimated work than the free working time you have
  left, one line says so and offers to move the least urgent tasks that do not
  fit to tomorrow
- The list: started tasks first, then the rest by priority and due date, with
  no section headers — an overdue task shows its due date in red and a started
  task carries a **Started** chip, so every row already says what a heading
  would
- **Done** — what you finished today; click or tap its header to fold it

On Mac a quick-add field sits under the tasks; on iPhone and iPad the day's
habits follow as rings. Nothing you or the assistant put on today is hidden.
On Mac the day's schedule leads the page, under the briefing: your calendar
events and the day's timed tasks in time order, above the tasks without a
time. An event that runs past midnight shows its start on the day it begins
and "Until" its end at the top of the next day; a day it fills completely
shows it as all day. Click an event to see its details in the inspector,
where an event you made in Lorvex can also be edited or deleted. On iPad the
schedule stands beside the list; on iPhone, tap the day strip under the
briefing to open it.

Open Today from the sidebar, by pressing **⌘1**, or by tapping the Today tab
on iPhone/iPad.

On iPad, Lorvex supports hardware-keyboard navigation: **⌘R** refreshes,
**⌘N** opens Capture, and **⌘1**-**⌘4** switch the tabs in the order the tab bar
shows them (Today, Calendar, Tasks, Review). **⌘5** opens Habits, **⌘6** Memory,
and **⌘,** Settings, the same numbers the Mac uses.

### Suggested Times

Lorvex can lay today's tasks into a time-blocked schedule, interleaved with
your real calendar events. Ask your AI client to "suggest times for today" (or
use **Suggest Times** on Today or in Shortcuts), review the suggestion, and
accept or dismiss it. A suggestion for today starts from the current time:
meetings that already ended are left out, a task you are in the middle of
keeps its place, and tasks that no longer fit before your day hours end
are listed as not scheduled, with **Move to Tomorrow** beside them. Day hours
(Settings, 08:00–23:00 unless you change them) are the part of the day Lorvex
plans into. Tasks are placed in Today's order, each at the
earliest free time long enough for it, so a short task can fill the gap before
a meeting that a longer one did not fit, and a ten-minute break follows each
task when there is room. The suggestion stands at the top of Today's
schedule on Mac and beside Today on iPad, headed "Suggested Times" above the
saved "Current Schedule", until you
accept it with **Use These Times** or dismiss it. On iPhone the schedule opens
as a sheet from the day strip. **Clear Times** removes the day's times without
taking any task off Today; on iPhone it asks you to confirm first.

### Focus Filter for iOS Focus Modes

Lorvex provides an iOS Focus Filter. In **Settings → Focus**, add the Lorvex
filter to any Focus mode (Work, Personal, Do Not Disturb, etc.) and choose
which lists it should keep visible. While that Focus mode is active, Lorvex's
widgets and Apple Watch show only Today's tasks from the lists you chose and
leave out the assistant's briefing; choosing no list narrows nothing. The app
itself, notifications, and Shortcuts are unaffected and keep showing every
list.

---

## Tasks & Lists

### Habits

Open **Habits** from the sidebar or press ⌘5. The macOS workspace can create,
edit, delete, complete, and reset habits against the shared Lorvex core.

Each habit is a card. A daily habit's card shows the last seven days as
marks over their weekdays, today's in the habit's color, then the current
streak ("12-day streak"), the share of the last 30 days you kept it, and, when
the habit has milestones, how close it is to the next one ("Next at 14 days").
Click the ring to check it in; click the card to open the habit in the
inspector. A card's **Edit** opens the inspector with the name ready to type.

The inspector edits a habit in place, the way the task inspector edits a task:

- **Header:** the check-in ring, the name, and an encouragement line. Click the
  name or the line to type; changes save as you go.
- **Standing:** whether this day, week, or month is done ("1 of 3 this
  week"). A habit counted several times a day shows a stepper for today's
  count instead. The **…** menu holds the check-in commands, Icon and Color,
  Archive Habit, and Delete Habit.
- **Repeat, Reminder, and Goal:** click a row to change it in a popover, or a
  dashed **+ Reminder** or **+ Goal** to add one. A goal is a streak length
  (days or weeks) or a number of completions, depending on how the habit
  repeats.
- **Progress:** the current and best streaks, the check-ins logged in all,
  the share of the last 30 days kept, and the next milestone.
- **History:** recent weeks as a grid of days, Monday to Sunday, shaded by how
  much of the day's count you did. Hover a day for its date and count.
- **By Weekday:** how much of each weekday's plan you kept over the last
  twelve weeks, naming your strongest and weakest day. It appears for a habit
  planned on more than one weekday and fills in after two weeks of check-ins.

### Lists

Open the **Lists** catalog from the **Navigate** menu or the Command Palette
(⌘K) — it has no sidebar row of its own; the sidebar's list rows scope the Tasks
workspace instead. Each list shows its open and total counts and its first
three open tasks, each with its due day; click a task to open it in that list,
or the card to open the whole list. The macOS workspace can create, edit, and delete empty lists
through the same core list catalog used by MCP and mobile. Drag task rows onto a
list to move them; lists with assigned tasks must be emptied before deletion.

### Creating Tasks

- **Quick Capture:** ⌘N, type, **Return**.
- **Inline quick-add:** Type in the quick-add field (under today's tasks on
  Today, at the top of the Tasks list) and press **Return**. Tasks land in the scoped list (when a list is
  selected), the inbox (all-tasks Tasks), or today's plan (Today).
- **Full details:** ⌘N, **File → New Task**, and the toolbar **+** all focus the
  same inline quick-add — there is no separate new-task sheet. To set notes, due
  date, tags, recurrence, and checklist items, open the task and edit it in Task
  Detail (**⌘⇧I**).
- **Task Detail on a small Mac display:** Task Detail opens beside the task
  list. On a display too narrow for the sidebar, the list, and Task Detail side
  by side, Task Detail takes the sidebar's place while it is open, and the
  sidebar returns when you close it. Showing the sidebar (**⌃⌘S**) while Task
  Detail is open closes Task Detail instead. Habit and event details work the
  same way.
- **Mobile Task Detail:** On iPhone and iPad, a task's set fields are rows —
  When, How long, Due, List, Priority, Repeat, Tags, Hide until — each with its
  value; tap a row to change only that field. **Add Detail** lists the fields
  the task does not have yet, plus a checklist and a reminder when it has
  none. Tap **Edit** to change the title and notes. Swipe a checklist item or
  a reminder to delete it, or tap a checklist item's circle to mark it
  complete. **Share** sends the task as plain text in your language: its
  title, its status unless it is open, the notes, one line per field with
  days written as dates, the assistant context, and the checklist.
- **Plans that miss a deadline:** When a task's When day falls after its Due
  day and that deadline is still ahead, the When row in Task Detail says so in
  orange ("Tomorrow · after the deadline") on the Mac, iPhone, and iPad, since
  working on it that day would finish it late. Once the deadline has passed,
  the Due row says how late the task is instead.
- **Mobile Task Rows:** A task row's circle is tinted by priority and
  completes the task. Under the title, capsules mark a task that is started or
  waiting on another task, and Today adds its own ("Until 3:00 PM",
  "Pushed 4 times"). One line of metadata follows: the task's saved time, the
  due date, a repeat glyph, the estimate, and up to two tags, which drop whole
  when the line runs short.
- **Tasks that wait on others:** Task Detail's **Waits on** field names the
  tasks a task waits on; on the Mac its row shows the task's title, or how many
  tasks when there are several. Until each of them is done, canceled, or
  deleted, the task can't be started. Its rows read **Blocked**, and so do its
  lines in the widgets and on Apple Watch. Its swipe actions and context menu
  on iPhone and iPad, and its swipe on Apple Watch, leave out **Start**, and
  the Mac's context menu grays it out. In Task Detail, and among its actions on
  Apple Watch, Start stays in place but can't be used: on iPhone, iPad, and
  Apple Watch a line under the actions says why, and on the Mac the button's
  tooltip does. Finishing the last of them makes Start available again.
- **Mobile Today habits:** When you have habits, the iPhone and iPad Today tab
  shows them as rings. Tap a ring to complete the habit for today or tap a
  completed one to reset it; touch and hold one to open its details. Creating
  habits, events, and lists lives on their own tabs, not in Today.
- **Mobile Lists:** On iPhone and iPad, lists live in the **Tasks** tab. The
  Tasks home lists them as rows below the smart collections; tap one to open its
  task list, which shows the list's description under its name. Edit or delete
  a list from the **⋯** menu on its screen, or swipe its row on the Tasks home.
  Only an empty list can be deleted, and the Inbox never can. Tap **New List**
  (the row after your lists) to create one; its screen opens right away. On
  the Mac, **New List** is the last row of the sidebar's Lists section. Links, Handoff, and system `openList` activities open the same screen.
- **Mobile Habit Creation:** Open **Habits** from its row on the **Tasks** tab,
  below the lists, then tap the **+** in its toolbar to create a core-backed
  daily habit with a cue and target count.
- **Mobile Calendar Creation:** Tap **New Event** in the **Calendar** tab to
  create a canonical Lorvex event; swipe an editable event row to edit or delete
  it. Today's schedule has no New Event footer.
- **Via AI:** Ask your connected AI client to create a task. The AI calls the
  `create_task` MCP tool and returns the full created task object.

### Moving Between Lists

Drag a task row onto a different list in the sidebar to move it. To reassign
several at once, select multiple tasks and use the **Lists** submenu in the
workspace selection menu — the batch menu that appears in the header while a
selection is active.

### Recurrence

In Task Detail, open the **Recurrence** row and choose a pattern:

- Daily, weekly, monthly, yearly with standard intervals
- Custom day-of-week patterns

The task detail view shows the saved repeat rule and skipped occurrence count.
On iPhone and iPad, Task Detail opens a full recurrence builder — a repeat
toggle, a frequency picker, an interval stepper, and weekday chips (for weekly
repeats) — matching the macOS detail editor.
Advanced recurrence fields such as end-by date or occurrence count remain
available through MCP recurrence tools.

### Tags

Tags are free-form labels you attach to tasks. On the Mac, the task detail's
Tags row opens a picker over every tag in use: type to find a tag or to name a
new one, and click a tag to put it on the task or take it off. The List row
beside it is a menu of your lists. Use tags to filter and organize your task
lists. The MCP host
exposes tag management tools so your AI client can tag tasks during capture or
triage.

### Batch Operations

Select multiple tasks by ⌘-clicking rows (⇧-click extends a range). The
workspace selection menu — the batch menu in the header while a selection is
active — also offers **Select All** and **Clear Selection**. With tasks selected:

- **Complete** — marks all selected tasks complete.
- **Defer** — defers all selected tasks to tomorrow.
- **Move to List** — reassigns all selected tasks to a different list.
- **Cancel** — marks all selected tasks cancelled.
- **Reopen** — reopens tasks in the selection that are completed, cancelled, or
  deferred.

On iPhone and iPad, tap **Select** in the Tasks workspace toolbar, then tap task
rows to select them; a bottom action bar offers Complete, Defer, and Reopen.

---

## Calendar & EventKit

### Viewing Calendar Events

The **Calendar** workspace shows a merged timeline of Lorvex planning blocks
and Apple Calendar events. EventKit events appear in a distinct style alongside
your Lorvex tasks so you can see scheduling conflicts at a glance.
Use the row buttons or context menu to edit or delete Lorvex-owned events.
Imported EventKit events are read-only overlays.

An event that lasts 24 hours or more appears in the all-day row of each day it
covers. A shorter event that runs past midnight appears on both days: the
first shows when it starts, and the second shows when it ends.

Calendar permission is required to display EventKit events. If permission is
denied, Lorvex shows only its own planning blocks with a permission prompt in
the Settings diagnostics panel.

### Creating and Editing Events

On the Mac, click **+** (Create Event) in the Calendar toolbar, or click or
drag across empty time in the grid. On iPhone and iPad, tap **New Event** in
the **Calendar** tab. An event from the toolbar or **New Event** starts at the
next full hour and lasts one hour; a click on the grid starts at that time,
and a drag covers the time you dragged across.

**Start** and **End** each have a day and, unless the event is all day, a
time, so an event can run overnight, such as from 10 PM to 1 AM, or across
several days. Changing the start moves the end with it, so the event keeps its
length. Picking an end time earlier than the start time ends the event the
next day. An event can't be saved while its end is not after its start.

To move an event, drag it in the grid; on iPhone and iPad, touch and hold it
first. On the Mac, drag an event's top or bottom edge to change when it starts
or ends. Repeating events and events that continue past midnight into the next
day can't be dragged; open them to change their times. An event that ends at
exactly midnight counts as a one-day event and drags like any other.

When you edit one occurrence of a repeating event and change how many days it
spans, the change applies to this event or to this and the following events;
**All Events** is not offered for that edit.

### Importing from System Calendars

In **Settings → Calendar**, choose which Apple Calendar calendars to overlay.
Lorvex reads those calendars through EventKit and merges their events into the
Calendar workspace view. Import failures (permission errors, missing calendars)
are recorded in the import report visible in Settings diagnostics.

### Exporting Lorvex Events to System Calendar (macOS)

Write-back to the system Calendar is a **macOS-only** feature. On macOS, when
you create or update a Lorvex calendar event, Lorvex can write it through
EventKit into a dedicated Lorvex calendar as a write-through copy. This keeps
the rest of your Apple ecosystem (the system Calendar, Siri, and any
calendar-aware apps) aware of your Lorvex schedule without duplicating data
ownership. The Lorvex database remains authoritative; EventKit holds a mirrored
copy.

Enable this in **Settings → Calendar → Two-Way Calendar Sync**.
If the write fails (permission denied, calendar not available), Settings
diagnostics show the export report so you can retry after granting permission.

On iPhone and iPad, Lorvex reads the system calendar for display and planning
but does not write to Apple Calendar; calendar events you create there stay
Lorvex-native. Those events still sync across your devices
through iCloud (Lorvex's own CloudKit sync).

### ICS Export

To export Lorvex calendar events as an ICS file:

- **macOS:** open **File → Export Calendar…** and save the `.ics` file. It
  holds the dates the Calendar workspace has loaded.
- **iPhone and iPad:** open **Settings → Data Export**, tap **Export Calendar**,
  then **Share Calendar**. The file holds your events from today through the
  next 30 days.

The AI client can also trigger ICS export via the `export_calendar_ics` MCP tool.

---

## Reviews & Memory

### Daily Review

The **Review** workspace opens on today's review, one page per day:

- One sentence reading the day: how many tasks you finished, how many due
  tasks are still open, and how many habits you kept.
- **What moved forward**: the tasks you finished that day.
- **Still open**: the tasks due that day that are not done yet. Tap a task's
  circle to complete it, or its title to open it. **Move All to Tomorrow**
  beside the heading plans every listed task for tomorrow; to move one task,
  use its context menu (or, on macOS, the **Move to Tomorrow** button that
  appears when you point at the row). A moved task stays listed, since it is
  still due that day, and says when it is planned.
- **Habits**: every habit as it stood that day. Tap a habit to check it in on
  that day, so a check-in you forgot can be made up from the review.
- Two one-tap scales, **How did it feel?** and **Energy**. The level you pick
  is named under its dot, from **Rough** to **Great** and from **Drained** to
  **Full**.
- **Tomorrow**, while you review today: tomorrow's events and the tasks
  planned for it, or a line saying nothing is planned yet.
- A **Note** field. The rarer **Wins**, **Blockers**, and **Learnings** fields
  fold behind one line under it.

Everything saves as you change it; there is no Save button. On macOS, step to
an earlier day with the arrows or the date chip in the toolbar. On iPhone and
iPad, the **Review** tab shows the same page; open an earlier day from the
week page's day list, and use **Return to today** to come back. Each day has
one review record, shared by every device and by MCP tools.

### Weekly Review

Switch the review to **Weekly** (macOS toolbar) or **Week** (iPhone and iPad)
to read the week on one page:

- One sentence: how many tasks you finished, how many new ones came in, and
  how many are overdue.
- Under it, a bar for each of the week's seven days, as tall as the number
  of tasks you finished that day. It appears once you finished anything that
  week.
- **What moved forward**: the week's top finished tasks.
- **The days**: each day's review, which opens that day.
- A question about the task pushed off most often, once it has been pushed
  three or more times: **Move to Someday** parks it until it matters.
- **Overdue**: open tasks past their due date, earliest first, each with how
  long ago it was due. The list shows up to five and counts the rest.
- **Kept getting pushed**: other tasks you deferred again and again.
- **The Week Ahead**, while you review the current week: each of the next
  seven days that has something on it, with its events and scheduled tasks
  and their start times. A day lists four items and counts the rest.
- How many ideas wait in Someday.

Each task appears once on the page, and an overdue or pushed task opens when
you tap it. Your AI client can read a summary of the week through the
`get_weekly_brief` tool.

On iPhone and iPad, **Share Daily** and **Share Weekly** in the Review toolbar
send the page as plain text in your language. A day sends its date, how it felt
and its energy, and what you wrote; a week sends its dates, its sentence, what
moved forward, the overdue tasks, the tasks that kept getting pushed, and the
Someday line. Dates are written out, so the text still reads right later.

### Memory

Lorvex keeps a memory store — AI-managed notes, observations, and context
snapshots the assistant remembers about you as a key→value store with last-write
semantics. On macOS, open **Memory** from the sidebar's footer, beside
Settings, or press **⌘6**. You can browse, search, write, and delete entries; edits
are synced across your devices.

On iPhone and iPad, Memory is its own row on the **Tasks** tab, below the
lists. Use it to review recent context entries or write a compact key/content
memory update through the same core path used by macOS and MCP tools.

## MCP & AI Integration

### How the MCP Host Works

`LorvexMCPHost` is a command-line helper bundled inside the app. Your AI client
(Claude, Codex, or any MCP-capable client) launches it as a subprocess over
stdio. The helper connects to the same `LorvexCoreServicing` boundary as the
app, so all AI writes go through the same data path, audit log, and sync
invariants as in-app mutations.

The host is stateless per invocation: each stdio session is a fresh process.
The Lorvex database is the persistent state.

### Tool Catalog

The MCP host exposes tools across these domains:

| Domain | Example tools |
|---|---|
| **System / Overview** | `get_overview`, `get_setup_status`, `get_session_context`, `get_sync_status` |
| **Tasks** | `create_task`, `update_task`, `get_task`, `list_tasks`, `search_tasks`, `complete_task`, `cancel_task`, `reopen_task`, `defer_task`, `move_task_to_list`, `append_to_task_body`, `get_deferred_tasks` |
| **Batch tasks** | `batch_create_tasks`, `batch_update_tasks`, `batch_defer_tasks`, `batch_complete_tasks`, `batch_reopen_tasks`, `batch_move_tasks` |
| **Day planning** | `start_task`, `pause_task`, `propose_daily_schedule`, `save_daily_schedule`, `get_daily_schedule`, `set_daily_briefing` |
| **Lists & tags** | `create_list`, `update_list`, `delete_list`, `archive_list`, `unarchive_list`, `get_lists`, `get_list`, `get_list_health_snapshot`, `list_all_tags`, `rename_tag` |
| **Calendar** | `create_calendar_event`, `update_calendar_event`, `delete_calendar_event`, `get_calendar_timeline`, `search_calendar_events`, `batch_create_calendar_events`, `edit_scoped_calendar_event`, `delete_scoped_calendar_event`, `export_calendar_ics`, `add_calendar_event_exception`, `remove_calendar_event_exception`, `link_task_to_event`, `unlink_task_from_event`, `link_task_to_provider_event`, `unlink_task_from_provider_event`, `get_linked_events_for_task`, `get_linked_tasks_for_event` |
| **ICS export** | `export_calendar_ics` |
| **Habits** | `create_habit`, `update_habit`, `delete_habit`, `complete_habit`, `uncomplete_habit`, `batch_complete_habits`, `get_habits`, `get_habit_completions`, `get_habit_stats`, `get_habit_reminder_policies`, `upsert_habit_reminder_policy` |
| **Reviews** | `get_daily_review`, `add_daily_review`, `amend_daily_review`, `get_weekly_brief`, `get_review_history` |
| **Memory** | `read_memory`, `write_memory`, `delete_memory` |
| **Checklists** | `add_task_checklist_item`, `update_task_checklist_item`, `toggle_task_checklist_item`, `reorder_task_checklist_items`, `remove_task_checklist_item` |
| **Recurrence** | `set_task_recurrence`, `remove_task_recurrence`, `add_task_recurrence_exception`, `remove_task_recurrence_exception` |
| **Reminders** | `add_task_reminder`, `set_task_reminders`, `remove_task_reminder`, `get_due_task_reminders`, `get_upcoming_task_reminders` |
| **AI context** | `set_task_ai_notes`, `set_list_ai_notes` |
| **Dependencies** | `get_dependency_graph`, `get_upcoming_tasks` |
| **Data export** | `export_data` |
| **Preferences** | `get_all_preferences`, `get_preference`, `set_preference`, `complete_setup` |
| **Audit / logs** | `get_ai_changelog`, `get_recent_logs` |
| **Guidance** | `get_guide` |

Every write tool returns the complete updated object. The AI always sees the
resulting state, not just a success flag.

### Idempotency Keys

Create and update tools accept an optional `idempotency_key` string. If the
client submits the same key twice (for example, after a network retry), Lorvex
returns the result of the first operation instead of creating a duplicate. Use a
UUID or a deterministic hash of the intended operation as the key. If a helper
stops after committing the mutation but before saving its full response, Lorvex
returns `idempotency_response_unavailable`; inspect current state rather than
retrying the mutation under a new key.

---

## Widgets & Watch

### Widgets

Lorvex widgets live on the iPhone and iPad Home Screen and Lock Screen, and on
the Mac desktop and in Notification Center. On iPhone or iPad, long-press the
Home Screen, tap **Edit**, then **Add Widget**, and search for **Lorvex**. On a
Mac, Control-click the desktop and choose **Edit Widgets**.

- **Today** (Small, Medium, Large, and the Lock Screen families) leads with the
  task at the top of Today and its ring, which fills while the task's saved
  time runs. The tasks after it follow in Today's order, each with its circle
  and its time or estimate. Large opens with the assistant's briefing.
- **Habits** (Small, Medium, and Lock Screen circular) shows today's habits as
  a grid of rings in each habit's color, with its symbol inside. A habit
  counted several times a day draws one arc per check-in. With more habits
  than the grid holds, the ones not yet done come first and the last tile
  counts the rest.
- **Daily Progress** (Small, and Lock Screen circular and inline) fills a ring
  with the tasks done today against those plus the tasks still on Today.

Tapping a task's circle completes it, and tapping a habit's ring checks the
habit in, without opening the app. Those are the only controls on a widget,
which deliberately leaves out destructive actions. Tapping a task's title
opens that task; tapping anywhere else opens Today, or Habits from the Habits
widget.

Widgets refresh from a shared App Group snapshot the main app publishes. If the
App Group entitlement is not configured for your build, widgets show preview
data.

### Control Center

Lorvex provides a control for Control Center on iPhone, iPad, and Mac. It shows
the task at the top of Today and opens Lorvex directly to Today when tapped.
On iPhone or iPad, swipe down to open Control Center, long-press to enter edit
mode, tap **＋ Add a Control**, and search for **Lorvex Today**. On a Mac, open
Control Center from the menu bar, click **Edit Controls**, and search for
**Lorvex Today**.

### Watch App

The `LorvexWatchApp` companion shows Today's list on Apple Watch, led by the
task at its top with a ring while its saved time runs. The iPhone projects the
bounded task, habit, briefing, and aggregate subset the Watch actually consumes
into a versioned, workspace-fenced replica. WatchConnectivity carries that
latest-state replica,
and the Watch atomically stores it as `watch_replica_v1.json` in its own App
Group container. The iPhone's fuller `widget_snapshot.json` remains local to
the WidgetKit surfaces; it is not the Watch transport contract.

**Completing, starting, pausing, canceling, or deferring a task** from the
Watch is forwarded to iPhone over WatchConnectivity. The Watch persists every command before updating
its UI, keeps it until a checksum- and identity-bound application ACK arrives,
and retries temporary transport or phone failures in FIFO order. The phone
records the terminal receipt in SQLite in the same transaction as the canonical
domain write, then publishes a fresh authoritative replica. Quick capture and
habit completion use the same durable path. A terminal rejection remains visible
on the Watch until dismissed; previews without a forwarder stay read-only.

### Watch Complications

Lorvex ships the "Lorvex Today" complication, backed by the Watch's atomically
stored replica (shared with the Watch app, not with the iPhone Widget
extension). It supports
circular, rectangular, inline, and watchOS corner accessory families. Add it
from the Watch app or directly from a watch-face customization flow.

---

## Sync & Export

### CloudKit (Status)

With **Sync with iCloud** turned on, Lorvex syncs through Apple's `CKSyncEngine`: the Swift sync
outbox is sent to the private CloudKit database, and changes from your other
devices are fetched into the local store.
Core planning entities such as tasks, lists, habits, calendar events, memory,
and daily briefings route through the same native inbound sync
engine used by the Swift core tests. Real iCloud writes require a provisioned
CloudKit container and a logged-in iCloud account.

For local testing:

```bash
# Turn sync on and write to the private CloudKit database (provisioned build
# only); any other value of LORVEX_CLOUD_SYNC forces sync off
LORVEX_CLOUD_SYNC=live ./script/build_and_run.sh
```

**Settings → Cloud Sync** holds the **Sync with iCloud** switch and shows the account and pause status,
and a Last Cycle panel with the latest pass's counts and any failure text.

While sync is on, `CKSyncEngine` fetches changes when a Lorvex remote-change push
arrives and on its own schedule, and it keeps its change tokens as a checkpoint
in the local SQLite database. The native inbound processor commits fetched
records in one SQLite transaction before the checkpoint that covers them is
saved.

The inbound boundary applies decoded CloudKit records through the native
`Apply.applyEnvelope` registry with typed HLC LWW gates, tombstones,
redirect-aware pending inbox draining, and conflict logging. Settings shows the
applied, skipped, deferred, remapped, replayed, and undecodable counts from the
latest sync pass.

### JSON / CSV / ZIP Export

From **Settings → Data → Export** on the Mac, or **Settings › Data Export ›
Categories** on iPhone and iPad, choose the categories you want. They are
grouped as **Planning** (tasks, lists, tags, habits), **Calendar** (events and
the links between tasks and events), **Reviews & Assistant** (daily reviews,
daily briefings, memory), and **Settings** (preferences); one button selects
every category, or clears them once all are selected (on the Mac it sits at the
end of the Export header). On the Mac, pick **JSON**, **CSV**, or **ZIP** (one
JSON file per category) under **Format** and click **Export…**; the note under
the group says what the chosen format holds and whether Lorvex can import it
again. On iPhone and iPad, tap the format's export button.

Human JSON/ZIP task exports include an Apple-native task-state graph for the most
faithful same-app import, alongside portable task JSON. The native graph includes
deletion high-waters and opaque future-field state so deleted task-domain records
do not silently reappear after restore. It never installs CloudKit account
receipts or the source device as this device's runtime identity; a single-file
JSON provenance header may still describe which Apple device produced it. If the
target already contains tasks or the native graph's list/tag roots were not
selected, import safely uses the portable merge instead. CSV is portable only.

Import is non-destructive, not an authoritative iCloud rollback. With iCloud
sync turned on, Lorvex first runs one sync pass so the import compares
against the latest records from your other devices; if that pass fails, the
import still proceeds against local data. Imported records then upload to
iCloud like any other change. When sync is off, import compares only with local
data; enable sync first when current iCloud state must participate in collision
decisions.

A file Lorvex can't import is turned away before anything is written, with one
sentence saying why: the file is empty, isn't a Lorvex backup (or is damaged
past recognition), was made by a newer version of Lorvex (update this device,
then try again), is a damaged backup (export it again on the device it came
from), or is larger than a backup can be.

Once an import has run, the summary under Import Data says what came back: how
many records were imported and how many were already present, and a line for
each category. When some records did not come back whole, two short lists name
them the way you know them (a task's title, a list's name, a review's date):
the records that were not imported, and the tasks that were restored without
some of their details, such as their reminders or repeat rule. A long list
ends with a count of the rest.

The AI client can request portable exports via the `export_data` MCP tool.

### Spotlight Indexing

The Lorvex Mac app indexes tasks in macOS CoreSpotlight automatically. Search
for any task title in macOS Spotlight, and tapping a result opens the task
detail view via a `lorvex://task/<id>` deep link. Lists, habits, calendar
events, and daily reviews are indexed by name (or date) the same way. Only
titles and names are indexed — never notes, checklist text, or other private
free text.

Spotlight re-indexes whenever the app refreshes its snapshot. To force a
re-index, use **Task → Refresh (⌘R)** on macOS.

---

## Keyboard Shortcuts

### Global (macOS)

| Shortcut | Action |
|---|---|
| ⌘N | New task (focuses the quick-add field) |
| ⌘K | Command Palette: find a task, go somewhere, or capture |
| ⌘F | Find: focus the search field in All Tasks or Memory; from any other workspace, open All Tasks and focus its search field |
| ⌘1 | Today |
| ⌘2 | Calendar |
| ⌘3 | All Tasks |
| ⌘4 | Review |
| ⌘5 | Habits |
| ⌘6 | Memory |
| ⇧⌘1–⇧⌘5 | Open Today, Calendar, All Tasks, Review, or Habits in its own window |
| ⌘← / ⌘→ | Previous / next day, week, or month in Calendar, and day or week in Review (the keys swap in right-to-left languages) |
| ⌃⌘S | Show or hide the sidebar |
| ⌘R | Refresh data |
| ⌘, | Settings |

The numeric accelerators follow the sidebar from top to bottom, then Memory in
its footer (⌘1–⌘6). Adding ⇧ opens the same destination in its own window
(Workspace menu); Memory has no separate window. In the Command Palette (⌘K),
type the start of a destination's or a list's name and press Return to go
there; any other text becomes a new task on Return, with matching tasks listed
below it to open instead. In Review, ⌘← and ⌘→ move the cursor instead while
you type a note. Lists has no numeric shortcut and no sidebar row of its
own — the sidebar's list rows scope the Tasks workspace. The Lists catalog is
reached from the Navigate menu or the Command Palette (⌘K), and the Workspace
menu opens it in its own window.

### Task Operations (macOS)

These act on the selected task.

| Shortcut | Action |
|---|---|
| ⌘⇧I | Show task detail |
| ⌘S | Save task edits |
| ⌘⇧S | Start or pause task |
| ⌘⇧D | Defer to tomorrow |
| ⌘⇧Return | Complete task |
| ⌘⇧O | Reopen task |
| ⌘⌫ | Cancel task |

### Quick-Add Field (macOS)

The inline quick-add sits under today's tasks on Today and at the top of the
Tasks list; ⌘N (or File → New Task) focuses it.

| Shortcut | Action |
|---|---|
| Return | Save the task and keep the field focused for the next one |

On iPhone and iPad, the **+** opens a capture sheet instead: fill in the title
(and optional notes) and tap **Capture**, or tap **Cancel** to dismiss.

---

## Handoff & Spotlight

### Continuing on Another Device

Lorvex advertises Apple Handoff activity from macOS. When the Lorvex Mac app is
open to a task or workspace, and your other Apple devices are signed into the
same iCloud account, a Handoff icon for that view appears on those devices — in
the Dock on another Mac, or the App Switcher on iPhone and iPad. Click or tap it
to open the same view there. The iPhone and iPad app can continue a Handoff
started on a Mac, but it does not advertise its own activity, so Handoff flows
from a Mac to another device, not the reverse.

Handoff uses the `lorvex://` URL scheme to encode the destination workspace and
current task. It does not transfer database content — both devices must have
access to the same database (either local or via CloudKit sync when available).

### Finding Tasks via Spotlight

On **macOS**, press ⌘Space and type any part of a task title. Lorvex results
appear under the Lorvex category. Pressing Return or clicking the result opens
task detail inside the app. Spotlight indexing is a macOS feature; the iPhone
and iPad apps do not index into iOS Search.

Spotlight results carry `lorvex://task/<escaped-id>` links. If the app is not
installed or the database is unavailable, the link cannot resolve.

---

## Troubleshooting

### App won't launch

If `Lorvex.app` quits immediately after opening:

1. Check that the macOS version is 26 or later (Lorvex requires macOS 26+).
2. If you built from source, confirm `swift build` completed without errors.
3. Open Console.app, filter by process name `Lorvex`, and look for crash
   reports or permission errors immediately after the launch timestamp.
4. Try launching from the terminal to see stderr:
   ```bash
   /Applications/Lorvex.app/Contents/MacOS/Lorvex
   ```

### MCP host not found by client

If your AI client reports that the MCP server could not be started or the
`LorvexMCPHost` binary is not found:

1. Confirm the app bundle is built and placed where the config points:
   ```bash
   ls /Applications/Lorvex.app/Contents/Helpers/LorvexMCPHost.app/Contents/MacOS/LorvexMCPHost
   ```
2. Regenerate the MCP client config to pick up the correct path:
   ```bash
   python3 script/generate_mcp_client_config.py \
     --app-bundle /Applications/Lorvex.app
   ```
3. Run the smoke test to confirm the host starts cleanly:
   ```bash
   python3 script/mcp_stdio_smoke.py
   ```
   This source-build command uses a temporary database. Do not point
   `MCP_HOST_BINARY` at an installed sandboxed helper: the corresponding release
   smoke is intentionally destructive and is reserved for the packaging
   workflow with an explicit `LORVEX_ALLOW_DESTRUCTIVE_APP_GROUP_RESET=1`
   acknowledgement.
4. Check that the `command` path in the client config points at the
   `Contents/Helpers/LorvexMCPHost.app/Contents/MacOS/LorvexMCPHost` path
   inside the bundle, not a stale path from a previous build.

### CloudKit shows "No Account"

Lorvex requires an iCloud account signed in on the device to use CloudKit sync.

1. Verify you are signed into iCloud in **System Settings → Apple ID**.
2. Confirm the CloudKit container (`iCloud.com.lorvex.apple`) is provisioned in
   your Apple Developer portal and the app is built with the CloudKit entitlements
   variant (`LorvexAppleCloudKit.entitlements`; Mac App Store builds use
   `LorvexAppleCloudKitAppStore.entitlements`). See `docs/DISTRIBUTION.md §8`.
3. If the app shows "No Account" even with an active iCloud session, the build
   may be using the basic entitlements file (without iCloud keys). Check
   **Settings → Diagnostics** for the CloudKit error detail.
4. For local development, `LORVEX_CLOUD_SYNC` overrides the Settings
   choice: `live` turns sync on and any other value turns it off.

### EventKit permission denied

If Lorvex cannot read calendar events after you granted
permission:

1. Open **System Settings → Privacy & Security → Calendars** (macOS) or
   **Settings → Privacy → Calendars** (iOS) and confirm Lorvex has full access.
2. If the permission entry is missing, delete the app and reinstall — the system
   permission prompt reappears on first access.
3. After granting permission, use **Task → Refresh (⌘R)** (macOS) or pull to
   refresh (iOS) to trigger a new EventKit read. The Settings diagnostics panel
   shows the latest import/export report with any error detail.
4. If `EKAuthorizationStatus.denied` is logged, the only recovery path is
   granting access in System Settings; the app cannot re-prompt once denied.

### watchOS complication shows stale data

The complication reads a snapshot file from the shared App Group container. If
the data is stale:

1. Open the Lorvex app on iPhone or Mac and let it refresh (pull to refresh or
   use **Task → Refresh (⌘R)**). The app writes a fresh snapshot to the shared
   container on every refresh.
2. On the watch, force-quit the Lorvex app and reopen it; this triggers a fresh
   read from the container.
3. If the complication is still stale, check that the App Group entitlement
   (`group.com.lorvex.apple`) is configured in your build and that both the iOS
   app and the watch app share the same App Group ID. The current default build
   uses a no-op publisher when the App Group is not set up; complications in
   that configuration always show placeholder data.
4. Background complication refresh requires a WatchConnectivity session between
   the watch and phone. The phone forwards snapshots to the watch over WCSession
   and the watch forwards its mutations back; complication timelines reload from
   the pushed snapshots.
