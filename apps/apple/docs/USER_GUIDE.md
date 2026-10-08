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

### From Any App (macOS)

Quick Capture is also a small window that opens over whatever app you are using,
so a thought goes into Lorvex without switching to it. It stays off until you
choose a shortcut: open **Settings → General → Quick Capture** and pick
**⌃⌥Space**, **⌃Space**, **⌥Space**, or **⌃⇧Space**. Press the shortcut again,
press **Escape**, or click another window to close it. ⌃Space and ⌃⌥Space are
also the macOS shortcuts for switching input sources, so when those are turned
on in System Settings, choose one of the other two. If another app already uses
the shortcut you pick, Settings says so under the picker.

Type a line and press **Return**. The line is read like any capture field's (a
day, a time, a length, a `#list`, a priority), the details show under the field
before you save, and the window names the list the task landed in before it
closes. A line that names no day stays undated and goes to your default list
(the Inbox unless you chose another) or the list you name. A line you started
and then walked away from is still there the next time the window opens;
**Escape** throws it away.

**File → Quick Capture** (⌥⌘N), **Quick Capture** in the Command Palette (⌘K),
and **Quick Capture** in the Dock menu open the same window without the global
shortcut.

The shortcut and the menu bar icon work while Lorvex is running. To have it open
when you sign in to your Mac, turn on **Settings → General → Open at Login**.
The switch shows what macOS has set, so it also follows a change you make in
**System Settings → General → Login Items & Extensions**. If you turned it on there but
macOS still waits for your approval, a row under the switch says so, and **Open
Login Items** takes you to the pane where you turn Lorvex on.

### Words Quick Capture Understands

Every capture field reads a few details out of what you type and shows them
under the field before you save; the rest becomes the title. That covers the
quick-add fields on Today, in the Tasks list, and on a list's page, the menu
bar's field, the Quick Capture window, the **New Task** row of the Command
Palette (⌘K), and the capture sheet on iPhone and iPad. English and Chinese both work. Chinese needs no spaces ("明天开会30分钟") and reads the same
in Traditional characters ("後天開會", "下週三", "30分鐘"); the title keeps the
characters you typed.

| Detail | English | Chinese |
|---|---|---|
| Day | today, tonight, tomorrow, Friday, this Friday, next Friday, next week, weekend, in 3 days | 今天, 明天, 后天, 大后天, 周三 / 星期三 / 礼拜三, 这周三, 下周三, 下周, 周末, 3天后 |
| Date | Oct 5, October 5th, 5 Oct, 2026-10-05 | 10月5日, 10月5号, 5号 |
| Date range | May 3-5, May 3 to 5, May 3 through 5, May 30 - June 2, 3-5 May, from May 3 to May 5, between May 3 and May 5 | 5月3日到5日, 5月3日至5日, 5月3日-5日, 5月3日到5月5日, 5月30日到6月2日, 从5月3日到5月5日, 3号到5号 |
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
means the coming 5th unless it numbers a thing: 5号楼 (building 5), 2号线
(line 2), and 5号电池 (AA batteries) stay in the title. A time plans the task
at that time for its length, or for half an hour, on the day you wrote or
today when you wrote none. A time from 1 to 6 o'clock with no AM, PM, or part
of the day (下午, 晚上) is in the afternoon.

A date range plans the task on its first day and makes it due on its last:
"Trip May 3-5" is planned for May 3 and due May 5, and 出差5月3日到5日 does the
same. A month written once serves both days ("May 3-5", "3-5 May", 5月3日到5日),
each day may carry its own month ("May 30 - June 2", 5月30日到6月2日), and a
year written after the end places the range ("Dec 30 - Jan 2, 2028"). The end
must come after the start, and an end in an earlier month falls in the next
year ("Dec 30 - Jan 2" runs into January). A range names both the planned day
and the due day, so another day in the same line stays in the title. Text
written like a range that names no days ("May 5-3", "May 3 - Feb 30") stays in
the title whole, and so do counts and references ("pages 3-5", "score 3-5"). A
number alone before a spaced dash belongs to the title: "Sprint 12 - 20 May"
is planned for May 20, while "12-20 May" and "from 12 to 20 May" are ranges. A
range ending in AM or PM is a time ("May 3-5pm"), and a weekday range
("Mon-Fri") is not a date range. English needs a month in a range, so "the 3rd
to the 5th" stays in the title; Chinese reads a range of days of the month in
号 ("3号到5号") and leaves "3日到5日" alone.

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
| Date range | 5月3日から5日まで, 5月3日〜5日, 5月3日から5月5日まで, 5/3〜5/5 | 5월 3일부터 5일까지, 5월 3일~5일, 5월 3일부터 5월 5일까지, 5/3~5/5 |
| Due day | 金曜までに, 今日中, 10/5締切 | 금요일까지, 내일까지, 10월 5일 마감 |
| Time | 午後3時, 3時半, 9時20分, 夜8時, 午後3:30, 正午; 15時から16時まで, 3〜5時 | 오후 3시, 3시 반, 9시 20분, 저녁 7시, 오후 세 시, 오후 3:30, 정오, 자정; 3시부터 4시까지, 오후 3시~5시 |
| Repeat | 毎日, 毎週, 隔週, 毎週月曜, 毎週月・水・金, 平日毎日, 毎月, 毎月5日, 毎年, 3日ごと, 1日おき | 매일, 매주, 격주, 매주 월요일, 매주 월수금, 월요일마다, 평일마다, 매달, 매달 5일, 매년, 3일마다 |
| Length | 30分, 2時間, 1時間半, 1時間30分 | 30분, 2시간, 1시간 반, 1시간 30분, 한 시간 |
| Priority | 至急, 急ぎ, 緊急 | 긴급 |

The night runs past midnight in both, as in Chinese: 夜12時 and 밤 12시 mean
00:00 the next day, and 今夜8時 and 오늘 밤 8시 mean 8 PM today.

A date range works as in English: 5月3日から5日まで and 5월 3일부터 5일까지
plan the task on May 3 and make it due on May 5, with the particle after the
range going with it. Both need a month, so "3日から5日まで" and
"3일부터 5일까지" stay in the title, and "5日間" and "5일간" count days rather
than end a range.

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
| Date range | du 3 au 5 mai, du 30 mai au 2 juin, du 1er au 5 mai, du lundi 3 au mercredi 5 mai, entre le 3 et le 5 mai, 3-5 mai | de 3 a 5 de maio, de 30 de maio a 2 de junho, do dia 3 ao dia 5 de maio, entre os dias 3 e 5 de maio, 3-5 de maio |
| Due day | pour vendredi, d'ici demain, avant le 5 octobre, jusqu'au 5 octobre, vendredi au plus tard | até sexta, para o dia 5, prazo: 5 de outubro |
| Time | 15h, 15h30, à 9h, vers 18h, 8h du soir, 3h de l'après-midi, midi, à minuit; de 14h à 16h, 14h-16h30, entre 14h et 16h | 15h, às 15h30, por volta das 18h, às 3 da tarde, às 8 da noite, meio-dia, à meia-noite; das 14h às 16h, entre 14h e 16h |
| Repeat | tous les jours, chaque lundi, tous les lundis et jeudis, les lundis, un lundi sur deux, en semaine, tous les 15 jours, tous les mois, le 5 de chaque mois, chaque année; hebdomadairement at the end | todo dia, toda segunda, todas as segundas e quartas, aos sábados, às terças (at the end), dias úteis, a cada 15 dias, de 2 em 2 semanas, todo dia 5, todo ano; semanalmente at the end |
| Length | pendant 2h, 1h30min, 1,5 h, 30 min, 2 heures, une demi-heure, un quart d'heure | por 2h, 1h30min, 1,5 h, 30 min, 2 horas, meia hora, uma hora e meia |
| Priority | priorité haute, basse priorité, urgente | prioridade alta, baixa prioridade, urgente |

A date range plans the task on its first day and makes it due on its last,
and a month written once serves both days: "du 3 au 5 mai" and "de 3 a 5 de
maio" run from May 3 to May 5. The end must come after the start ("du 5 au 3
mai" stays in the title). Au, jusqu'au, a, ao, and até need no opening word when
the end names a month ("3 au 5 mai", "3 a 5 de maio"), while "et" and "e" join
the two days of a range only after entre. A range of days with no month needs
"dia" in Portuguese ("do dia 3 ao dia 5", "entre os dias 3 e 5"), since "de 3 a
5" may be a count or a time; French reads a range only with its month. As in
English, a number alone before a spaced dash belongs to the title ("Sprint 12 -
20 mai" is planned for May 20).

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
| Date range | del 3 al 5 de mayo, del 30 de mayo al 2 de junio, desde el 3 hasta el 5 de mayo, entre el 3 y el 5 de mayo, 3-5 de mayo, del 3 al 5 | dal 3 al 5 maggio, dal 30 maggio al 2 giugno, tra il 3 e il 5 maggio, dal 3 maggio al 5 maggio, 3-5 maggio, dal 3 al 10 |
| Due day | para el viernes, antes del viernes, hasta mañana, vence el 5 de octubre, el viernes a más tardar | entro venerdì, per venerdì, entro il 5 ottobre, scade il 5 ottobre, venerdì al più tardi |
| Time | a las 15:30, a las 3 de la tarde, a las 9 de la mañana, a las 8 de la noche, a las 3 y media, a la una, mediodía, a medianoche; de 3 a 4, de las 3 a las 4 de la tarde, entre las 3 y las 4 | alle 15, ore 15:30, alle 3 del pomeriggio, alle 9 di mattina, alle 8 di sera, alle 3 e mezza, all'una, mezzogiorno, a mezzanotte; dalle 3 alle 4, tra le 3 e le 4 |
| Repeat | todos los días, cada lunes, todos los lunes y jueves, los lunes (at the end), cada dos lunes, entre semana, cada 15 días, cada mes, el 5 de cada mes, cada año; diariamente at the end | ogni giorno, ogni lunedì, tutti i lunedì e giovedì, il lunedì (at the end), un lunedì sì e uno no, nei giorni feriali, ogni 15 giorni, ogni mese, il 5 di ogni mese, ogni anno; quotidianamente at the end |
| Length | durante 2 horas, por 2h, de 2 horas, 1h30, 30 min, 2 horas y media, media hora, una hora y media | per 2 ore, di 2 ore, 1h30, 30 min, 2 ore e mezza, mezz'ora, un'ora e mezza |
| Priority | prioridad alta, baja prioridad, urgente | priorità alta, bassa priorità, urgente |

A date range plans the task on its first day and makes it due on its last:
"del 3 al 5 de mayo" and "dal 3 al 5 maggio" run from May 3 to May 5, and a
month written once serves both days. The opening del or dal may be left out
when the end names a month ("3 al 5 de mayo", "3 al 5 maggio"), while "y" and
"e" join the two days of a range only after entre or tra. A range of days with
no month ("del 3 al 5", "dal 3 al 10") is read where a day alone is: only at
the end of the line or before a word that can follow a date, so "del 3 al 5
capítulos" is not a range. "De 3 a 4" and "dalle 3 alle 4" are time ranges, and
"de lunes a viernes" and "dal lunedì al venerdì" repeat. As in English, a
number alone before a spaced dash belongs to the title ("Sprint 12 - 20 de
mayo" is planned for May 20).

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

Russian and Ukrainian words are read when Russian or Ukrainian is among your
device's preferred languages, in any regional variant. The letter ё is optional
in Russian ("отчёт" and "отчет"), and the Ukrainian apostrophe may be typed
straight, curly, or as the modifier letter, or left out ("п'ятниця", "п’ятниця",
"пʼятниця", "пятниця"); the title keeps the letters you typed. Russian says a
clock time with "в" and Ukrainian with "о": "в 15:00", "в 3 часа дня", "о 15:00",
"о 3 годині дня". An hour from 1 to 6 with no part of the day is in the
afternoon ("в 3" is 3 PM) unless it is written with a zero ("06:30"), and a
part of the day sets the hour: "утра" ("ранку") is the morning, "дня" is noon
at 12 and the afternoon from 1 to 6, "вечера" ("вечора") is the evening, and
"ночи" ("ночі") runs past midnight, so "в 2 ночи" is 02:00 on the next day and
"в 11 ночи" is 23:00. A bare hour counts only at the end of the line or
before a word that can follow a time ("в 3 с Иваном", "о 3 з Іваном"), so "в 3
этапа" and "о 2 етапи" stay in the title, and so does a clock time that names a
deadline ("до 18:00", "после 18:00", "не позднее 18:00"). A time written
without a Russian or Ukrainian word ("3pm", "14:00-16:30") is read by English,
which also takes an English "at" or "from" in front of it.

| Detail | Russian | Ukrainian |
|---|---|---|
| Day | сегодня, сегодня вечером, завтра, завтра утром, послезавтра, в пятницу, в эту пятницу, в следующую пятницу, на следующей неделе, на выходных, через 3 дня | сьогодні, сьогодні ввечері, завтра, завтра вранці, післязавтра, у п'ятницю, у цю п'ятницю, у наступну п'ятницю, наступного тижня, на вихідних, через 3 дні |
| Date | 5 мая, 5-го мая, 5 янв., в понедельник, 5 октября, 5 мая 2027 года | 5 травня, 5-го травня, 5 січ., у понеділок, 5 жовтня, 5 травня 2027 року |
| Date range | с 3 по 5 мая, с 3 до 5 мая, от 3 до 5 мая, с 30 мая по 2 июня, 3–5 мая, 3-5 мая | з 3 по 5 травня, з 3 до 5 травня, від 3 до 5 травня, з 30 травня по 2 червня, 3–5 травня, 3-5 травня |
| Due day | до пятницы, к пятнице, до 5 мая, не позднее пятницы, срок: 5 мая, дедлайн 5 мая | до п'ятниці, до 5 травня, не пізніше п'ятниці, термін: 5 травня, дедлайн 5 травня |
| Time | в 15:00, в 15, в 3 часа дня, в 9 утра, в 7 вечера, в 2 ночи, в полдень, в полночь, около 15:00; с 14 до 16, с 14:00 до 16:00, с 9 утра до 6 вечера | о 15:00, о 15, о 3 годині дня, о 9 ранку, о 7 вечора, о 2 ночі, опівдні, опівночі, близько 15:00; з 14 до 16, з 14:00 до 16:00, з 9 ранку до 6 вечора |
| Repeat | каждый день, каждую неделю, каждый понедельник, каждый понедельник и четверг, по понедельникам, по будням, по выходным, каждые 2 дня, раз в неделю, 5-го числа каждого месяца; ежедневно at the end | щодня, щотижня, кожного понеділка, щопонеділка, по понеділках, по буднях, по вихідних, кожні 2 дні, раз на тиждень, 5 числа кожного місяця; щоденно at the end |
| Length | 30 минут, 30 мин, 2 часа, 2 ч, 1,5 часа, полтора часа, полчаса, на 30 минут, в течение 2 часов | 30 хвилин, 30 хв, 2 години, 2 год, 1,5 години, півтори години, півгодини, на 30 хвилин, протягом 2 годин |
| Priority | высокий приоритет, низкий приоритет, срочно (at the end, or "Срочно:" at the start) | високий пріоритет, низький пріоритет, терміново (at the end, or "Терміново:" at the start) |

A date range plans the task on its first day and makes it due on its last:
"с 3 по 5 мая" and "з 3 по 5 травня" run from May 3 to May 5, and a month
written once serves both days. The end must come after the start ("с 5 по 3
мая" stays in the title), and the end names a month, so "с 3 по 5" stays in the
title. As in English, a number alone before a spaced dash belongs to the title
("Sprint 12 - 20 мая" is planned for May 20), while "12-20 мая" is a range.
"С 14 до 16" and "з 14 до 16" are time ranges, but two bare hours count only
at the end of the line or before a word that can follow a time, so "с 14 до 16
страниц" stays in the title. They also stay after a word that names an amount
or numbered items ("Цена от 10 до 20", "Прочитать главы с 3 до 5", "Ціна від
10 до 20"), and a number before a percent or currency sign is never a time
("от 10 до 20 ₽", "20 %"). A date written in digits ("5.10") stays in the
title, since the order of its day and month depends on the region, and so does
a month name without a day number ("Майские праздники", "Травневі свята"). A
Ukrainian month abbreviation needs its dot ("5 січ.").

A weekday is a day only with a word before it: "в", "во", or "на" in Russian,
"у", "в", or "на" in Ukrainian, or the "с" ("з") that starts a day ("с
понедельника"). A weekday after "на" plans the task for that day ("билеты на
пятницу"). Alone, it stays in the title ("отчёт за понедельник", "Звіт за
понеділок"), and so does a capitalized weekday in the middle of a line, which is
a name ("Купить в Пятнице"). Среда is also the environment, so "Настроить среду
разработки" stays in the title. A weekday that names today means a week ahead,
"в эту пятницу" ("у цю п'ятницю") is this week's, and "в следующую пятницу"
("у наступну п'ятницю") is next week's.

"Через день" means both "in a day" and "every other day", so it stays in the
title in both languages; write "через 1 день" or "каждые 2 дня" ("через 1
день" or "кожні 2 дні") for the one you mean. Russian "ежедневно",
"еженедельно", "ежемесячно", and "ежегодно" and Ukrainian "щоденно",
"щотижнево", "щомісячно", and "щорічно" repeat only at the end of the line, so
"Ежедневно проверять почту" and the adjectives "Ежедневный отчёт" and "Щоденний
звіт" stay in the title, while the Ukrainian "щодня", "щотижня", "щомісяця", and
"щороку" repeat anywhere. A length says that it is one: an amount after
"через", "за", "по", "каждые" ("кожні"), or "раз в" ("раз на") names a moment or an
interval, not a length ("через 2 часа", "по 2 часа"), "2 часа в день" stays in
the title, "в 2 часа" is a time, and "час" or "година" alone is no length
("Час пик").

Polish words are read when Polish is among your device's preferred languages,
in any regional variant. The Polish letters are optional: ą, ć, ę, ń, ó, ś, ź,
and ż are read as the plain letter and ł as l ("środa" and "sroda", "łączność"
and "lacznosc"), and the title keeps the letters you typed. Polish says a clock
time with "o": "o 15:00", "o 15", "o 15-tej", "o godz. 15", "o 3 po południu".
An hour from 1 to 6 with no part of the day is in the afternoon ("o 3" is 3 PM)
unless it is written with a zero ("06:30"), and a part of the day sets the hour:
"rano" is the morning, "po południu" is noon at 12 and the afternoon from 1 to
6, "wieczorem" is the evening, and "w nocy" runs past midnight, so "o 2 w nocy"
is 02:00 on the next day and "o 11 w nocy" is 23:00. A bare hour counts only at
the end of the line or before a word that can follow a time ("o 3 z Anią"), so
"o 3 osoby" stays in the title, and so does a clock time that names a deadline
("do 18:00", "przed 18:00", "po 18:00", "najpóźniej o 18:00"). A time written
without a Polish word ("3pm", "14:00-16:30") is read by English, which also
takes an English "at" or "from" in front of it.

| Detail | Polish |
|---|---|
| Day | dziś, dziś wieczorem, jutro, jutro rano, pojutrze, na jutro, od jutra, w piątek, w ten piątek, w przyszły piątek, w przyszłym tygodniu, w weekend, za 3 dni, za tydzień |
| Date | 5 maja, 5. maja, 5-go maja, dnia 5 maja, 5 sty., w poniedziałek, 5 października, 5 maja 2027 r. |
| Date range | od 3 do 5 maja, od 30 maja do 2 czerwca, między 3 a 5 maja, 3–5 maja, 3-5 maja, od poniedziałku do środy |
| Due day | do piątku, do 5 maja, do jutra, najpóźniej w piątek, nie później niż do piątku, termin: 5 maja, deadline 5 maja |
| Time | o 15:00, o 15, o 15-tej, o 3 po południu, o 9 rano, o 7 wieczorem, o 2 w nocy, w południe, o północy, około 15:00; od 14 do 16, od 14:00 do 16:00, od 9 rano do 6 wieczorem, od 9-tej do 17-tej, godz. 14-16, między 14:00 a 16:00 |
| Repeat | co tydzień, co poniedziałek, co poniedziałek i czwartek, w poniedziałki, w dni robocze, w weekendy, co 2 dni, co drugi tydzień, raz w tygodniu, 5. każdego miesiąca; codziennie at the end |
| Length | 30 minut, 30 min, 2 godziny, 2 godz., 2 h, 1,5 godziny, półtorej godziny, pół godziny, kwadrans, na 30 minut, przez 2 godziny |
| Priority | wysoki priorytet, niski priorytet, pilne (at the end, or "Pilne:" at the start) |

A date range plans the task on its first day and makes it due on its last:
"od 3 do 5 maja" and "między 3 a 5 maja" run from May 3 to May 5, and a month
written once serves both days. A span of weekdays does the same: "od
poniedziałku do środy" plans the task on the coming Monday and makes it due on
the Wednesday after it, while "od poniedziałku do piątku" is the working week,
which repeats. The end must come after the start ("od 5 do 3
maja" stays in the title), and the end names a month, so "od 3 do 5" is never a
range of days. "Do" joins the two days only after "od", and "a" or "i" only
after "między". As in English, a number alone before a spaced dash belongs to
the title ("Sprint 12 - 20 maja" is planned for May 20), while "12-20 maja" is
a range. "Od 14 do 16" is a time range, but two bare hours count only at the
end of the line or before a word that can follow a time, so "od 14 do 16
stron" stays in the title. They also stay after a word that names an amount or
numbered items ("Cena od 10 do 20", "Przeczytać rozdziały od 3 do 5"), and a
number before a percent sign, a currency sign, or "zł" is never a time ("od 10
do 20 zł", "o 15%"). "Między 14 a 16" is a time range only with a colon, a
part of the day, or "godz." ("między 14:00 a 16:00"). A date written in digits
("5.10") stays in the title, since the order of its day and month depends on
the region, and so does a month name without a day number ("Majówka", "Raport
za maj"). A month abbreviation needs its dot ("5 sty."), since several are
ordinary words too. Easter and Christmas ("Wielkanoc", "Boże Narodzenie") are
not dates.

A weekday is a day only with a word before it: "w", "we", or "na", or the "od"
that starts a day ("od poniedziałku"). A weekday after "na" plans the task for
that day ("bilety na piątek"). Alone, it stays in the title ("raport z
poniedziałku"), and so does a capitalized weekday in the middle of a line, which
is a name ("Zadzwonić do Soboty"). So does a month with a capital letter after a
day number there: "Spotkanie na ul. 3 Maja" names a street, while "3 maja" is a
date. A weekday that names today means a week ahead, "w ten piątek" is this
week's, and "w przyszły piątek" is next week's. A weekday in the plural repeats
("w poniedziałki", "w poniedziałki i czwartki"), except Sunday: without its
ogonek, "w niedziele" is the same word as "w niedzielę" (on Sunday), so it
names the coming Sunday, and it repeats only in a list with another weekday in
the plural ("w soboty i niedziele").

"Codziennie", "cotygodniowo", "comiesięcznie", and "corocznie" repeat only at
the end of the line, so "Codziennie sprawdzać pocztę" and the adjectives
"Codzienny raport" and "Raport cotygodniowy" stay in the title, as do "2 razy w
tygodniu" and "na co dzień" (day to day). A length says that it is one: an
amount after "za", "co", "po", "o", "w", or "do" names a moment, an interval, or
a bound, not a length ("za 2 godziny", "co 2h", "za 15 min"), "2 godziny
dziennie" and "30 minut temu" stay in the title, and "godzina" alone is no
length ("Godzina szczytu").

Arabic words are read when Arabic is among your device's preferred languages,
in any regional variant. Vowel signs and tatweel are optional, and the letters
that are spelled in more than one way are read as one (أ, إ, آ as ا, ى as ي, ة
as ه), so "غداً", "غدًا", and "غدا" are the same word, and so are "الأربعاء" and
"الاربعاء"; the title keeps what you typed. The Arabic-Indic digits ("٣") and
the Extended Arabic-Indic digits ("۳") read as the digits they stand for.
Arabic says a clock time with "الساعة": "الساعة 3", "الساعة 3:30", "الساعة 3
مساءً", "عند الساعة 9 صباحاً". An hour from 1 to 6 with no part of the day is
in the afternoon ("الساعة 3" is 3 PM) unless it is written with a zero
("06:30"), and a part of the day sets the hour: "صباحاً" is the morning,
"ظهراً" is noon at 12 and the afternoon from 1 to 6, "مساءً" is the evening,
and "ليلاً" runs past midnight, so "الساعة 2 ليلاً" is 02:00 on the next day
and "الساعة 11 ليلاً" is 23:00. A part of the day beside the day phrase sets a
bare hour too: "غداً صباحاً الساعة 6" is 06:00. A bare number is never an hour
("اجتماع 3", and "3 م" counts meters), "12 صباحاً" and "12 مساءً" are not
read, and a clock time that names a deadline ("قبل الساعة 18:00", "حتى 18:00")
stays in the title. A time written without an Arabic word ("3pm",
"14:00-16:30") is read by English, which also takes an English "at" or "from"
in front of it.

| Detail | Arabic |
|---|---|
| Day | اليوم, الليلة, غداً, غداً صباحاً, بكرة, بعد غد, يوم الخميس, هذا الخميس, الخميس القادم, مساء الخميس, الأسبوع القادم, بعد 3 أيام, بعد أسبوع |
| Date | 5 مارس, 5 من مارس, يوم 5 مارس, بتاريخ 5 مارس, 5 كانون الثاني, 5 مارس 2027 |
| Date range | من 3 إلى 5 مارس, من 30 يناير إلى 2 فبراير, من 3 مارس حتى 5 أبريل, بين 3 و5 مارس, 3-5 مارس |
| Due day | قبل الخميس, حتى غداً, بحلول 5 مارس, لغاية الخميس القادم, الموعد النهائي: الخميس, موعد التسليم 5 مارس |
| Time | الساعة 3, الساعة 15:30, الساعة 3 مساءً, الساعة 9 صباحاً, الساعة 3 ونصف, الساعة 3 إلا ربع, عند منتصف الليل, في منتصف النهار; من الساعة 2 إلى 4, من 9 صباحاً إلى 5 مساءً, بين الساعة 2 و4, الساعة 2-4 |
| Repeat | كل يوم, كل أسبوع, كل اثنين, كل اثنين وخميس, كل يوم من الأحد إلى الخميس, كل يومين, كل 3 أيام, كل شهر, 5 من كل شهر, مرة في الأسبوع, مرة كل أسبوعين; يومياً at the end |
| Length | 20 دقيقة, 30 د, 3 ساعات, ساعتين, 1.5 ساعة, نصف ساعة, ربع ساعة, ساعة ونصف, لمدة ساعة |
| Priority | أولوية عالية, أولوية منخفضة, عاجل (at the end, or "عاجل:" at the start) |

A date range plans the task on its first day and makes it due on its last:
"من 3 إلى 5 مارس" and "بين 3 و5 مارس" run from March 3 to March 5, and a month
written once serves both days. The end must come after the start ("من 5 إلى 3
مارس" stays in the title), and the end names a month, so "من 3 إلى 5" stays in
the title. "إلى" joins the two days only after "من", and "و" only after "بين".
Two bare hours are not a time range either ("من 14 إلى 16 صفحة" stays in the
title): a range needs "الساعة", a part of the day, or a colon ("من الساعة 2
إلى 4", "من 2 إلى 4 مساءً", "من 14:00 إلى 16:00"). The months are the Gregorian
ones, in the names used across the Arab world (يناير, كانون الثاني, جانفي). A
month name needs its day number ("مارس" is also a verb), and a date written in
digits only ("5/3") or a Hijri date ("3 رمضان") stays in the title.

A weekday is a day only with a word before it: "يوم", "في يوم", "ليوم", or
"في" ("يوم الخميس"), "هذا" ("هذا الخميس"), or a part of the day ("مساء
الخميس"); or with a word for next after it ("الخميس القادم", "الجمعة
المقبلة"). Alone, it stays in the title ("صلاة الجمعة", "الجمعة العظيمة",
"اجتماع الخميس"), and so does a weekday in the past ("الخميس الماضي") or a
night ("ليلة الجمعة" is the night before Friday). A weekday that names today
means a week ahead, "هذا الخميس" is this week's, and "الخميس القادم" is the
coming one. Sunday needs its article ("الأحد"): without it "أحد" means
"someone", so "كل أحد" (everyone) and "يوم أحد" stay in the title.

"كل ساعتين" and "كل 15 دقيقة" are intervals shorter than a day, so they are
not repeats and stay in the title whole, as do "كل عام وأنتم بخير" (a
greeting) and "مرتين في الأسبوع" (twice a week). "يومياً", "أسبوعياً",
"شهرياً", and "سنوياً" repeat only at the end of the line, so the adjective in
"تقرير يومي" stays in the title. A length says that it is one: an amount after
"بعد", "كل", "قبل", "منذ", "خلال", or "في" names a moment or an interval, not a
length ("بعد 15 دقيقة", "كل ساعتين"), "20 دقيقة في اليوم" stays in the title,
and "ساعة" alone is a watch or a clock unless "لمدة" or an approximation opens
it ("لمدة ساعة", "حوالي ساعة"). Arabic attaches one-letter words to the next
word, and only the attached forms Lorvex lists are read: "و" between weekdays
("كل اثنين وخميس"), "ل" before an amount, a date, or a day ("لـ 20 دقيقة", "لـ
5 مارس", "ليوم الخميس"), and "ب" in "بحلول", "بالليل", and "بأولوية". Any other
attached word ("وغداً", "لغد") stays in the title. The working days and the
weekend are not read, because which days they are depends on the country.

Hindi words are read when Hindi is among your device's preferred languages, in
any regional variant. A word counts only as a whole word in Devanagari, so
"आजकल" (nowadays) and "कलयुग" hold no day, and a hyphen between two Devanagari
words joins them ("आज-कल"). Hindi writes its postpositions as separate words,
and the one that goes with a detail is read with it: "सोमवार को", "कल से", "5 बजे
की मीटिंग", "30 मिनट के लिए". The Devanagari digits ("५") read as the digits
they stand for, the nukta is optional ("ज़रूरी" and "जरूरी", "हफ़्ते" and
"हफ्ते"), the candrabindu and the anusvara are one sign ("पाँच" and "पांच"),
and a nasal conjunct may be spelled either way ("सितंबर" and "सितम्बर"); the
title keeps what you typed. Hindi written in Latin letters ("kal subah 9 baje")
is not read. English is read beside Hindi, so "3pm", "17:30", and "30 min" work
as they do alone, and Hindi does not write a clock time with the letter h, so
"2h" stays a length.

"कल" means both tomorrow and yesterday, and "परसों" both the day after tomorrow
and the day before yesterday. Lorvex reads "कल" as tomorrow and "परसों" as the
day after tomorrow, and never reads a past day, since the app itself writes the
past day "बीता कल". A day stays in the title when its line says that it is
past: a past-tense word anywhere in the line ("कल मीटिंग थी", "मैं कल गया
था", "कल मीटिंग हुई"), or "बीता", "गुज़रा", "पिछले", or "पहले" just before it
("बीता कल", "पिछले शुक्रवार", "पहले शुक्रवार"). A past statement without such
a word ("कल मैंने फोन किया") is read as tomorrow.

Hindi says a clock time with "बजे" after the hour: "5 बजे", "5:30 बजे", "साढ़े
5 बजे" (5:30), "सवा 5 बजे" (5:15), "पौने 6 बजे" (5:45), "डेढ़ बजे" (1:30), and
"ढाई बजे" (2:30). The hour may be a number word before "बजे" ("पाँच बजे"), while
a number word anywhere else is a count ("तीन लोग"). An hour from 1 to 6 with no
part of the day is in the afternoon ("5 बजे" is 5 PM) unless it is written with
a zero ("06:30 बजे"), and a part of the day sets the hour: "सुबह" is the
morning, "दोपहर" is noon at 12 and the afternoon from 1 to 6, "शाम" is the
evening, and "रात" runs past midnight, so "रात 2 बजे" is 02:00 on the next day
and "रात 10 बजे" is 22:00. "आधी रात" is the midnight that ends the day. The part
of the day may stand before the hour ("सुबह 9 बजे", "शाम को 5 बजे", "सुबह ठीक
6 बजे") or after "बजे" ("9 बजे सुबह"). An hour with no part of the day of its
own takes the one part of the day the line names elsewhere: in its day phrase
("कल सुबह मीटिंग 6 बजे" is 06:00), after "हर" ("हर सुबह 6 बजे योग"), or in a
noun ("रात का खाना 8 बजे" is 20:00, "सुबह की सैर 6 बजे" is 06:00). A line that
names two different parts of the day leaves the hour as it reads alone, and an
hour written on the 24-hour clock ("20:00 बजे", "06:30 बजे") is read as
written. A clock time that names a bound ("5 बजे तक", "शाम 5 बजे से पहले", "5
बजे के बाद") stays in the title, and so does "5 बजकर 30 मिनट".

| Detail | Hindi |
|---|---|
| Day | आज, आज रात, कल, कल सुबह, परसों, सोमवार को, इस शुक्रवार, अगले सोमवार, अगले हफ़्ते, इस वीकेंड, 3 दिन बाद, एक हफ़्ते बाद |
| Date | 5 मई, 5 मई 2027, तारीख 5 मई, 1 जनवरी, 12 दिसंबर, 5 अक्टूबर |
| Date range | 3 से 5 मार्च, 3 मार्च से 5 मार्च तक, 30 जनवरी से 2 फ़रवरी तक, 3-5 मार्च, सोमवार से बुधवार तक |
| Due day | शुक्रवार तक, कल शाम से पहले, 5 मई तक, अंतिम तिथि: 5 मई, डेडलाइन शुक्रवार |
| Time | 5 बजे, 5:30 बजे, साढ़े 5 बजे, पौने 6 बजे, डेढ़ बजे, पाँच बजे, सुबह 9 बजे, शाम को 5 बजे, रात के 10 बजे, 9 बजे सुबह, आधी रात, शाम 5:30; 3 से 5 बजे, सुबह 9 से 11 बजे तक, 3 बजे से 5 बजे तक, 14:00 से 16:00 |
| Repeat | हर दिन, रोज़, हर सुबह, हर सोमवार, हर सोमवार और गुरुवार, हर दूसरे सोमवार, हर हफ़्ते, हर 2 दिन, हर महीने, हर महीने की 5 तारीख, हर साल, हर वीकेंड, हर कार्यदिवस, हर सोमवार से शुक्रवार |
| Length | 30 मिनट, 2 घंटे, 1.5 घंटे, 1 घंटा 30 मिनट, आधा घंटा, पौन घंटा, डेढ़ घंटा, दो घंटे, 30 मिनट के लिए |
| Priority | उच्च प्राथमिकता, मध्यम प्राथमिकता, निम्न प्राथमिकता, प्राथमिकता: उच्च, ज़रूरी (at the end, or "ज़रूरी:" at the start) |

A date range plans the task on its first day and makes it due on its last:
"3 से 5 मार्च" and "3 मार्च से 5 मार्च तक" run from March 3 to March 5, and a
month written once serves both days. The end must come after the start ("5 से 3
मार्च" stays in the title), and the end names a month, so "3 से 5" is never a
range of days. A span of weekdays does the same: "सोमवार से बुधवार तक" plans the
task on the coming Monday and makes it due on the Wednesday after it, while
"सोमवार से शुक्रवार" alone stays in the title, since it is a week of work as
often as it is the working week. As in English, a number alone before a spaced
dash belongs to the title ("Sprint 12 - 20 मार्च" is planned for March 20),
while "12-20 मार्च" is a range. A range in the past tense, or one that a
possessive follows ("5 से 8 मई तक की छुट्टी"), stays in the title whole, since
it may be an event the task only prepares for. "3 से 5 बजे" is a time range:
its end carries "बजे", so "3 से 5" alone stays in the title. A date needs its
day number before the month name (जनवरी, फ़रवरी, मार्च, अप्रैल, मई, जून,
जुलाई, अगस्त, सितंबर, अक्टूबर, नवंबर, दिसंबर, in the spellings people type); a
month without a day, a month before its day, a date written in digits ("5/10"),
a date the calendar lacks ("31 अप्रैल"), and a month of the Vikram Samvat year
("चैत्र", "वैशाख") stay in the title.

A weekday is a day only with its full name in "वार" (सोमवार, मंगलवार, बुधवार,
गुरुवार or बृहस्पतिवार, शुक्रवार, शनिवार, रविवार or इतवार): the short forms
"रवि", "सोम", "मंगल", "बुध", "गुरु", "शुक्र", and "शनि" are ordinary words and
names ("शनि मंदिर जाना", "मंगल ग्रह देखना") and stay in the title. A weekday
alone is the coming one, a week ahead when it names today; "इस" makes it this
week's, "अगले" makes it next week's (weeks start on Monday), and "आने वाले"
the coming one. A day that a possessive follows is an attribute of a noun, not
a plan: "सोमवार की मीटिंग" and "कल की रिपोर्ट" stay in the title, and "कल रात
का खाना" reads only "कल". A part of the day after a day belongs to it ("कल
सुबह", "शुक्रवार की शाम"), the afternoon also as "दोपहर बाद" ("कल दोपहर बाद"),
and the emphatic "ही" or "भी" goes with a day, its postposition, or a deadline
word ("आज ही", "सोमवार को ही", "शुक्रवार तक ही"). The weekend ("वीकेंड",
"सप्ताहांत", "हफ़्ते के अंत") is the coming Saturday, today on a Saturday or a
Sunday, and the Saturday a week later after "अगले". "इस हफ़्ते" alone names no
single day and stays in the title, and "आज तक" (so far) and "आज से पहले" are
idioms, not deadlines.

"हर" (or "प्रत्येक", "हरेक") with a day, week, month, year, weekday, or part of
the day repeats the task, and so do the words for every day ("रोज़", "रोज़ाना",
"प्रतिदिन", "नित्य"). "हर सोमवार और गुरुवार" repeats on both days, "हर दूसरे
सोमवार" every other week, "हर वीकेंड" on Saturday and Sunday, and "हर कार्यदिवस"
on the working days, as does a span of weekdays beside "हर" or a word for every
day ("हर सोमवार से शुक्रवार", "रोज़ सोमवार से शुक्रवार"). "हर महीने की 5
तारीख" repeats on the 5th, while a day of the month alone ("5 तारीख तक") is
not read. A part of the day after "हर" belongs to the repeat and gives an hour
beside it its half of the day: "हर सुबह 6 बजे योग" repeats every day at 06:00.
An interval shorter than a day ("हर 2 घंटे") is not a repeat and stays in the
title whole, and so does a cadence word that describes a noun ("रोज़ का काम",
"हर साल की रिपोर्ट"); "रोज़ा", "रोज़गार", and "रोज़ी" are other words.

A length says that it is one: "30 मिनट", "2 घंटे", "1.5 घंटे", "आधा घंटा",
"डेढ़ घंटा", "ढाई घंटे", and "साढ़े 3 घंटे", each maybe after "लगभग" or "करीब",
and with the word that goes with it ("30 मिनट की मीटिंग"). An amount before
"बाद", "पहले", or "में", or after "हर", "कम से कम", or "दिन में", names a moment,
an interval, or a bound, not a length ("2 घंटे बाद", "हर 2 घंटे", "दिन में 2
घंटे"), and neither is a side of a range of amounts ("2 से 3 घंटे"); "घंटा"
alone is no length ("घंटा भर"). A number before a counted noun, a price, or a
percent sign is never a time, a length, or a day ("5 लोग", "5 रुपये", "5%").

"उच्च", "मध्यम", and "निम्न" before "प्राथमिकता" set the priority, and so do
the same words after it ("प्राथमिकता: उच्च"). "ज़रूरी", "अत्यावश्यक", "तुरंत",
and "अर्जेंट" are priority words only at the end of the line, or at its start
before a colon or a comma ("ज़रूरी: रिपोर्ट भेजें"); anywhere else "ज़रूरी" is an
ordinary adjective and stays in the title ("ज़रूरी दवाइयाँ ख़रीदना", "रिपोर्ट
भेजें ज़रूरी है").

Persian words are read when Persian is among your device's preferred languages,
in any regional variant (Iranian and Afghan spellings). A word counts only as a
whole word in Persian letters, so "امروزی" (modern) and "فردایی" hold no day,
and the zero-width non-joiner that Persian writes inside a word keeps it whole
("پس‌فردا", "دوشنبه‌ها"). A compound may be typed with a space, a non-joiner,
or nothing between its words ("سه‌شنبه", "سه شنبه", "سهشنبه"; "قبل از" and
"قبل‌از"). Vowel signs and tatweel are optional, the Persian and Arabic digits
("۳" and "٣") read as the digits they stand for, and the letters that are
spelled in more than one way are read as one (أ, إ, آ as ا, ي and ى as ی, ك as
ک, ة as ه), so "آینده" and "اینده" are the same word; the title keeps what you
typed. Persian written in Latin letters ("farda sobh") is not read. English is
read beside Persian, so "3pm", "17:30", and "30 min" work as they do alone, and
Persian does not write a clock time with the letter h, so "2h" stays a length.

A written date is counted in the Solar Hijri calendar, which Persian speakers
date by ("۱۲ مهر", "۳۱ شهریور"), or in the Gregorian one when it names a
Gregorian month ("۵ مارس", "۵ ژانویه"; the Dari spellings "جنوری", "اپریل", and
"اگست" work too). A date without a year means the next such day, counted in its
own calendar, and a year written after it ("۱۲ مهر ۱۴۰۵", "۵ مارس ۲۰۲۷") must
not be past or more than ten years ahead. A date needs its day number before
the month name: a month alone ("مهر"), a date written in digits only
("۱۴۰۵/۷/۱۲"), a date the calendar lacks ("۳۱ مهر", or "۳۰ اسفند" in a year
that is not a leap year), the lunar Hijri months ("رمضان"), and the Afghan names
of the Solar months ("حمل", "ثور") stay in the title. Weeks start on Monday, as
the app's weeks do in every language: "هفته آینده سه‌شنبه" is the Tuesday of the
week that begins on the coming Monday, and "هفته آینده شنبه" the Saturday that
closes it.

Only the future is read. Persian has one word for each of today, tomorrow, and
the day after ("امروز", "فردا", "پس‌فردا"), so "دیروز" and "پریروز" name no day,
and a weekday that "گذشته", "پیش", "قبل", or "قبلی" follows is the past ("پنجشنبه
گذشته", "جمعه قبل") and stays in the title. So does "شب جمعه", the night before
Friday, and the names that hold a weekday ("نماز جمعه", "بازار جمعه",
"چهارشنبه‌سوری"). A weekday alone is the coming one, a week ahead when it names
today; "این" or "همین" makes it this week's, today when it names today; "آینده",
"آتی", "بعدی", or "بعد" after it makes it the coming one ("پنجشنبه آینده",
"پنجشنبه‌ی بعد", but "پنجشنبه بعد از ظهر" is the afternoon); and a week named
before or after it makes it that week's ("هفته آینده سه‌شنبه", "سه‌شنبه هفته
آینده", "پنجشنبه این هفته"). A part of the day before or after a day belongs to
it ("صبح پنجشنبه", "جمعه عصر", "فردا شب"; the night only after it: "پنجشنبه
شب"). A count of days, weeks, or months ahead is a day ("۳ روز دیگر", "سه روز
دیگه", "۲ هفته دیگر", "یک ماه دیگر", "بعد از ۳ روز"; months are counted on the
Solar Hijri calendar), but not when "از" follows it ("۳ روز بعد از جلسه"), nor
"مانده" or "باقی" ("۳ روز دیگر مانده"), and a count with no word for ahead
("سفر ۵ روز") stays in the title. The weekend and the working days are not
read, because which days they are depends on the country.

Persian says a clock time with "ساعت": "ساعت ۵", "ساعت ۵:۳۰", "ساعت ۱۷", "ساعت
پنج", "ساعت ۵ و نیم" (5:30), "ساعت ۵ و ربع" (5:15), "ساعت ۵ و ده دقیقه" (5:10),
"ساعت ۶ ربع کم" (5:45), "یک ربع به ۶" (5:45), and "ده دقیقه به ۶" (5:50). An
hour from 1 to 6 with no part of the day is in the afternoon ("ساعت ۵" is 5 PM)
unless it is written with a zero ("ساعت ۰۶:۳۰"), and a part of the day sets the
hour: "صبح" (also "سحر", "بامداد", "قبل از ظهر") is the morning, "ظهر" is noon at
12 and the afternoon from 1 to 6 ("بعد از ظهر" is the afternoon), "عصر" and
"غروب" are the evening, and "شب" runs past midnight, so "ساعت ۲ شب" is 02:00 on
the next day and "ساعت ۱۰ شب" is 22:00. "در نیمه‌شب" is the midnight that ends
the day. A part of the day beside the day phrase sets a bare hour too: "فردا صبح
ساعت ۶" is 06:00, and "هر شب ساعت ۱۰" is 22:00. An hour with a part of the day
needs no "ساعت" ("۸ شب", "۹ صبح", "۸ و نیم شب", "۵ بعدازظهر"), except that the
night names no hour from 1 to 5 without it, since "۳ شب" is three nights. A bare
number is never an hour ("جلسه ۳", "جلسه با ۳ نفر"), "۵ و نیم" is 5:30 only at
the end of the line ("۲ و نیم کیلو" counts kilograms), "ساعت ۱۲ صبح" and "ساعت
۱۲ عصر" are not read, and a clock time that names a bound ("تا ساعت ۵", "قبل از
۱۸:۰۰", "بعد از ساعت ۵:۳۰", "قبل از ساعت ۵ عصر") stays in the title.

| Detail | Persian |
|---|---|
| Day | امروز, امشب, فردا, فردا صبح, پس‌فردا, جمعه, این جمعه, پنجشنبه آینده, هفته آینده, ۳ روز دیگر, یک هفته دیگر |
| Date | ۱۲ مهر, ۱۲ مهر ۱۴۰۵, پنجشنبه ۱۲ مهر, ۵ مارس, ۵ مارس ۲۰۲۷ |
| Date range | از ۳ تا ۵ آبان, ۳ تا ۵ آبان, از ۳ آبان تا ۵ آذر, بین ۳ و ۵ آبان, ۳-۵ آبان, از دوشنبه تا چهارشنبه |
| Due day | تا جمعه, قبل از فردا, تا ۱۲ مهر, حداکثر پنجشنبه, تا آخر روز, مهلت: جمعه, ددلاین ۱۲ مهر |
| Time | ساعت ۵, ساعت ۱۷:۳۰, ساعت ۵ عصر, ساعت ۹ صبح, ساعت ۵ و نیم, ساعت ۶ ربع کم, یک ربع به ۶, ۸ شب, در نیمه‌شب; از ساعت ۲ تا ۴, از ۹ صبح تا ۵ بعدازظهر, بین ساعت ۲ و ۴, ساعت ۲-۴ |
| Repeat | هر روز, هر صبح, هر هفته, هر دوشنبه, هر دوشنبه و پنجشنبه, دوشنبه‌ها, روزهای دوشنبه و چهارشنبه, هر دو روز, یک روز در میان, یک دوشنبه در میان, هر ماه, هر سال, هفته‌ای یک بار; روزانه at the start or after a comma |
| Length | ۲۰ دقیقه, ۲ ساعت, ۱٫۵ ساعت, ۲ ساعت و نیم, نیم ساعت, ربع ساعت, یک ربع, به مدت ۲ ساعت |
| Priority | اولویت بالا, اولویت متوسط, اولویت پایین, فوری (at the end, or "فوری:" at the start) |

A date range plans the task on its first day and makes it due on its last:
"از ۳ تا ۵ آبان" and "از ۳ آبان تا ۵ آذر" run from 3 Aban to 5 Aban and from 3
Aban to 5 Azar, and a month written once serves both days. "الی" may stand for
"تا", "بین ... و" and a dash join the days too, and a year may follow the end.
The end must come after the start ("از ۵ تا ۳ آبان" stays in the title), and
the end names a month, so "از ۳ تا ۵" is never a range of days. "و" joins the
days only after "بین" ("۳ و ۵ آبان" names two days and stays in the title
whole), and a range whose sides name different calendars ("از ۳ مهر تا ۵ مارس")
stays in the title whole too. As in English, a number alone before a spaced
dash belongs to the title ("اسپرینت ۱۲ - ۲۰ مهر" is planned for 20 Mehr), while
"۱۲-۲۰ مهر" is a range. Two bare hours are not a time range either ("از ۱۴ تا ۱۶
صفحه" stays in the title): a range needs "ساعت", a part of the day, or a colon
("از ساعت ۲ تا ۴", "از ۲ تا ۴ عصر", "۱۴:۰۰ تا ۱۶:۰۰"). A span of weekdays does
the same as a range of dates: "از دوشنبه تا چهارشنبه" plans the task on the
coming Monday and makes it due on the Wednesday after it, and a span runs
through the week's end ("از جمعه تا دوشنبه"). The spans that are a week of work
("از دوشنبه تا جمعه", "از شنبه تا چهارشنبه", "از شنبه تا پنجشنبه") stay in the
title whole, since each is a week of work as often as it is a span of days, and
so does a span in the past ("تا چهارشنبه گذشته") or from a day to itself.

A due day follows "تا", "قبل از", "پیش از", "حداکثر", or "نهایتاً" ("تا جمعه",
"قبل از فردا", "تا ۱۲ مهر", "تا آخر روز"), or a label ("مهلت", "ددلاین",
"سررسید", "موعد", "آخرین مهلت", "تاریخ سررسید": "مهلت: جمعه"). A day after "بعد
از", "پس از", or "از" is neither a deadline nor a planned day ("بعد از جمعه"
stays in the title), and neither is a day that a stretch word precedes ("هر",
"همه", "تمام", "طی", "ظرف", "آخر", "اول"). The day before a clock deadline is
the due day, and the clock stays in the title: "گزارش جمعه تا ساعت ۵" is due
Friday.

"هر" with a day, week, month, year, weekday, or part of the day repeats the
task: "هر روز", "هر دو روز", "هر ۳ هفته", "هر ماه", "هر سال", "هر دوشنبه و
پنجشنبه". A part of the day after "هر" belongs to the repeat ("هر صبح" and "هر
شب" repeat every day) and gives an hour beside it its half of the day: "هر شب
ساعت ۱۰" repeats every day at 22:00. "یک روز در میان" is every other day, "یک
دوشنبه در میان" every other week on Monday, "هفته‌ای یک بار", "ماهی یک بار",
and "روزی یک بار" once per week, month, and day, and "دو هفته یک بار" every two
weeks. The plural weekday ("دوشنبه‌ها") and "روزهای" with weekdays ("روزهای
دوشنبه و چهارشنبه") repeat too, as does a span of weekdays beside "هر",
"روزهای", or a word for every day ("هر روز از دوشنبه تا جمعه", "روزهای شنبه تا
چهارشنبه"), which runs through the week's end. The adverbs "روزانه", "هر
روزه", "هفتگی", "ماهانه", and "سالانه" repeat only at the start of the line
("روزانه ۳۰ دقیقه ورزش") or at its end after a comma ("ورزش، روزانه"); after the
task's noun they are its adjective, and "گزارش روزانه" and "جلسه هفتگی" stay in
the title. A part of the day before a weekday ("هر شب جمعه") is that day's
night and is not read, an interval shorter than a day ("هر ۲ ساعت") is not a
repeat and stays in the title whole, and "هر دو" before a noun that is not a
unit ("هر دو کتاب") means "both". "هر ماه" beside a day of the month ("اجاره
هر ماه ۵ام") stays in the title, since Persian speakers count the days of a
month in the Solar Hijri calendar, whose months are not the Gregorian months a
monthly repeat keeps.

A length says that it is one: "۲۰ دقیقه", "۲ ساعت", "۱٫۵ ساعت", "۲ ساعت و ۳۰
دقیقه", "دو و نیم ساعت", "نیم ساعت", "ربع ساعت", "یک ربع", "سه ربع", "بیست و پنج
دقیقه", "جلسه ۲ ساعته", and "۳۰ دقیقه‌ای", each maybe after "به مدت", "مدت",
"حدود", "تقریباً", "نزدیک", or "برای". An amount after "بعد از", "پس از", "قبل از",
"پیش از", "کمتر از", "بیش از", "حداقل", "حداکثر", "هر", "تا", "طی", "ظرف", "در",
"روزی", or "ماهی", and one before "پیش", "بعد", "دیگر", "باقی", or "در روز", names
a moment, an interval, a rate, or a bound, not a length ("بعد از ۱۵ دقیقه", "هر ۲
ساعت", "روزی ۲ ساعت", "۲ ساعت پیش", "۱۰ دقیقه دیگر"), and neither is a side of a
range of amounts ("۲ تا ۳ ساعت"). "ساعت" and "دقیقه" alone are nouns (a watch, a
moment), and a number before a counted noun, a price, or a percent sign is never
a time, a length, or a day ("۵ نفر", "۵۰ هزار تومان", "۲۰٪").

"اولویت بالا" (also "اولویت بسیار بالا", "اولویت خیلی بالا", "اولویت زیاد"),
"اولویت متوسط" (also "معمولی", "نرمال"), and "اولویت پایین" (also "کم",
"کمتر") set the priority, each maybe with a colon ("اولویت: بالا") or after "با"
("با اولویت بالا"). "فوری" is a priority word only at the end of the line, or at
its start before a colon or a comma ("فوری: گزارش را بفرست"); anywhere else it is
an ordinary adjective and stays in the title ("کار فوری دارم", "تماس فوری با
مادر").

Urdu words are read when Urdu is among your device's preferred languages, in
any regional variant (ur-PK and ur-IN). A word counts only as a whole word in
Urdu letters, so "کلاس" (a class) and "آجکل" (nowadays) hold no day, and the
Urdu full stop and comma end a word ("رپورٹ بھیجیں کل۔"). The Arabic-Indic and
Extended Arabic-Indic digits ("٣" and "۳") read as the digits they stand for,
and vowel signs and tatweel are optional. The letters that Urdu and Arabic
keyboards spell in more than one way are read as one (the alefs with hamza or
madda as ا, ي and ى as ی, ك as ک, every heh as ہ, and ں as ن), so "بھی" and
"بهي" are the same word; the bari ye ے stays a different letter from the choti
yeh ی, since "ہے" (is) and "ہی" (only) are different words. A compound may be
typed with a space, a zero-width non-joiner, or nothing between its words ("سہ
پہر", "سہ‌پہر", "سہپہر"); the title keeps what you typed. Urdu written in Latin
letters ("kal subah 9 baje") is not read. English is read beside Urdu, so
"3pm", "17:30", and "30 min" work as they do alone, and Urdu does not write a
clock time with the letter h, so "2h" stays a length.

"کل" means both tomorrow and yesterday, and "پرسوں" both the day after tomorrow
and the day before yesterday. Lorvex reads "کل" as tomorrow and "پرسوں" as the
day after tomorrow, and never reads a past day, since the app itself writes the
past day "گزشتہ کل". A day stays in the title when its line says that it is
past: a past-tense word anywhere in the line ("کل میٹنگ تھی", "میں کل گیا
تھا", "کل میٹنگ ہوئی"), or "گزشتہ", "گزرا", "پچھلا", or "پہلا" just before it
("گزشتہ کل", "پچھلے جمعہ", "پہلے جمعہ"). A past statement without such a word
("کل میں نے فون کیا") is read as tomorrow. "کل" is also the word for "total":
it is no day before "رقم", "تعداد", "ملا", and the like ("کل رقم"), and "آج
کل" is "nowadays". "میں" after a day is never read as a postposition, since it
is also "I": "آج میں رپورٹ لکھوں گا" reads only "آج".

Urdu says a clock time with "بجے" after the hour: "5 بجے", "5:30 بجے", "ساڑھے 5
بجے" (5:30), "سوا 5 بجے" (5:15), "پونے 6 بجے" (5:45), "ڈیڑھ بجے" (1:30), and
"ڈھائی بجے" (2:30). The hour may be a number word before "بجے" ("پانچ بجے"),
while a number word anywhere else is a count ("تین لوگ"). An hour from 1 to 6
with no part of the day is in the afternoon ("5 بجے" is 5 PM) unless it is
written with a zero ("06:30 بجے"), and a part of the day sets the hour: "صبح"
(also "سویرے" and "تڑکے") is the morning, "دوپہر" and "سہ پہر" are noon at 12
and the afternoon from 1 to 6, "شام" is the evening, and "رات" runs past
midnight, so "رات 2 بجے" is 02:00 on the next day and "رات 10 بجے" is 22:00.
"آدھی رات" and "نصف شب" are the midnight that ends the day. The part of the
day may stand before the hour ("صبح 9 بجے", "شام کو 5 بجے", "رات کے 10 بجے",
"صبح ٹھیک 6 بجے") or after "بجے" ("9 بجے صبح"). An hour with no part of the day
of its own takes the one part of the day the line names elsewhere: in its day
phrase ("کل صبح میٹنگ 6 بجے" is 06:00), after "ہر" ("ہر صبح 6 بجے ورزش"), or in
a noun ("رات کا کھانا 8 بجے" is 20:00, "صبح کی سیر 6 بجے" is 06:00). A line
that names two different parts of the day leaves the hour as it reads alone,
and an hour written on the 24-hour clock ("20:00 بجے", "06:30 بجے") is read as
written. A clock time that names a bound ("5 بجے تک", "شام 5 بجے سے پہلے", "5
بجے کے بعد") stays in the title, and so does "5 بج کر 30 منٹ".

| Detail | Urdu |
|---|---|
| Day | آج, آج رات, کل, کل صبح, پرسوں, جمعہ کو, اس جمعہ, اگلے پیر, اگلے ہفتے, ویک اینڈ, 3 دن بعد, ایک ہفتے بعد |
| Date | 5 مئی, 5 مئی 2027, تاریخ 5 مئی, 1 جنوری, 12 دسمبر, 5 اکتوبر |
| Date range | 3 سے 5 مارچ, 3 مارچ سے 5 مارچ تک, 30 جنوری سے 2 فروری تک, 3 تا 5 مارچ, 3-5 مارچ, پیر سے بدھ تک |
| Due day | جمعہ تک, کل شام سے پہلے, 5 مئی تک, آخری تاریخ: 5 مئی, ڈیڈ لائن جمعہ |
| Time | 5 بجے, 5:30 بجے, ساڑھے 5 بجے, پونے 6 بجے, ڈیڑھ بجے, پانچ بجے, صبح 9 بجے, شام کو 5 بجے, رات کے 10 بجے, 9 بجے صبح, آدھی رات, شام 5:30; 3 سے 5 بجے, صبح 9 سے 11 بجے تک, 3 بجے سے 5 بجے تک, 14:00 سے 16:00 |
| Repeat | ہر دن, ہر روز, روزانہ, ہر صبح, ہر پیر, ہر پیر اور جمعرات, ہر دوسرے پیر, ہر ہفتے, ہر 2 دن, ہر مہینے, ہر مہینے کی 5 تاریخ, ہر سال, ہر ویک اینڈ, ہر کام کے دن, ہر پیر سے جمعہ |
| Length | 30 منٹ, 2 گھنٹے, 1.5 گھنٹے, 1 گھنٹہ 30 منٹ, آدھا گھنٹہ, پون گھنٹہ, ڈیڑھ گھنٹہ, دو گھنٹے, 30 منٹ کے لیے |
| Priority | اعلیٰ ترجیح, معمولی ترجیح, کم ترجیح, ترجیح: اعلیٰ, فوری (at the end, or "فوری:" at the start) |

A written date is counted in the Gregorian calendar and needs its day number
before the month name (جنوری, فروری, مارچ, اپریل, مئی, جون, جولائی, اگست,
ستمبر, اکتوبر, نومبر, دسمبر, in the spellings people type: "ایپریل", "جولای",
"اگسٹ" work too). A date without a year means the next such day, a year
written after it ("5 مئی 2027", "5 مئی 2028ء") must not be past or more than
ten years ahead, and a label ("تاریخ 5 مئی", "بتاریخ: 5 مئی") or a weekday
("پیر، 5 اکتوبر") may go with it. A month alone ("چھٹی مئی میں"), a month
before its day ("مئی 5"), a date written in digits ("5/10"), a date the
calendar lacks ("31 اپریل"), a day of the month alone ("5 تاریخ کو"), and the
months of the Islamic and the Indian calendars ("محرم", "رمضان", "چیت") stay in
the title. A date range plans the task on its first day and makes it due on its
last: "3 سے 5 مارچ" and "3 مارچ سے 5 مارچ تک" run from March 3 to March 5, and
a month written once serves both days. "تا" and a dash join the days too, "سے
لے کر" may open the end, "کے بیچ" or "کے درمیان" may close it ("3 اور 5 مارچ کے
درمیان"), and a year may follow the end. The end must come after the start ("5
سے 3 مارچ" stays in the title), and the end names a month, so "3 سے 5" is never
a range of days. "3 اور 5 مارچ" with no "کے بیچ" or "کے درمیان" names two days
and stays in the title whole. As in English, a number alone before a spaced
dash belongs to the title ("Sprint 12 - 20 مارچ" is planned for March 20),
while "12-20 مارچ" is a range. A range in the past tense, or one that a
possessive follows ("5 سے 8 مئی تک کی چھٹی"), stays in the title whole, since
it may be an event the task only prepares for. "3 سے 5 بجے" is a time range:
its end carries "بجے", so "3 سے 5" alone stays in the title. A span of
weekdays does the same as a range of dates: "پیر سے بدھ تک" plans the task on
the coming Monday and makes it due on the Wednesday after it, while "پیر سے
جمعہ" and "پیر سے ہفتہ" alone stay in the title, since each is a week of work
as often as it is a span of days.

A weekday is a day by its name: پیر (or سوموار), منگل, بدھ, جمعرات, جمعہ (or
جمعے), ہفتہ or سنیچر, and اتوار. A weekday alone is the coming one, a week ahead
when it names today; "اس" makes it this week's, "اگلے" makes it next week's
(weeks start on Monday, as the app's weeks do), and "آئندہ" or "آنے والے" the
coming one. "کو", "کے دن", "کے روز", and "بروز" go with the name ("جمعہ کو",
"جمعہ کے روز", "بروز جمعہ"). "ہفتہ" and "ہفتے" also mean "the week", so they name
Saturday only beside a mark of a day ("ہفتے کو", "ہفتے کے دن", "بروز ہفتہ",
"ہفتے کی شام", "ہفتہ اور اتوار") or before a deadline word ("ہفتے تک");
anywhere else ("اس ہفتے", "ہفتہ وار", "ہفتہ بھر") they stay in the title, while
"سنیچر" names Saturday anywhere. The names that hold a weekday ("پیر صاحب",
"پیر میں درد", "بدھ مت", "جمعہ بازار", "جمعہ مبارک", "نماز جمعہ") are no day.
A day that a possessive follows is an attribute of a noun, not a plan: "پیر کی
میٹنگ" and "کل کی رپورٹ" stay in the title, and "کل رات کا کھانا" reads only
"کل". A part of the day after a day belongs to it ("کل صبح", "جمعہ کی شام"),
the afternoon also as "دوپہر بعد" ("کل دوپہر بعد"), and the emphatic "ہی" or
"بھی" goes with a day, its postposition, or a deadline word ("آج ہی", "پیر کو
ہی", "جمعہ تک ہی"). A list of weekdays with no "ہر" ("پیر اور جمعرات کو") stays
in the title, since one planned day cannot carry the list. The weekend ("ویک
اینڈ", "اختتام ہفتہ", "ہفتے کے آخر", "ہفتہ اور اتوار") is the coming Saturday,
today on a Saturday or a Sunday, and the Saturday a week later after "اگلے".
"اس ہفتے" alone names no single day and stays in the title. A count of days,
weeks, or months ahead is a day ("3 دن بعد", "تین دن بعد", "2 ہفتے بعد", "ایک
ہفتے کے بعد", "1 مہینے بعد"; months are counted on the calendar), but "رپورٹ 3
دن میں", "3 دن پہلے", and "میٹنگ کے 3 دن بعد" name no day.

A due day follows "تک", "سے پہلے", or "سے قبل" ("جمعہ تک", "کل شام سے پہلے", "5
مئی تک", "اگلے ہفتے تک"), or a label ("آخری تاریخ", "مقررہ تاریخ", "حتمی تاریخ",
"ڈیڈ لائن": "آخری تاریخ: 5 مئی", "ڈیڈ لائن جمعہ"). The day before a clock
deadline is the due day, and the clock stays in the title: "رپورٹ جمعہ شام 5
بجے تک" is due Friday. "آج تک" (so far) and "آج سے پہلے" are idioms, not
deadlines, and a deadline that a possessive follows ("جمعہ تک کی رپورٹ") stays
in the title.

"ہر" with a day, week, month, year, weekday, or part of the day repeats the
task, and so do "روزانہ", "ہفتہ وار", "ماہانہ", "ماہوار", and "سالانہ" (each maybe
with "کی بنیاد پر" after it). "ہر پیر اور جمعرات" repeats on both days, "ہر دوسرے
پیر" every other week, "ہر ویک اینڈ" on Saturday and Sunday, and "ہر کام کے دن"
on the working days, as does a span of weekdays beside "ہر" or a word for every
day ("ہر پیر سے جمعہ", "پیر سے جمعہ ہر روز"). "ہر ہفتے" is every week and "ہر
ہفتے کو" every Saturday. "ہر مہینے کی 5 تاریخ" repeats on the 5th, while a day of
the month alone ("5 تاریخ کو") is not read. A part of the day after "ہر" belongs
to the repeat and gives an hour beside it its half of the day: "ہر صبح 6 بجے
ورزش" repeats every day at 06:00. An interval shorter than a day ("ہر 2
گھنٹے") is not a repeat and stays in the title whole, and so does a cadence word
that a possessive follows, since it describes a noun ("روزانہ کی رپورٹ", "ہر
سال کا جائزہ", "ہر ہفتے کی میٹنگ"). Urdu puts an adjective before its noun, so
the adverbs read as repeats elsewhere in the line ("روزانہ دوا لیں"). A bare
"روز" is no repeat word ("جمعہ کے روز" names a day), and "روزہ", "روزگار", and
"روز مرہ" are other words.

A length says that it is one: "30 منٹ", "2 گھنٹے", "1.5 گھنٹے", "1 گھنٹہ 30
منٹ", "آدھا گھنٹہ", "پون گھنٹہ" (45 minutes), "سوا گھنٹہ" (75 minutes), "ڈیڑھ
گھنٹہ", "ڈھائی گھنٹے", "ساڑھے 3 گھنٹے", and "بیس منٹ", each maybe after
"تقریباً", "قریباً", or "لگ بھگ", and with the word that goes with it ("30 منٹ
کے لیے", "30 منٹ کی میٹنگ"). An amount before "بعد", "پہلے", or "میں", or after
"ہر", "کم از کم", or "دن میں", names a moment, an interval, or a bound, not a
length ("2 گھنٹے بعد", "ہر 2 گھنٹے", "دن میں 2 گھنٹے"), and neither is a side of a
range of amounts ("2 سے 3 گھنٹے"); "گھنٹہ" alone is no length ("گھنٹہ بھر"). A
number before a counted noun, a price, or a percent sign is never a time, a
length, or a day ("3 لوگوں کے ساتھ میٹنگ", "500 روپے", "20%").

"اعلیٰ", "معمولی", and "کم" before "ترجیح" set the priority, and so do the same
words after it ("ترجیح: اعلیٰ"); "درمیانی" and "عام" are the middle priority,
"نچلی" the low one, and "زیادہ" the high one, and "کے ساتھ", "پر", or "سے" may
follow ("اعلیٰ ترجیح کے ساتھ بھیجیں"). "فوری", "ضروری", "انتہائی ضروری", "فوراً",
and "ارجنٹ" are priority words only at the end of the line, or at its start
before a colon or a comma ("فوری: رپورٹ بھیجیں"); anywhere else "ضروری" is an
ordinary adjective and stays in the title ("ضروری دوائیں خریدنا", "رپورٹ بھیجیں
ضروری ہے"). The Urdu full stop that follows a detail stays with the title:
"امی کو فون کرنا کل۔" gives the title "امی کو فون کرنا۔".

Hebrew words are read when Hebrew is among your device's preferred languages,
in any regional variant. A word counts only as a whole word in Hebrew letters,
so "מחרוזת" (a string) and "היומן" (the diary) hold no day. Hebrew attaches its
one-letter prepositions and the article to the word they go with ("למחר",
"בשבוע", "השבוע", "בבוקר"): each word is read with the prefixes it takes, and a
word with another prefix ("ומחר", "שמחר") stays in the title. The final letters
(ך ם ן ף ץ) are read as the regular ones, the maqaf and every dash as the
hyphen ("ב־17:30" is "ב-17:30"), every apostrophe as the geresh, and every
double quote as the gershayim, so "אחה״צ" (afternoon) typed with a straight or a
curly double quote is the same word. Niqqud is optional on any letter, and the
title keeps what you typed. A word with two usual spellings is read in both
("שתיים" and "שתים", "צהריים" and "צהרים", "מרץ" and "מרס"). Hebrew written in
Latin letters ("machar") and Hebrew numerals ("י״ב") are not read. English is
read beside Hebrew, so "3pm", "17:30", and "30 min" work as they do alone, and
Hebrew does not write a clock time with the letter h, so "2h" stays a length.

Weeks start on Monday, as the app's weeks do in every language, and the weekend
is Saturday and Sunday. Israel's week starts on Sunday and its weekend is Friday
and Saturday, so the phrases that depend on which days make up the week are left
in the title: "כל יום עבודה", "בימי עבודה", and "ימי חול" (working days), and a
span from Sunday to Thursday or Friday, or from Monday to Friday or Saturday,
with no "כל" before it ("מיום ראשון עד יום חמישי"), since each is a week of work
as often as it is a span of days.

Only the future is read. A line in the past tense (a form of "היה": "היה",
"הייתה", "היו", "הייתי", "היינו") or one that says "אתמול", "שלשום", or "אמש"
holds no day to plan ("היום הייתה פגישה"), except "מחר", "מחרתיים", and "בעוד"
with a count, which cannot be past. A weekday that "שעבר", "הקודם", "האחרון", or
"שחלף" follows is the past one ("ביום שני שעבר") and stays in the title, and
"היום" before the article and an adjective is "the day", not today ("היום
הראשון"). A day that "של" (of), "כל" (every), or a bound ("לפני", "אחרי", "מאז")
stands before is no plan ("הדוח של מחר" stays in the title), and neither is a
day after a noun in the construct state, which ends in ת ("ארוחת הערב", "ישיבת
יום שני").

A weekday is a day by its name: ראשון, שני, שלישי, רביעי, חמישי, שישי, and שבת.
It takes "יום" before it ("יום שני", "ביום שני", "ליום שני"), an attached ב
("בשלישי"), or, after "יום", a letter from א׳ to ו׳ or ש׳ ("יום ג׳"). The names
are ordinary words too (שני is "second" and "two"), so a name with neither "יום"
nor an attached ב is no day; "בשני" is a day only at the end of the line or
before a part of the day, a time, or "הבא"; and no name is a day before a month
or "החודש" ("בראשון לחודש", "בראשון במאי"), in the city "ראשון לציון", or before
"מתוך" ("בשישי מתוך עשרה" is the sixth of ten). A weekday alone is the coming
one, a full week ahead when it names today; "הזה", "השבוע", and "בשבוע הזה" make
it this week's, today when it names today; "הבא" and "הקרוב" make it the coming
one; and "בשבוע הבא" makes it next week's, so "בשבוע הבא ביום רביעי" is the
Wednesday of the week that begins on the coming Monday. A list of weekdays with
no "כל" ("ביום שני וחמישי", "בשישי ובשבת") stays in the title, since one planned
day cannot carry the list.

A part of the day after a day belongs to it ("מחר בבוקר", "היום אחר הצהריים",
"ביום שלישי בערב"), and "הערב", "הלילה", and "הבוקר" are today. A count of
days, weeks, or months ahead is a day ("בעוד 3 ימים", "בעוד שלושה שבועות",
"בעוד יומיים", "בעוד שבוע", "בעוד חודש"; months are counted on the calendar),
but "בעוד שעה" (in an hour) names no day. "בשבוע הבא" alone is seven days
ahead. The weekend ("סוף השבוע", "סוף שבוע", "סופ״ש", each maybe with ב or ל and
with "הבא", "הקרוב", or "הזה") is the coming Saturday, today on a Saturday or a
Sunday, and the Saturday a week later after "הבא".

Hebrew says a clock time with "בשעה" or "ב-" before the hour: "בשעה 5", "בשעה
17:30", "ב-17:30", "בשעה 5.30", "בשלוש וחצי" (3:30), "בשעה 3 ורבע" (3:15), "ברבע
לשש" (5:45), "בשעה 4 פחות רבע" (3:45), and "בשעה 3 ו-10 דקות" (3:10). The hour
is digits or a word from "אחת" to "שתים עשרה" in the feminine, since "שעה" is
feminine ("שלוש", "חמש", "שתיים"). A bare number is no time, because "ב-5 ימים"
counts things: after "שעה" the number alone is enough, and after "ב-" it needs a
colon, a fraction word, "רבע ל", or a part of the day ("ב-9 בבוקר"), so "ב-5" is
left in the title. An hour in words needs a fraction word, "רבע ל", or a part of
the day too ("בחמש אחר הצהריים"), so "בחמש" alone is left in the title as well.
An hour from 1 to 6 with no part of the day anywhere in the line is in the
afternoon ("בשעה 5" is 17:00, but "בשעה 7" is 07:00) unless it is written with a
zero ("בשעה 06:30"), and a part of the day sets the hour: "בבוקר" (also "לפנות
בוקר") is the morning, "בצהריים" and "אחר הצהריים" ("אחה״צ") are noon at 12 and
the afternoon from 1 to 6, "בערב" is the evening, and "בלילה" runs past
midnight, so "בשעה 8 בלילה" is 20:00, "בשעה 2 בלילה" is 02:00 on the next day,
and "בשעה 12 בלילה" and "בחצות" are 00:00 on the next day.

An hour with no part of the day of its own takes the one part of the day the
line names elsewhere: in its day phrase ("מחר בבוקר פגישה בשעה 6" is 06:00),
after "כל" ("כל בוקר בשעה 6"), or in a noun ("ארוחת ערב בשעה 8" is 20:00). A line
that names two different parts of the day leaves the hour as it reads alone, and
an hour on the 24-hour clock ("בשעה 17:30", "בשעה 17") is read as written.
"בערך", "בסביבות", "בדיוק", and "בקירוב" may go with a time ("בערך בשעה 5", "בשעה
5 בדיוק"). A time range plans the task from its start for as long as the range
lasts: "מ-9 עד 11 בבוקר", "בין 14:00 ל-16:00", "משעה 9 עד 11", "בשעה 17:30 עד
18:30", and "18:00-19:30". Two bare numbers are a range only with "משעה" or
"בשעות" before them, a colon, or a part of the day, so "מ-14 עד 16 עמודים" stays
in the title. A clock time that names a bound ("עד 17:00", "לפני 18:00", "אחרי
18:00", "עד השעה 5", "עד 5 בערב", "לא יאוחר מ-17:00") stays in the title, and so
does a number before a percent sign, a price, or a counted noun ("ב-5 וחצי ק״מ").

| Detail | Hebrew |
|---|---|
| Day | היום, הערב, מחר, מחר בבוקר, מחרתיים, ביום שני, ביום שני הבא, בשבוע הבא ביום רביעי, בשבוע הבא, סוף השבוע, בעוד 3 ימים, בעוד שבועיים |
| Date | 5 במרץ, ב-5 במרץ, 5 במרץ 2027, בתאריך 5 במרץ, ביום שני 5 באוקטובר |
| Date range | מ-3 עד 5 במרץ, בין 3 ל-5 במרץ, 3-5 במרץ, מ-30 בינואר עד 2 בפברואר, מיום שני עד יום רביעי |
| Due day | עד יום שישי, עד מחר, עד ה-5 במרץ, לפני יום שישי, לא יאוחר מיום שלישי, מועד אחרון: יום חמישי, דדליין מחר |
| Time | בשעה 5, בשעה 17:30, ב-17:30, ב-9 בבוקר, בשלוש וחצי, בשעה 3 ורבע, ברבע לשש, בחמש אחר הצהריים, בשעה 8 בלילה, בחצות; מ-9 עד 11 בבוקר, בין 14:00 ל-16:00, 18:00-19:30 |
| Repeat | כל יום, מדי יום, כל יומיים, כל 3 ימים, כל שבוע, כל חודש, כל חודש ב-5, כל שנה, כל יום שני, כל שני וחמישי, כל יום ראשון עד חמישי, כל סוף שבוע, כל בוקר, אחת לשבוע, פעם ב-3 חודשים, יום כן יום לא |
| Length | 30 דקות, שעתיים, 1.5 שעות, שעה ו-30 דקות, חצי שעה, רבע שעה, שלושת רבעי שעה, שעה וחצי, שלוש שעות, עשרים דקות, ריצה של 30 דקות |
| Priority | עדיפות גבוהה, עדיפות בינונית, עדיפות נמוכה, עדיפות: גבוהה, דחוף (at the end, or "דחוף:" at the start) |

A written date is counted in the Gregorian calendar and needs its day number
before the month name: ינואר, פברואר, מרץ (or מרס), אפריל, מאי, יוני, יולי, אוגוסט,
ספטמבר, אוקטובר, נובמבר, and דצמבר, each maybe with ב ("5 במרץ"). The day may
carry ב or ה ("ב-5 במרץ", "ה-5 במרץ"), a label ("בתאריך 5 במרץ") or a weekday
("ביום שני, 5 באוקטובר") may go with it, a date without a year means the next
such day, and a year written after it ("5 במרץ 2027") must not be past or more
than ten years ahead. A month alone, a date written in digits ("5.3", "5/3"), a
date the calendar lacks ("31 באפריל"), and the months of the Hebrew calendar
("תשרי", "ניסן") stay in the title.

A date range plans the task on its first day and makes it due on its last: "מ-3
עד 5 במרץ", "מה-3 ועד ה-5 במרץ", "בין 3 ל-5 במרץ", and "3-5 במרץ" run from March
3 to March 5, and "מ-30 בינואר עד 2 בפברואר" names both months. A day written
without its month takes the month of the end, a year may follow the end, and the
end must come after the start ("מ-5 עד 3 במרץ" stays in the title whole). The end
names a month, so "3 עד 5" is never a range of days. "ב-3 ו-5 במרץ" (two days
joined by "ו-" with no "בין") names two days and stays in the title whole, and
so does a range in the past tense. A range names both the planned day and the
due day, so another day in the same line stays in the title. As in English, a
number alone before a spaced dash belongs to the title ("ספרינט 12 - 20 במרץ" is
planned for March 20), while "ספרינט 12-20 במרץ" is a range. A span of weekdays
does the same as a range of dates: "מיום שני עד יום רביעי", "משני עד רביעי",
"בין יום שני ליום רביעי", and "מיום ב׳ עד ד׳" plan the task on the coming
Monday and make it due on the Wednesday after it. The spans that are a week of
work (Sunday to Thursday or Friday, Monday to Friday or Saturday) and a span from
a day to itself stay in the title.

A due day follows "עד" ("עד יום שישי", "עד מחר", "עד ה-5 במרץ", "עד השבוע הבא",
"עד סוף היום"), "לפני" or "לא יאוחר מ" with a weekday or a date ("לפני יום שישי",
"לא יאוחר מיום שלישי"), or a label ("מועד אחרון", "תאריך יעד", "דדליין": "מועד
אחרון: יום חמישי", "דדליין מחר"), and a part of the day after it goes with it
("עד מחר בבוקר"). The day before a clock deadline is the due day, and the clock
stays in the title: "עד יום שישי בשעה 17:00" is due Friday. "עד היום" (so far),
"עד הבוקר", "עד שני" (which may be "until the second"), "עד סוף השבוע" and "עד
סוף החודש" (the end of the working week as often as the weekend), and "לפני
מחר" are not read, and neither is "לפני שבת", which means before the Sabbath
begins on Friday ("לפני יום שבת" and "עד שבת" are read).

"כל" and "מדי" with a day, week, month, year, weekday, or part of the day repeat
the task: "כל יום", "מדי יום", "כל שבוע", "כל חודש", "כל שנה", and the intervals
"כל יומיים", "כל שבועיים", "כל 3 ימים", and "כל שלושה שבועות". So do "אחת
לשבוע", "פעם בחודש", "פעם ב-3 חודשים", "יום כן יום לא" (every second day), "שבוע
כן שבוע לא", and "על בסיס יומי" ("על בסיס שבועי", "חודשי", and "שנתי" too). A
weekday repeats every week ("כל יום שני"), a list repeats on each of its days
("כל שני וחמישי", "כל ב׳ וד׳", "בימי שני וחמישי", "כל שבוע ביום שני"), a span of
weekdays after "כל" or "בימי" holds the days it names ("כל יום ראשון עד חמישי",
"בימים א׳-ה׳"), and "כל סוף שבוע" and "כל סופ״ש" repeat on Saturday and Sunday.
"כל חודש ב-5" and "ב-5 לכל חודש" repeat on the 5th of each month. A part of the
day after "כל" ("כל בוקר", "כל ערב", "כל לילה", "כל יום בבוקר") repeats every day
and gives an hour beside it its half of the day: "כל בוקר בשעה 6" repeats every
day at 06:00.

An interval shorter than a day ("כל שעתיים"), "כל הבוקר" (all morning), "כל ערב
חג" (a holiday's eve), "כל יום ראשון בחודש" (one Sunday of the month), "כל בוקר
ובערב" (twice a day), and "כל" with a compound that holds "יום" ("כל יום
הולדת") are no repeat and stay in the title whole. The adjectives "יומי",
"שבועי", "חודשי", and "שנתי" are not read ("דוח שבועי"), because they follow
their noun as a title's own words do; only "על בסיס" gives them a repeat. The
working-day phrases "כל יום עבודה", "בימי עבודה", and "ימי חול" stay whole too.

A length says that it is one: "30 דקות", "2 שעות", "1.5 שעות", "3 שעות ו-20
דקות", "שעה ו-30 דקות", "חצי שעה", "רבע שעה", "שלושת רבעי שעה" (45 minutes),
"שעה וחצי", "שעתיים", "שעתיים וחצי", "שלוש שעות", "עשרים דקות", "שעה אחת", "30
דק׳", and "3 שע׳", each maybe after "בערך", "כ-", "למשך", "במשך", "ל-", "של",
"בן", or "בת" ("ריצה של 30 דקות", "סרט בן שעתיים"). "שעה" and "דקה" alone are
lengths only after one of those words ("בערך שעה", "למשך שעה"). An amount after
"בעוד", "עוד", "תוך", "כל", "עד", "לפני", "אחרי", "לפחות", "מ-", or "ב-", or before
"לפני", "אחרי", "ביום", "בשבוע", "בחודש", or "מאז", names a moment, an interval, a
bound, or a rate, not a length ("בעוד 30 דקות", "30 דקות ביום", "30 דקות לפני
הפגישה"), and neither is a side of a range of amounts ("2-3 שעות", "בין 2 ל-3
שעות"); each stays in the title whole. "ריצה 30 דקות כל יום" is a length of 30
minutes and a daily repeat.

"עדיפות גבוהה" is high priority, "עדיפות בינונית" (or "רגילה") the middle one,
and "עדיפות נמוכה" the low one, each also with "ב" before "עדיפות", after a colon
("עדיפות: גבוהה"), and with "מאוד". "דחוף", "דחופה", "בהול", and "בדחיפות",
maybe with "מאוד" or "ביותר", are high priority only at the end of the line, or
at its start before a colon or a comma ("דחוף: להגיש דוח"); anywhere else "דחוף"
is an ordinary adjective and stays in the title ("דחוף לקנות חלב"). "חשוב" is
not a priority word.

German words are read when German is among your device's preferred languages,
in any regional variant (Germany, Austria, and Switzerland). The umlauts and ß
are optional: ä, ö, ü, and ß are read as the plain letter and the digraphs ae,
oe, ue, and ss as the same letters, so "übermorgen", "uebermorgen", and
"ubermorgen" are one word, and the title keeps the letters you typed. German
says a clock time with "um" and "Uhr": "um 15 Uhr", "um 15:30 Uhr", "15.30
Uhr", "um 15 Uhr 30", "um 15h", "um 3", and an hour spelled as a word after
"um" or "gegen" ("um drei Uhr", "gegen vier"). An hour from 1 to 6 with no part
of the day is in the afternoon ("um 3 Uhr" is 3 PM) unless it is written with a
zero ("06:30"), and a part of the day sets the hour: "morgens" and "vormittags"
are the morning, "mittags" is noon at 12 and "nachmittags" the afternoon from 1
to 6, "abends" is the evening, and "nachts" runs past midnight, so "um 2 Uhr
nachts" is 02:00 on the next day and "um 11 Uhr nachts" is 23:00. "Um 12 Uhr
nachts", "um 24 Uhr", and "um Mitternacht" mean 00:00 the next day. A part of
the day beside the day phrase sets a bare hour too ("heute Abend um 7" is
19:00, "morgen früh um 6" is 06:00), and so does "Abendessen" or "Abendbrot"
("Abendessen um 8" is 20:00).

German names the half hour by the hour it leads to: "halb vier" is 3:30,
"viertel nach drei" is 3:15, and "Viertel vor vier" is 3:45. "Viertel vier"
(3:15), "dreiviertel vier" (3:45), "fünf nach drei", and "zehn vor vier" are times
only after "um" ("um zehn vor vier" is 3:50), since without it they could be
words of a title. A bare hour counts only at the end of the line or before a
word that can follow a time: a preposition, a pronoun, a conjunction, or the
infinitive of an everyday activity ("um 3 mit Anna", "um 7 aufstehen"). "Um 3
Kuchen" and "ab 15 Personen" count things and "Preis um 5 erhöhen" says by how
much, so they stay in the title. An hour with "Uhr" is a time wherever it
stands, and a time that names a deadline ("bis 17 Uhr", "vor 17 Uhr", "nach 17
Uhr") stays in the title, while "ab 17 Uhr" starts at 17:00. An hour count
written with h is a clock time from 13h on or after "um", "gegen", or "ab"
("15h", "um 10h"), and a length from 2h to 8h ("2h", "1h30"); 9h to 12h alone
could be either, so they stay in the title. With German among your languages,
English leaves an hour count written with h to German as well.

| Detail | German |
|---|---|
| Day | heute, heute Abend, heute Nacht, morgen, morgen früh, übermorgen, Freitag, am Freitag, diesen Freitag, nächsten Freitag, nächste Woche, am Wochenende, in 3 Tagen, in einer Woche |
| Date | 15. Oktober, 15 Oktober, am 1. Mai 2027, 15. Okt., 15.10., 15.10.2026, 15/10, 2026-10-15 |
| Date range | vom 3. bis 5. Mai, vom 30. Mai bis 2. Juni, vom 3.5. bis 5.5., zwischen dem 3. und 5. Mai, 3.-5. Mai, 3-5 Mai, von Montag bis Mittwoch |
| Due day | bis Freitag, bis zum 15. Oktober, bis morgen, spätestens Freitag, fällig am Freitag, Frist: Freitag, Deadline Freitag, zum 31.7. |
| Time | um 15 Uhr, um 15:30 Uhr, 15.30 Uhr, um 15h, gegen 15 Uhr, ab 15 Uhr, um 3 Uhr nachmittags, um 8 Uhr abends, um drei, halb vier, viertel nach drei, um zehn vor vier, um Mitternacht; von 14 bis 16 Uhr, von 14:00 bis 16:30 Uhr, 14-16 Uhr |
| Repeat | jeden Tag, täglich, jeden Montag, montags, jeden Montag und Donnerstag, jede Woche, wöchentlich, alle 2 Wochen, alle zwei Tage, jeden zweiten Tag, jede zweite Woche, zweiwöchentlich, jeden Monat, monatlich, am 15. jedes Monats, jedes Jahr, jährlich, werktags, an Wochenenden |
| Length | 30 Min, 30 Minuten, 1 Std, 2 Stunden, 1,5 Stunden, 1 Stunde 30 Minuten, eine halbe Stunde, anderthalb Stunden, eine Viertelstunde, dreiviertel Stunde, für 2 Stunden, 2h, 1h30 |
| Priority | dringend, wichtig (at the end, or "Dringend:" at the start), hohe Priorität, niedrige Priorität, Prio 1, Prio: niedrig |

A weekday alone or after "am" is the coming one, and a weekday that names today
means a week ahead ("am Dienstag" on a Tuesday is next Tuesday). "Diesen
Freitag" is this week's, which may be today, and "nächsten Freitag" is next
week's. A part of the day may follow a weekday or be written onto it ("Freitag
Abend", "Samstagabend", "Freitag früh"). Weeks start on Monday, as the app's
weeks do: "nächste Woche" plans the task seven days ahead, and the weekend is
Saturday and Sunday ("am Wochenende" is the coming Saturday, "nächstes
Wochenende" the one after). The abbreviations Mo, Di, Mi, Do, Fr, Sa, and So are
ordinary words too ("so", "do"), so they name a day only after a word that
points at one ("am Mo", "von Mo bis Mi", "bis kommenden Fr", "jeden Mo"), and a
weekday that is part of a name or a title stays ("Frau Montag", "Montag-Meeting",
"Sonntagsbraten"). No past day is read: "gestern", "vorgestern", and "letzten
Montag" stay in the title. "Morgen" is tomorrow in lowercase, and in capitals
where a line opens with it ("Morgen Zahnarzt") or a part of the day follows it
("Morgen früh"); elsewhere a capitalized "Morgen" is the noun for the morning
("guten Morgen", "am Morgen"). "In 3 Tagen" and "in 2 Wochen" count days and
weeks; months and years are not read.

A written date has its day number before the month ("15. Oktober", "15
Oktober", "1. Mai 2027", "5. Jänner"), or is in digits with the day first
("15.10.", "15.10.2026", "15.10.26", "15/10", "15-10-2026", "2026-10-15"), maybe
with a weekday in front ("Freitag, den 16.10.", "Fr. 16.10."), and "am", "ab",
"für", or "zum" may open it. A month abbreviation needs a dot, its own or the
day's ("5. Okt", "5 Okt."), since several are words too (Jan, Mar, Sep).
Digits with no closing dot ("15.10") are a date only after a word that
introduces it ("am 15.10", "bis 15.10"), since "15.10 Uhr" is a time. A date
without a year that has already passed means next year's, and a year written
after it must not be past or more than ten years ahead ("5. Oktober 2025" stays
in the title). A day the calendar lacks ("31. April"), a month alone ("im Mai",
"Mitte Oktober"), a day of the month alone ("bis zum 5."), and numbers that
number things ("Kapitel 3.5.", "Version 2.3.4") stay in the title.

A date range plans the task on its first day and makes it due on its last:
"vom 3. bis 5. Mai", "vom 3. bis zum 5. Mai", "zwischen dem 3. und 5. Mai",
"3.-5. Mai", "3-5 Mai", and "vom 28.12. bis 2.1." run from the first date to the
last, and a month written once serves both days. A span of weekdays does the
same: "von Montag bis Mittwoch" and "von Mo bis Mi" plan the coming Monday and
make the task due on the Wednesday after it, while Monday to Friday is the
working week, which repeats. The end must come after the start ("vom 5. bis 3.
Mai" stays in the title), and the end names its month, so "vom 3. bis 5." is
never a range. "Bis" joins the two days only after "vom" or "von", or after a
first day that has its ordinal dot ("3. bis 5. Mai"); a bare number before
"bis" belongs to the title ("Sprint 12 bis 20 Mai" is due on May 20), as it
does before a spaced dash ("Sprint 12 - 20 Mai" is planned for May 20). A range
names both the planned day and the due day, so another day in the same line
stays in the title.

A due day follows "bis" ("bis Freitag", "bis zum 15. Oktober", "bis morgen",
"bis spätestens Freitag", "bis kommenden Fr"), "spätestens", "fällig" ("fällig am
Freitag"), "zum" with a date ("zum 31.7."), or a label ("Frist: Freitag",
"Abgabefrist 15.10.", "Deadline Freitag", "Stichtag 1.11."). The day before a
clock deadline is the due day, and the clock stays in the title: "bis Freitag 17
Uhr" is due Friday, and "17 Uhr" stays. "Bis bald", "bis Ende Juli", "bis Ende
der Woche", and "bis Juli" are not read.

"Jeden" or "jede" with a day, week, month, or year repeats the task ("jeden
Tag", "jede Woche", "jeden Monat", "jedes Jahr"), and so do the adverbs
"täglich", "wöchentlich", "monatlich", and "jährlich" wherever they stand in the
line, while the adjectives with an ending ("tägliche Aufgaben", "wöchentlicher
Bericht") stay in the title. The counted intervals are "alle 3 Tage", "alle
zwei Wochen", "alle 14 Tage" (every second week), "jeden zweiten Tag", "jede
zweite Woche", "zweiwöchentlich", "vierzehntägig", "vierteljährlich", and
"halbjährlich". A weekday repeats every week ("jeden Montag", "montags", "an
jedem Montag"), a list repeats on each of its days ("jeden Montag und
Donnerstag", "montags, mittwochs und freitags", "jeden Mo und Do"), "werktags",
"an Werktagen", "Mo-Fr", and "von Montag bis Freitag" repeat on the working
days, and "jedes Wochenende" and "an Wochenenden" on Saturday and Sunday. A
weekday after an interval fixes its days ("alle 2 Wochen montags", "jede zweite
Woche am Freitag", "alle zwei Wochen jeden Montag"), a day of the month repeats
each month ("am 15. jedes Monats", "zum 1. jedes Monats", "jeden Monat am 15."),
and "einmal pro Woche" and "einmal im Monat" repeat weekly and monthly. A
weekday by its place in the month ("jeden ersten Montag im Monat", "jeden
letzten Freitag", "jeden 2. Montag") has no repeat rule and stays in the title
whole, and so does "zweimal pro Woche", which counts times.

A length says that it is one: "30 Min", "30 Minuten", "1 Std", "2 Stunden", "1,5
Stunden", "1 Stunde 30 Minuten", "2h", "1h30", "eine halbe Stunde", "1/2
Stunde", "anderthalb Stunden", "zweieinhalb Stunden", "eine Viertelstunde",
"dreiviertel Stunde", and "zwanzig Minuten", maybe after "für", "ca.", "etwa",
or "Dauer:", or before "lang" ("30 Minuten lang"). An amount after "in",
"alle", "nach", "vor", "um", "pro", "ab", "bis", "mindestens", or "höchstens", or
before "vorher", "später", "früher", or "pro Tag", names a moment, an interval,
a bound, or a rate, not a length ("in 30 Minuten", "alle 2 Stunden", "2 Stunden
pro Tag", "30 Minuten vorher"), and a side of a range of amounts ("5-6
Stunden") is none either.

"Priorität hoch", "hohe Priorität", and "Prio 1" are high priority, "mittlere
Priorität" ("Prio 2") the middle one, and "niedrige Priorität" ("Prio:
niedrig", "Prio 3") the low one. "Dringend", "dringlich", "eilig", and
"wichtig", also with "sehr" ("sehr wichtig"), are high priority only at the end
of the line, or at its start before a colon or a comma ("Wichtig:
Steuererklärung abgeben"); anywhere else they are ordinary adjectives and stay
in the title ("Das ist wichtig für mich"), and "nicht dringend" turns the word
around, so it stays too.

Dutch words are read when Dutch is among your device's preferred languages, in
any regional variant (the Netherlands and Belgium). Accents are optional: é, ë,
ï, and ó are read as the plain letter, so "één" and "een", "vóór" and "voor", and
"tweeënhalf" and "tweeenhalf" are one word, and the title keeps the letters you
typed. Dutch says a clock time with "om" and then "uur", a colon, or "u" after
the hour: "om 15:00", "om 15.30 uur", "om 15u30", "om 3 uur", "om 3", and an
hour spelled as a word ("om drie uur", "om drie"). A time written with a dot
("15.30") needs "om" or "uur", since without them it could be a number. An hour
from 1 to 6 with no part of the day is in the afternoon ("om 3 uur" is 3 PM)
unless it is written with a zero ("06:00"), and a part of the day sets the hour:
"'s ochtends", "'s morgens", and "voormiddags" are the morning, "'s middags" and
"namiddags" the afternoon, "'s avonds" the evening, and "'s nachts" runs past
midnight, so "om 2 uur 's nachts" is 02:00 on the next day and "om 11 uur 's
nachts" is 23:00. "Om 12 uur 's nachts", "om 24 uur", and "om middernacht" mean
00:00 the next day. The apostrophe of "'s middags" may be straight, curly, or
left out. A part of the day beside the day phrase sets a bare hour too
("vanavond om 7" is 19:00, "morgenavond om 8" is 20:00), and so does "avondeten"
or "diner" ("Avondeten om 7" is 19:00).

Dutch names the half hour by the hour it leads to: "half vier" is 3:30, "kwart
over drie" is 3:15, and "kwart voor vier" is 3:45. "Tien over drie" (3:10),
"vijf voor half vier" (3:25), and "vijf over half vier" (3:35) are times only
after "om", and "half een" needs a word before it ("om half een" is 12:30),
since without one they could be words of a title. A bare hour counts only at the
end of the line or before a word that can follow a time: a preposition, a
pronoun, a conjunction, or the infinitive of an everyday activity ("om 3 met
Anna", "om 7 opstaan"). "Om 3 koekjes" counts things and "om 5 verhogen" says by
how much, so they stay in the title. A count of hours with "uur" is a length
when it stands alone ("rapport 2 uur" lasts two hours) and a clock time after
"om", a day, a date, or a part of the day ("om 3 uur", "morgen 3 uur", "vrijdag
14 uur", "'s avonds 8 uur"); "morgen 3 uur lang" is a length again. An hour from
13 on with no "om" or day ("13 uur") is not read. A count written with "u" is a
clock time ("15u", "om 15u30"), and one written with h is a length, as in
English ("2h"). A clock time that names a bound ("tot 17 uur", "voor 17:00",
"tegen 17 uur", "uiterlijk 17:00", "na 18 uur", "niet later dan 17 uur") stays
in the title, while the day before it is the due day: "voor vrijdag om 17 uur"
is due Friday, and "om 17 uur" stays.

| Detail | Dutch |
|---|---|
| Day | vandaag, vanavond, vannacht, morgen, morgenochtend, morgenavond, morgen vroeg, overmorgen, vrijdag, op vrijdag, deze vrijdag, volgende vrijdag, vrijdagavond, volgende week, volgende week maandag, in het weekend, dit weekend, volgend weekend, over 3 dagen, over een week |
| Date | 15 oktober, op 15 oktober, 1 mei 2027, 15 okt., vrijdag 16 oktober, 15-10-2026, 15.10.2026, op 15/10 |
| Date range | van 3 tot 5 mei, van 3 tot en met 5 mei, 3 t/m 5 mei, 3-5 mei, van 30 mei tot 2 juni, tussen 3 en 5 mei, van maandag tot woensdag |
| Due day | voor vrijdag, tot vrijdag, tot en met vrijdag, tegen vrijdag, uiterlijk vrijdag, ten laatste vrijdag, deadline vrijdag, voor 15 oktober |
| Time | om 15:00, om 15.30 uur, om 15u30, om 3 uur, om drie uur, om 3 uur 's middags, om 8 uur 's avonds, 's avonds om 8, half vier, om kwart over drie, om tien over drie, om middernacht; van 14 tot 16 uur, tussen 14 en 16 uur, 14:00-16:00, van half 3 tot half 5 |
| Repeat | elke dag, dagelijks, elke maandag, maandags, elke maandag en donderdag, elke week, wekelijks, om de week, om de 2 weken, elke twee dagen, elke maand, maandelijks, elke maand op de 15e, elk jaar, jaarlijks, elk kwartaal, doordeweeks, op werkdagen, elk weekend |
| Length | 30 min, 30 minuten, 2 uur, 1,5 uur, 1 uur 30 min, een half uur, anderhalf uur, een kwartier, drie kwartier, een uurtje, 45 minuten lang, duur: 2 uur, 2h |
| Priority | dringend, belangrijk, urgent (at the end, or "Dringend:" at the start), hoge prioriteit, gemiddelde prioriteit, lage prioriteit, prio 1, prio: laag |

A weekday alone or after "op" is the coming one, and a weekday that names today
means a week ahead ("op dinsdag" on a Tuesday is next Tuesday). "Komende
vrijdag" and "aanstaande vrijdag" are the coming one too, "deze vrijdag" is this
week's, which may be today, and "volgende vrijdag" is next week's. A part of the
day may follow a weekday or be written onto it ("vrijdagavond", "vrijdag
avond", "vrijdagochtend"). Weeks start on Monday, as the app's weeks do:
"volgende week" plans the task seven days ahead, "volgende week maandag" and
"maandag volgende week" name next Monday, and the weekend is Saturday and
Sunday ("dit weekend" and "in het weekend" are the coming Saturday, "volgend
weekend" the one after). The abbreviations ma, di, wo, do, vr, za, and zo are
ordinary words too ("zo", "do"), so they name a day only after a word that
points at one ("op ma", "van ma tot wo", "elke ma", "komende vr", "deze wo"),
and a weekday that is part of a name or a compound stays ("mevrouw Maandag",
"maandag-meeting", "vrijdagmiddagborrel"). No past day is read: "gisteren",
"eergisteren", "gisteravond", "vorige maandag", "afgelopen vrijdag", "vorige
week", and "vorig weekend" stay in the title, and so does a weekend named by
what it comes before ("voor het weekend"). "Morgen" is tomorrow, while
"goedemorgen" and "de morgen" are the greeting and the noun for the morning, so
they stay. "Over 3 dagen" and "over 2 weken" count days and weeks; months and
years are not read.

A written date has its day number before the month ("15 oktober", "op 15
oktober", "1 mei 2027", "15 okt.", "3 sept"), or is in digits with the day first
("15-10-2026", "15/10/2026", "15.10.2026", "15.10."), maybe with a weekday in
front ("vrijdag 16 oktober", "vr. 16 okt"). Digits with no year ("15-10",
"15/10", "15.10") are a date only after "op", "voor", "tot", "tegen",
"uiterlijk", or "vanaf" ("op 15-10", "vanaf 15/10"), since without one they could
be a score, a version, or a room number. A date without a year that has already
passed means next year's, and a year written after it must not be past or more
than ten years ahead ("15 oktober 2025" stays in the title). A day the calendar
lacks ("31 februari"), a month alone ("in mei"), and numbers that number things
("hoofdstuk 3.5", "versie 2.3.4", "score 3-1") stay in the title.

A date range plans the task on its first day and makes it due on its last: "van
3 tot 5 mei", "van 3 tot en met 5 mei", "3 t/m 5 mei", "3-5 mei", "van 30 mei
tot 2 juni", and "tussen 3 en 5 mei" run from the first date to the last, and a
month written once serves both days. A span of weekdays does the same: "van
maandag tot woensdag" and "vrijdag t/m zondag" plan the coming first day and
make the task due on the last day after it, while Monday to Friday ("ma-vr",
"maandag t/m vrijdag") is the working week, which repeats. The end must come
after the start ("van 5 tot 3 mei" stays in the title), and the end names its
month, so "van 3 tot 5" is never a range of days; it is the hours 15:00 to
17:00. "Tot" joins two days only after "van", while "t/m", "tot en met", and a
dash need no "van": "Vakantie 3 tot 5 mei" is due on May 5 and keeps the "3" in
the title, while "Vakantie 3-5 mei" is a range. A number alone before a spaced
dash belongs to the title ("Sprint 12 - 20 mei" is planned for May 20). A range
names both the planned day and the due day, so another day in the same line
stays in the title.

A due day follows "voor", "tot", "tot en met", "t/m", "tegen", "uiterlijk", or
"ten laatste" ("voor vrijdag", "tot en met vrijdag", "uiterlijk 15 oktober"), or
a label ("deadline vrijdag", "deadline: vrijdag", "einddatum 15 oktober",
"inleverdatum vrijdag"), and "uiterlijk" may follow the day ("vrijdag
uiterlijk"). A weekday abbreviation after a deadline word ("voor vr", "tot ma")
is not read, and neither is "voor het weekend".

"Elke" or "iedere" with a day, week, month, or year repeats the task ("elke
dag", "elke week", "elke maand", "elk jaar"), and so do the adverbs "dagelijks",
"wekelijks", "maandelijks", and "jaarlijks" at the end of the line, or at its
start before a colon or a comma. Before a noun they are adjectives and stay in
the title ("Wekelijks overleg", "Dagelijkse stand-up"). The counted intervals
are "om de dag", "om de week", "om de 2 weken", "elke twee dagen", "elke 3
dagen", "elke 14 dagen" (every second week), "elke derde dag", "elke tweede
week", "tweewekelijks", "om de maand", "elke 2 maanden", "elk kwartaal", "elk
half jaar", and "elke twee jaar". A weekday repeats every week ("elke maandag",
"maandags", "'s maandags"), a list repeats on each of its days ("elke maandag en
donderdag", "maandags en donderdags", "elke ma en wo"), "doordeweeks", "op
werkdagen", "elke werkdag", and "ma-vr" repeat on the working days, and "elk
weekend" and "in de weekenden" repeat on Saturday and Sunday, while "in het
weekend" is one day. A weekday after an interval fixes its days ("elke 2 weken
op maandag", "om de week op dinsdag", "wekelijks op maandag"), and a day of the
month repeats each month ("elke maand op de 15e", "elke 15e van de maand",
"maandelijks op de eerste"). A weekday by its place in the month ("elke eerste
maandag van de maand", "elke tweede maandag") has no repeat rule and stays in
the title whole, and so does "twee keer per week", which counts times.

A length says that it is one: "30 min", "30 minuten", "2 uur", "1,5 uur", "1 uur
30 min", "2h", "een half uur", "anderhalf uur", "tweeënhalf uur", "een
kwartier", "drie kwartier", "een uurtje", and "twintig minuten", maybe after
"voor", "ongeveer", "ca.", "zo'n", or "duur:", or before "lang" ("45 minuten
lang"). A whole count of hours is a length up to 12 ("2 uur"). An amount after
"over", "na", "binnen", "elke", "om de", "per", or "minstens", or before
"geleden", "later", "extra", "te laat", or "per dag", names a moment, an
interval, a bound, or a rate, not a length ("over 30 min", "2 uur geleden",
"elke 2 uur", "2 uur per dag", "30 min voor de vergadering"); each stays in the
title whole.

"Prioriteit hoog", "hoge prioriteit", and "prio 1" are high priority,
"gemiddelde prioriteit" ("normale prioriteit", "prio 2") the middle one, and
"lage prioriteit" ("prio: laag", "prio 3") the low one. "Dringend", "belangrijk",
and "urgent", also with "zeer", "erg", or "heel" ("zeer belangrijk"), are high
priority only at the end of the line, or at its start before a colon or a comma
("Dringend: rapport schrijven"); anywhere else they are ordinary adjectives and
stay in the title ("Een belangrijke vergadering"), and "niet dringend" or
"minder belangrijk" turn the word around, so they stay too. A full stop or an
exclamation mark that ends the line goes with the word.

Romanian words are read when Romanian is among your device's preferred
languages, in any regional variant (Romania and Moldova). The diacritics are
optional: ă, â, and î are read as the plain letter, and the comma-below letters
ș and ț and the cedilla letters ş and ţ are both read as s and t, so "mâine" and
"maine", "sâmbătă" and "sambata", and "marți", "marţi", and "marti" are one
word, and the title keeps the letters you typed. Romanian says a clock time with
"la" or "ora" before the hour: "la ora 15", "la 15:30", "ora 15.30", "la 3", and
an hour spelled as a word ("la trei", "la ora trei"). A time written with a dot
whose minutes could be a month ("la 5.10") is a time only after "ora" ("ora
5.10"). An hour from 1 to 6 with no part of the day is in the afternoon ("la ora
3" is 3 PM) unless it is written with a zero ("la 03:00"), and a part of the day
sets the hour: "dimineața" is the morning, "după-amiaza" the afternoon, and
"seara" the evening ("la 8 seara" is 20:00, "la 7 dimineața" is 07:00).
"Noaptea" runs past midnight, so "la 2 noaptea" is 02:00 on the next day and "la
11 noaptea" is 23:00. "La 12 noaptea" and "la miezul nopții" mean 00:00 the next
day, and "la prânz" is noon. A part of the day beside the day phrase sets a bare
hour too ("diseară la 7" is 19:00, "mâine seara la 8" is 20:00), and so does
"cina" ("Cina la 8" is 20:00).

Romanian adds to the hour it names: "la 3 și jumătate" is 3:30, "la 3 și un
sfert" is 3:15, "la 3 fără un sfert" is 2:45, "la 3 fără 10" is 2:50, and "la 3
și 10" is 3:10. These spoken forms need "la" or "ora" before the hour, since
without one they could be words of a title ("Cumpără 3 și jumătate kg"), and
minutes with a unit word ("la 3 și 10 minute") stay in the title whole. A bare
hour counts only at the end of the line or before a word that can follow a time:
a preposition, a conjunction, a pronoun, or a day word ("la 3 cu Ana", "Mama sună
la 7"). "La 3 prieteni" counts people and "pâine la 3 lei" gives a price, so
they stay in the title. A count written with h is a length, as in English
("2h"), since Romanian does not write a clock time with that letter. A clock time
that names a bound ("până la ora 17", "înainte de 17:00", "după ora 18", "cel
târziu la ora 17") stays in the title, while the day before it is the due day:
"până vineri la ora 17" is due Friday, and "la ora 17" stays.

| Detail | Romanian |
|---|---|
| Day | azi, astăzi, diseară, în seara asta, mâine, mâine dimineață, mâine seara, poimâine, vineri, pe vineri, vineri asta, vineri viitoare, vineri seara, săptămâna viitoare, în weekend, weekendul acesta, weekendul viitor, peste 3 zile, peste o săptămână |
| Date | 15 octombrie, pe 15 octombrie, în data de 15 octombrie, 1 mai 2027, 15 oct., vineri 16 octombrie, 15.10.2026, 15/10/2026, pe 15.10 |
| Date range | de la 3 la 5 mai, de la 3 până la 5 mai, între 3 și 5 mai, în perioada 3-5 mai, 3-5 mai, de la 30 mai la 2 iunie, 3 mai - 5 mai, de la luni până miercuri |
| Due day | până vineri, până la 15 octombrie, cel târziu vineri, înainte de vineri, pentru vineri, termen: vineri, deadline vineri, scadent vineri |
| Time | la ora 15, la 15:30, ora 15.30, la 3, la trei, la 8 seara, la 7 dimineața, la 3 și jumătate, la 3 fără un sfert, la prânz, la miezul nopții, seara la 8; de la 14 la 16, între 14 și 16, 14:00-16:00 |
| Repeat | în fiecare zi, zilnic, în fiecare luni, lunea, în fiecare luni și joi, lunea și joia, în fiecare săptămână, săptămânal, o dată la două săptămâni, la două zile, din două în două zile, în fiecare lună, lunar, în fiecare 15 ale lunii, în fiecare an, în zilele lucrătoare, de luni până vineri, în fiecare weekend |
| Length | 30 de minute, 30 min, 2 ore, o oră, 1,5 ore, 2 ore și 30 de minute, o oră și jumătate, jumătate de oră, un sfert de oră, trei sferturi de oră, zece minute, durează 2 ore, 2h |
| Priority | urgent, important (at the end, or "Urgent:" at the start), prioritate mare, prioritate medie, prioritate scăzută, prio 1, prio: mică |

A weekday alone or after "la", "pe", "în", or "de" is the coming one, and a
weekday that names today means a week ahead ("marți" on a Tuesday is next
Tuesday). "Vineri asta" and "marți aceasta" are this week's, which may be today,
"vineri care vine" is the coming one, and "vineri viitoare" and "vineri
următoare" are next week's. A part of the day may follow a weekday ("vineri
dimineața", "vineri seara"). Weeks start on Monday, as the app's weeks do:
"săptămâna viitoare" plans the task seven days ahead, "săptămâna viitoare
vineri" and "vineri, săptămâna viitoare" name next Friday, and the weekend is
Saturday and Sunday ("în weekend" and "weekendul acesta" are the coming
Saturday, "weekendul viitor" the one after). The definite forms "lunea",
"martea", "miercurea", "joia", and "vinerea" name the day too ("lunea
viitoare"), and "sâmbăta" and "duminica" read like "sâmbătă" and "duminică".
"Luni" is also the plural of "lună", so after a count or before "de zile" it
stays in the title ("peste 3 luni", "două luni", "luni de zile"). No past day is
read: "ieri", "alaltăieri", "ieri seara", "luni trecută", "vinerea trecută",
"săptămâna trecută", and "weekendul trecut" stay in the title, and so does "azi
noapte", which names the night just gone as often as the one to come. "Peste 3
zile", "peste o săptămână", and "peste 2 săptămâni" count days and weeks; "în 3
zile" may mean within three days, so it is not read, and months and years are
not read either ("peste o lună", "peste un an").

A written date has its day number before the month ("15 octombrie", "pe 15
octombrie", "în data de 15 octombrie", "1 mai 2027", "15 oct.", "3 sept."), or is
in digits with the day first ("15.10.2026", "15.10.", "15/10/2026",
"15-10-2026"), maybe with a weekday in front ("vineri 16 octombrie", "vineri, 16
octombrie"). Digits with no year ("15.10", "15/10") are a date only after "pe" or
"în data de" ("pe 15.10") or after a deadline word ("până la 15.10"), since
without one they could be a score, a version, or a time. A date without a year
that has already passed means next year's, and a year written after it must not
be past ("15 octombrie 2025" stays in the title). A day the calendar lacks ("31
februarie"), a month alone ("Ianuarie", "Vacanța în mai"), and numbers that
number things ("capitolul 1.5.", "versiunea 2.3.4", "scor 3-1") stay in the
title. "Mai" is the month only where no adverb of comparison follows it: "3 mai"
is a date, while "3 mai multe" and "Mai multe idei" stay.

A date range plans the task on its first day and makes it due on its last: "de la
3 la 5 mai", "de la 3 până la 5 mai", "între 3 și 5 mai", "în perioada 3-5 mai",
"3-5 mai", "de la 30 mai la 2 iunie", and "3 mai - 5 mai" run from the first date
to the last, and a month written once serves both days. A span of weekdays does
the same: "de la luni până miercuri" and "vineri - duminică" plan the coming first
day and make the task due on the last day after it, while Monday to Friday ("luni
- vineri", "de luni până vineri") is the working week, which repeats. The end
must come after the start ("de la 5 la 3 mai" stays in the title), and the end
names its month, so "de la 3 la 5" is never a range of days; it is the hours
15:00 to 17:00. "Până la" joins two days only after "de la", "din", or "în
perioada", or after a first date that has its own month: "Vacanță 3 până la 5
mai" is due on May 5 and keeps the "3" in the title, while "Vacanță de la 3 până
la 5 mai" is a range. A number alone before a spaced dash belongs to the title
("Sprint 12 - 20 mai" is planned for May 20). A range names both the planned day
and the due day, so another day in the same line stays in the title.

A due day follows "până", "până la", "cel târziu", "înainte de", or "pentru"
("până vineri", "cel târziu pe 15 octombrie", "înainte de vineri", "tema pentru
luni"), or a label ("termen: vineri", "termen limită vineri", "deadline vineri",
"scadent 15 octombrie"), and "cel târziu" may follow the day ("vineri cel
târziu"). The weekend is no due day ("până la weekend" and "pentru weekend" stay
in the title), and neither is a count ("pentru 3 zile", "Salariu pentru 3 luni").

"În fiecare" with a day, week, month, or year repeats the task ("în fiecare zi",
"în fiecare săptămână", "în fiecare lună", "în fiecare an", "în fiecare
dimineață"), and so do the adverbs "zilnic", "săptămânal", "lunar", and "anual"
at the end of the line, or at its start before a colon or a comma. Before a noun
they are adjectives and stay in the title ("ședință săptămânală"). The counted
intervals are "la două zile", "din două în două zile", "în fiecare a doua zi",
"la fiecare 3 zile", "o dată la două săptămâni", "în fiecare a doua săptămână",
"la 14 zile" (every second week), "la fiecare 2 luni", "trimestrial", and
"semestrial". A weekday repeats every week ("în fiecare luni", "lunea"), a list
repeats on each of its days ("în fiecare luni și joi", "lunea și joia"),
"zilele lucrătoare", "în zilele de lucru", and "luni - vineri" repeat on the
working days, and "în fiecare weekend" and "în weekenduri" repeat on Saturday
and Sunday, while "în weekend" is one day. "Sâmbăta" and "duminica" read like
the plain names, so they repeat a task only beside another definite form
("lunea și sâmbăta"), and "sâmbăta și duminica" stays in the title. A weekday
after an interval fixes its days ("o dată la 2 săptămâni joia"), and a day of
the month repeats each month ("în fiecare 15 ale lunii", "în fiecare lună pe
15", "lunar pe 15"). A weekday by its place in the month ("prima luni din
lună", "ultima vineri din lună", "în fiecare a doua marți") has no repeat rule
and stays in the title whole.

A length says that it is one: "30 de minute", "30 min", "2 ore", "1,5 ore", "2
ore și 30 de minute", "2h", "o oră", "o oră și jumătate", "jumătate de oră", "un
sfert de oră", "trei sferturi de oră", and "zece minute", maybe after "pentru",
"cam", "aproximativ", "timp de", "durează", or "durata:". The particle "de" joins
a count from 20 up to its noun ("30 de minute") and may be left out ("30
minute"). A whole count of hours is a length up to 24 ("24 de ore"). An amount
after "peste", "în", "după", "acum", "la fiecare", or "mai mult de", or before
"înainte", "în urmă", "pe zi", "mai târziu", or "suplimentare", names a moment,
an interval, a bound, or a rate, not a length ("peste 2 ore", "în 10 minute", "2
ore în urmă", "2 ore pe zi", "30 de minute înainte"); each stays in the title
whole.

"Prioritate mare", "prioritate înaltă", "de mare prioritate", and "prio 1" are
high priority, "prioritate medie" ("prio 2") the middle one, and "prioritate
scăzută" ("prioritate mică", "prio: mică", "prio 3") the low one. "Urgent" and
"important", also with "foarte" ("foarte important"), are high priority only at
the end of the line, or at its start before a colon or a comma ("Urgent:
raport"); anywhere else they are ordinary adjectives and stay in the title ("Un
raport urgent pentru Anna"), and "nu e urgent" turns the word around, so it
stays too. The feminine and plural forms ("urgentă", "importante") are not
read, since without diacritics they are the nouns "urgență" and "importanță". A
full stop or an exclamation mark that ends the line goes with the word.

Indonesian words are read when Indonesian is among your device's preferred
languages, in any regional variant. Indonesian has no diacritics, so the line is
read as typed, and the title keeps the letters you typed. Indonesian says a
clock time with "jam" or "pukul" before the hour: "jam 15", "jam 15.30", "pukul
15.30", "jam 3", and an hour spelled as a word ("jam tiga"). A time with minutes
and a part of the day needs no "jam" ("7.30 malam"). An hour from 1 to 6 with no
part of the day is in the afternoon ("jam 3" is 3 PM) unless it is written with
a zero ("jam 03.00"), and a part of the day sets the hour: "pagi" is the
morning, "siang" midday, "sore" the afternoon, and "malam" the evening ("jam 8
malam" is 20:00, "jam 7 pagi" is 07:00), while "subuh" and "dini hari" are the
small hours ("jam 4 subuh" is 04:00). A part of the day beside the hour on the
line sets a bare hour too ("malam jam 8" is 20:00, "besok pagi jam 7" is
07:00), and so does a meal ("makan malam jam 7" is 19:00). "Malam" runs past
midnight, so "jam 12 malam" and "tengah malam" are 00:00 on the next day, and
"tengah hari" is noon.

Indonesian counts the half hour toward the next hour: "setengah empat" is 3:30
("jam setengah 4", "setengah empat sore"). "Kurang" takes minutes off and
"lewat" adds them: "jam 3 kurang 10" is 2:50, "jam 3 kurang seperempat" is 2:45,
and "jam 3 lewat 15" is 3:15. A bare "setengah empat" counts only at the end of
the line or before a word that can follow a time ("setengah empat dengan Ani");
"setengah empat kilo" gives an amount, so it stays in the title. English is read
beside Indonesian, so "3pm", "17:30", and "30 min" work as they do alone, and
Indonesian does not write a clock time with the letter h, so "2h" stays a
length. A clock time that names a bound ("sebelum jam 5", "sampai pukul 17.00",
"paling lambat jam 5 sore") stays in the title, while the day before it is the
due day: "sebelum Jumat jam 17" is due Friday, and "jam 17" stays. A time range
may leave the part of the day off one side: the side takes the reading that fits
the other, so "jam 9 sampai 5 sore" is 09:00 to 17:00.

| Detail | Indonesian |
|---|---|
| Day | hari ini, malam ini, nanti malam, besok, besok pagi, lusa, Jumat, hari Jumat, Jumat ini, Jumat depan, Jumat sore, minggu depan, akhir pekan, akhir pekan depan, 3 hari lagi, dalam 3 hari, seminggu lagi |
| Date | 15 Oktober, tanggal 15 Oktober, tgl. 15 Okt, 1 Mei 2027, Jumat 16 Oktober, 15/10/2026, 15.10.2026, pada 15/10, tanggal 25 |
| Date range | 3-5 Mei, 3 sampai 5 Mei, 3 s/d 5 Mei, dari 3 hingga 5 Mei, antara 3 dan 5 Mei, 30 Mei - 2 Juni, dari Senin sampai Rabu |
| Due day | sebelum Jumat, sampai Jumat, paling lambat Jumat, sebelum tanggal 15 Oktober, tenggat Jumat, batas waktu Jumat, deadline Jumat, jatuh tempo 15 Oktober |
| Time | jam 15, jam 15.30, pukul 15.30, jam 3 sore, jam 8 malam, jam 7 pagi, jam 12 siang, jam 3 kurang 10, jam 3 lewat 15, setengah empat, tengah malam, 7.30 malam; jam 14-16, dari jam 14 sampai jam 16, antara jam 14 dan 16, jam 14.00-16.00 |
| Repeat | setiap hari, setiap pagi, harian, setiap Senin, setiap hari Senin, setiap Senin dan Kamis, setiap Senin sampai Jumat, setiap hari kerja, setiap akhir pekan, setiap minggu, mingguan, seminggu sekali, 2 minggu sekali, setiap 2 hari, setiap bulan, bulanan, setiap tanggal 15, setiap tahun, setiap triwulan |
| Length | 30 menit, 30 mnt, 2 jam, 1,5 jam, 1 jam 30 menit, setengah jam, sejam, seperempat jam, tiga perempat jam, dua jam, lima belas menit, selama 2 jam, durasi: 2 jam, 2h |
| Priority | penting, mendesak, urgent, darurat, segera (at the end, or "Penting:" at the start), prioritas tinggi, prioritas sedang, prioritas rendah, prio 1, prio: rendah |

A weekday alone or after "pada", "di", or "hari" is the coming one, and a weekday
that names today means a week ahead ("Selasa" on a Tuesday is next Tuesday).
"Selasa ini" is this week's, which may be today, and "Selasa depan" and "Jumat
minggu depan" are next week's. A part of the day may follow a weekday ("Jumat
sore"), and so may "sekali" ("besok pagi sekali"). Weeks start on Monday, as the
app's weeks do: "minggu depan" plans the task seven days ahead, and the weekend
is Saturday and Sunday ("akhir pekan" is the coming Saturday, "akhir pekan
depan" the one after). "Minggu" is also the word for the week, so it names
Sunday only after "hari" ("hari Minggu"), before a part of the day ("Minggu
pagi"), or beside another weekday ("Sabtu dan Minggu", "Jumat sampai Minggu");
"Minggu" alone, "minggu ini", and "Sekolah Minggu" stay in the title. A list of
weekdays names no one day ("Kelas Senin dan Rabu", "Senin atau Selasa"), so it
stays in the title too, and so do the names that hold a weekday ("Salat Jumat",
"Jumat Agung"). No past day is read: "kemarin", "kemarin lusa", "Senin lalu",
"minggu lalu", "semalam", and "tadi malam" stay in the title. A phrase whose day
cannot be named stays too: "besok lusa" means tomorrow or the day after, and
"malam Jumat" is the night before Friday ("makan malam Jumat" is dinner on
Friday). "3 hari lagi", "dalam 3 hari", "seminggu lagi", and "2 minggu lagi"
count days and weeks, while a count of times before them gives a rate ("tiga kali
dalam seminggu" stays in the title); months and years are not read ("bulan
depan", "sebulan lagi").

A written date has its day number before the month ("15 Oktober", "tanggal 15
Oktober", "pada 15 Oktober", "1 Mei 2027", "tgl. 15 Okt"), or is in digits with
the day first ("15/10/2026", "15-10-2026", "15.10.2026"), maybe with a weekday in
front ("Jumat 16 Oktober"). Digits with no year ("15/10") are a date only after
"pada", "tanggal", or a deadline word ("sebelum 15/10"), since without one they
could be a score, a version, or a time. A date without a year that has already
passed means next year's, and a year written after it must not be past ("15
Oktober 2025" stays in the title). "Tanggal 25" alone is the 25th of this month,
or of next month once it has passed. A day the calendar lacks ("31 Februari"), a
month alone ("Mei", "libur di bulan Mei"), and numbers that number things ("bab
1.5", "versi 2.3.4", "skor 3-1") stay in the title.

A date range plans the task on its first day and makes it due on its last: "3-5
Mei", "3 sampai 5 Mei", "3 s/d 5 Mei", "dari 3 hingga 5 Mei", "antara 3 dan 5
Mei", "30 Mei - 2 Juni", and "3 Mei sampai 5 Mei" run from the first date to the
last, and a month written once serves both days. A span of weekdays does the
same: "dari Senin sampai Rabu" and "Jumat - Minggu" plan the coming first day and
make the task due on the last day after it, while Monday to Friday after
"setiap" is the working week, which repeats. The end must come after the start
("5-3 Mei" stays in the title), and the end names its month, so "dari 3 sampai
5" is never a range of days; it is the hours 15:00 to 17:00. A number alone
before a spaced dash belongs to the title ("Sprint 12 - 20 Mei" is planned for
May 20). A range names both the planned day and the due day, so another day in
the same line stays in the title.

A due day follows "sebelum", "paling lambat", "paling telat",
"selambat-lambatnya", "sampai", "hingga", or a label ("tenggat", "batas waktu",
"deadline", "jatuh tempo"): "sebelum Jumat", "paling lambat tanggal 15
Oktober", "tenggat: Jumat", "sampai besok". The weekend is no due day ("sebelum
akhir pekan" stays in the title), and neither is a count ("untuk 3 hari").

"Setiap" or "tiap" with a day, week, month, or year repeats the task ("setiap
hari", "setiap minggu", "setiap bulan", "setiap tahun", "setiap pagi", "setiap
malam"), and so do the adjectives "harian", "mingguan", "bulanan", and "tahunan"
at the end of the line, or at its start before a colon or a comma. Before a noun
or in the middle of the line they stay in the title ("buku harian", "Laporan
harian untuk tim"). The counted intervals are "setiap 2 hari", "2 hari sekali",
"seminggu sekali", "sekali seminggu", "2 minggu sekali", "sekali dalam 2
minggu", "setiap 14 hari" (every second week), "setiap 2 bulan", "3 bulan
sekali", "setiap triwulan", and "setiap semester". A weekday repeats every week
("setiap Senin", "tiap hari Senin"), a list repeats on each of its days ("setiap
Senin dan Kamis", "setiap Senin, Rabu, dan Jumat"), "setiap Senin sampai Jumat",
"setiap hari kerja", and "pada hari kerja" repeat on the working days, and
"setiap akhir pekan" repeats on Saturday and Sunday, while "akhir pekan" alone is
one day. A part of the day after the weekdays goes with them ("setiap Jumat
malam"). "Setiap minggu" is every week and "setiap hari Minggu" every Sunday. A
weekday after an interval fixes its days ("setiap 2 minggu hari Kamis"), and a
day of the month repeats each month ("setiap tanggal 15", "setiap bulan tanggal
15", "tanggal 15 setiap bulan"). A weekday by its place in the month ("setiap
Senin pertama") has no repeat rule and stays in the title whole, and so does
every day with a day left out ("setiap hari kecuali Minggu"), a count of times
("dua kali seminggu"), or an interval of hours ("setiap 2 jam").

A length says that it is one: "30 menit", "30 mnt", "2 jam", "1,5 jam", "1 jam
30 menit", "2 jam setengah", "setengah jam", "sejam", "seperempat jam", "tiga
perempat jam", and "lima belas menit", maybe after "selama", "durasi", "sekitar",
"kurang lebih", or "untuk". "Jam" after a number is a length and before one the
clock ("3 jam" and "jam 3"), so a number that stands before "jam 10 pagi" is no
amount of hours ("ruang 3 jam 10 pagi"), and "jam" before a clock noun is no
length either ("2 jam tangan" is two watches). An amount after "dalam",
"setiap", "setelah", "sebelum", or "kurang dari", or before "lagi", "yang lalu",
"sehari", or "per hari", names a moment, an interval, a bound, or a rate, not a
length ("dalam 2 jam", "2 jam lagi", "setiap 2 jam", "2 jam sehari"); each stays
in the title whole, and so does a range of amounts ("2-3 jam", "2 sampai 3 jam").

"Prioritas tinggi", "prioritas utama", and "prio 1" are high priority,
"prioritas sedang" ("prio 2") the middle one, and "prioritas rendah" ("prio:
rendah", "prio 3") the low one. "Penting", "mendesak", "urgent", "darurat", and
"segera", also with "sangat" or "sekali" ("sangat penting"), are high priority
only at the end of the line, or at its start before a colon or a comma
("Penting: kirim laporan"); anywhere else they are ordinary adjectives and stay
in the title ("Dokumen penting dibawa"), and "tidak penting" or "kurang
mendesak" turn the word around, so they stay too. A full stop or an exclamation
mark that ends the line goes with the word.

Malay words are read when Malay is among your device's preferred languages, in
any regional variant. Malay has no diacritics, so the line is read as typed, and
the title keeps the letters you typed. Malay says a clock time with "pukul",
"jam", or "pkl" before the hour: "pukul 15", "pukul 15.30", "jam 3", "pkl 3",
and an hour spelled as a word ("pukul tiga"). A time with minutes and a part of
the day needs no "pukul" ("7.30 malam"). An hour from 1 to 6 with no part of the
day is in the afternoon ("pukul 3" is 3 PM) unless it is written with a zero
("pukul 03.00"), and a part of the day sets the hour: "pagi" is the morning,
"tengah hari" midday, "petang" the afternoon, and "malam" the evening ("pukul 8
malam" is 20:00, "pukul 7 pagi" is 07:00), while "subuh" and "dini hari" are the
small hours ("pukul 4 subuh" is 04:00). "PG" and "PTG", the 12-hour clock's AM
and PM that Apple's Malay writes, set the hour too ("9.30 PG" is 09:30, "3.30
PTG" is 15:30). A part of the day beside the hour on the line sets a bare hour
as well ("malam pukul 8" is 20:00, "esok pagi pukul 7" is 07:00), and so does a
meal, a prayer, or the fast ("makan malam pukul 7", "berbuka puasa pukul 7").
"Malam" runs past midnight, so "pukul 12 malam" and "tengah malam" are 00:00 on
the next day. "Tengah hari" is also the word for lunch, so it sets an hour
("pukul 1 tengah hari" is 13:00) but is no time of its own.

Malay puts the half hour after the hour: "pukul tiga setengah" is 3:30. A
quarter is said both ways ("tiga suku" is 3:15 or 2:45), and "setengah empat"
is 3:30 in Indonesian but is not said the same way everywhere in Malay, so
neither is read as a time and both stay in the title. English is read beside
Malay, so "3pm", "17:30", and "30 min" work as they do alone, and Malay does
not write a clock time with the letter h, so "2h" stays a length. A clock time
that names a bound ("sebelum pukul 5", "hingga jam 17.00", "paling lewat pukul 5
petang") stays in the title, while the day before it is the due day: "sebelum
Jumaat pukul 17" is due Friday, and "pukul 17" stays. A time range may leave
the part of the day off one side: the side takes the reading that fits the
other, so "dari 9 hingga 5 petang" is 09:00 to 17:00. When Malay and Indonesian
are both among your languages, both are read, Malay first, and the Indonesian
words that Malay does not write ("besok sore", "jam 3 sore", "tanggal 5
Oktober", "setengah empat") work as they do for Indonesian alone.

| Detail | Malay |
|---|---|
| Day | hari ini, malam ini, malam nanti, esok, esok pagi, pagi esok, lusa, Jumaat, hari Jumaat, Jumaat ini, Jumaat depan, Jumaat petang, minggu depan, hujung minggu, hujung minggu depan, 3 hari lagi, dalam 3 hari, seminggu lagi |
| Date | 15 Oktober, tarikh 15 Oktober, 15hb Oktober, 15 Okt, 1 Mei 2027, Jumaat 16 Oktober, 15/10/2026, 15.10.2026, pada 15/10, tarikh 25, 25hb |
| Date range | 3-5 Mei, 3 hingga 5 Mei, 3 sampai 5 Mei, dari 3 hingga 5 Mei, antara 3 dan 5 Mei, 30 Mei - 2 Jun, dari Isnin hingga Rabu |
| Due day | sebelum Jumaat, hingga Jumaat, sampai esok, paling lewat Jumaat, selewat-lewatnya Jumaat, sebelum 15 Oktober, tarikh akhir Jumaat, had masa Jumaat, deadline Jumaat |
| Time | pukul 15, pukul 15.30, jam 15:30, pkl 3, pukul 3 petang, pukul 8 malam, pukul 7 pagi, pukul 12 tengah hari, pukul tiga setengah, tengah malam, 7.30 malam, 9.30 PG, 3.30 PTG; pukul 14-16, dari pukul 14 hingga pukul 16, antara pukul 14 dan 16, pukul 14.00-16.00 |
| Repeat | setiap hari, setiap pagi, harian, setiap Isnin, setiap hari Isnin, setiap Isnin dan Khamis, setiap Isnin hingga Jumaat, setiap hari kerja, setiap hujung minggu, setiap minggu, mingguan, seminggu sekali, 2 minggu sekali, setiap 2 hari, setiap bulan, bulanan, setiap tarikh 15, setiap tahun |
| Length | 30 minit, 30 min, 2 jam, 1,5 jam, 1 jam 30 minit, setengah jam, sejam, sejam setengah, suku jam, dua jam, lima belas minit, selama 2 jam, tempoh 2 jam |
| Priority | penting, mendesak, urgent, segera (at the end, or "Penting:" at the start), keutamaan tinggi, keutamaan sederhana, keutamaan rendah, prioriti 1, prio rendah |

A weekday alone or after "pada" or "hari" is the coming one, and a weekday that
names today means a week ahead ("Selasa" on a Tuesday is next Tuesday). "Selasa
ini" is this week's, which may be today, and "Selasa depan", "Selasa hadapan",
and "Jumaat minggu depan" are next week's. A part of the day may follow a
weekday ("Jumaat petang") or come before it ("petang Jumaat"), and may come
before or after "esok" ("esok pagi", "pagi esok"); a part of the day that forms
a noun with the word before it stays with that noun ("Makan malam esok" is
dinner tomorrow). Weeks start on Monday, as the app's weeks do: "minggu depan"
plans the task seven days ahead, and the weekend is Saturday and Sunday
("hujung minggu" is the coming Saturday, "hujung minggu depan" the one after).
"Minggu" is the word for the week and never Sunday, which is "Ahad" ("hari
Ahad"); "Minggu" alone stays in the title. A list of weekdays names no one day
("Kelas Isnin dan Rabu"), so it stays in the title too, and so do the names that
hold a weekday ("Solat Jumaat", "Jumaat Agung"). No past day is read:
"semalam", "kelmarin", "Isnin lepas", "minggu lalu", and "malam tadi" stay in
the title. A phrase whose day cannot be named stays too: "esok lusa" means
tomorrow or the day after, and "malam Jumaat" is the night before Friday
("makan malam Jumaat" is dinner on Friday). "3 hari lagi", "dalam 3 hari",
"seminggu lagi", and "2 minggu lagi" count days and weeks, while a count of
times before them gives a rate ("tiga kali dalam seminggu" stays in the title);
"dalam seminggu" alone is as often "per week" as "in a week", and months and
years are not read ("bulan depan", "sebulan lagi").

A written date has its day number before the month ("15 Oktober", "tarikh 15
Oktober", "pada 15 Oktober", "15hb Oktober", "1 Mei 2027", "15 Okt"), or is in
digits with the day first ("15/10/2026", "15-10-2026", "15.10.2026"), maybe with
a weekday in front ("Jumaat 16 Oktober"). Digits with no year ("15/10") are a
date only after "pada", "tarikh", or a deadline word ("sebelum 15/10"), since
without one they could be a score, a version, or a time. A date without a year
that has already passed means next year's, and a year written after it must not
be past ("15 Oktober 2025" stays in the title). "Tarikh 25" and "25hb" alone are
the 25th of this month, or of next month once it has passed. A day the calendar
lacks ("31 Februari"), a month alone ("Mei", "cuti pada bulan Mei"), and numbers
that number things ("bab 1.5", "versi 2.3.4", "skor 3-1") stay in the title.
"Mac" is the month unless a product name follows it ("2 Mac mini" counts
computers), and "2HB" is a pencil, not the 2nd.

A date range plans the task on its first day and makes it due on its last: "3-5
Mei", "3 hingga 5 Mei", "3 sampai 5 Mei", "dari 3 hingga 5 Mei", "antara 3 dan 5
Mei", "30 Mei - 2 Jun", and "3 Mei hingga 5 Mei" run from the first date to the
last, and a month written once serves both days. A span of weekdays does the
same: "dari Isnin hingga Rabu" and "Jumaat - Ahad" plan the coming first day and
make the task due on the last day after it, while Monday to Friday after
"setiap" is the working week, which repeats. The end must come after the start
("5-3 Mei" stays in the title), and the end names its month, so "dari 3 hingga
5" is never a range of days; it is the hours 15:00 to 17:00. A number alone
before a spaced dash belongs to the title ("Sprint 12 - 20 Mei" is planned for
May 20). A range names both the planned day and the due day, so another day in
the same line stays in the title.

A due day follows "sebelum", "paling lewat", "paling lambat",
"selewat-lewatnya", "selambat-lambatnya", "hingga", "sehingga", "sampai", or a
label ("tarikh akhir", "tarikh tamat", "had masa", "deadline"): "sebelum
Jumaat", "paling lewat 15 Oktober", "tarikh akhir: Jumaat", "sampai esok". The
weekend is no due day ("sebelum hujung minggu" stays in the title), and neither
is a count ("untuk 3 hari").

"Setiap" or "tiap" ("tiap-tiap") with a day, week, month, or year repeats the
task ("setiap hari", "setiap minggu", "setiap bulan", "setiap tahun", "setiap
pagi", "setiap malam"), and so do the adjectives "harian", "mingguan",
"bulanan", and "tahunan" at the end of the line, or at its start before a colon
or a comma. Before a noun or in the middle of the line they stay in the title
("buku harian", "Berita Harian", "Laporan harian untuk pasukan"). The counted
intervals are "setiap 2 hari", "2 hari sekali", "seminggu sekali", "sekali
seminggu", "2 minggu sekali", "sekali dalam 2 minggu", "setiap 14 hari" (every
second week), "setiap 2 bulan", "3 bulan sekali", and "setiap suku tahun". A
weekday repeats every week ("setiap Isnin", "tiap hari Isnin"), a list repeats
on each of its days ("setiap Isnin dan Khamis", "setiap Isnin, Rabu dan
Jumaat"), "setiap Isnin hingga Jumaat", "setiap hari kerja", and "pada hari
kerja" repeat on the working days, and "setiap hujung minggu" repeats on
Saturday and Sunday, while "hujung minggu" alone is one day. A part of the day
after the weekdays goes with them ("setiap Jumaat malam"). A weekday after an
interval fixes its days ("setiap 2 minggu hari Khamis"), and a day of the month
repeats each month ("setiap tarikh 15", "setiap 15hb", "setiap bulan pada
tarikh 15", "tarikh 15 setiap bulan"). A weekday by its place in the month
("setiap Isnin pertama") has no repeat rule and stays in the title whole, and so
does every day with a day left out ("setiap hari kecuali Ahad"), a count of
times ("dua kali seminggu"), or an interval of hours ("setiap 2 jam").

A length says that it is one: "30 minit", "30 min", "2 jam", "1,5 jam", "1 jam
30 minit", "2 jam setengah", "setengah jam", "sejam", "sejam setengah", "suku
jam", "tiga suku jam", and "lima belas minit", maybe after "selama", "tempoh",
"anggaran", "kira-kira", "lebih kurang", or "untuk". "Jam" after a number is a
length and before one the clock ("3 jam" and "jam 3"), so a number that stands
before "jam 10 pagi" is no amount of hours ("bilik 3 jam 10 pagi"), and "jam"
before a clock noun is no length either ("2 jam tangan" is two watches). An
amount after "dalam", "setiap", "selepas", "sebelum", or "kurang daripada", or
before "lagi", "yang lalu", "sehari", "per hari", or "sekali", names a moment, an
interval, a bound, or a rate, not a length ("dalam 2 jam", "2 jam lagi", "setiap
2 jam", "2 jam sehari"); each stays in the title whole, and so does a range of
amounts ("2-3 jam", "2 hingga 3 jam").

"Keutamaan tinggi", "keutamaan utama", "prioriti tinggi", and "prio 1" are high
priority, "keutamaan sederhana" ("prio 2") the middle one, and "keutamaan
rendah" ("prio rendah", "prio 3") the low one. "Penting", "mendesak", "urgent",
and "segera", also with "sangat" ("sangat penting"), are high priority only at
the end of the line, or at its start before a colon or a comma ("Penting: hantar
laporan"); anywhere else they are ordinary adjectives and stay in the title
("Dokumen penting dibawa"), and "tidak penting" or "kurang mendesak" turn the
word around, so they stay too ("Beli mi segera" is instant noodles). A full stop
or an exclamation mark that ends the line goes with the word.

Vietnamese words are read when Vietnamese is among your device's preferred
languages, in any regional variant. A line may be typed with every tone mark,
with none ("ngay mai", "thu hai", "3 gio chieu"), or with the stroke of "đ"
written as "d"; a word is read in one of those whole spellings, so "đem" (to
bring) is not "đêm" (night), "tôi" (I) is not "tối" (evening), and the name
"Tuấn" is not "tuần" (week). A few words are read only with their marks, since
without them they are another everyday word: "thứ Tư" ("thứ tự" is an order),
"tới", "mốt", "đúng", "khẩn", and "gấp" ("gặp" is to meet). The title keeps the
letters you typed, with the marks you typed.

Vietnamese says a clock time with "giờ" or the letter h after the hour: "3
giờ", "15 giờ 30", "15h", "7h30", "lúc 3 giờ", and an hour spelled as a word
("ba giờ chiều", "lúc ba giờ"). "Rưỡi" after the hour is the half hour ("3 giờ
rưỡi" is 3:30), and "kém" takes minutes off ("3 giờ kém 15" is 2:45). Minutes
after "h" follow it directly ("15h30") or, with their unit, after a space ("15h
30 phút"); a number after "h" and a space with no unit belongs to the next word
("18h 1 tiếng" is 18:00 and an hour). An hour from 1 to 6 with no part of the
day is in the afternoon ("3 giờ" is 3 PM) unless it is written with a zero ("03
giờ"), and a part of the day sets the hour: "sáng" is the morning, "trưa"
midday, "chiều" the afternoon, "tối" the evening, "đêm" and "khuya" the night
("7 giờ sáng" is 07:00, "8 giờ tối" is 20:00). A part of the day or a meal
written beside the hour sets it too ("tối 8 giờ" is 20:00, "ăn tối 7 giờ" is
19:00), and stays in the title. "12 giờ đêm", "12 giờ tối", and "nửa đêm" are
midnight at the end of the named day, so they plan the next day, and "2 giờ đêm"
is 02:00 on the next day. "SA" and "CH", the 12-hour clock's AM and PM that
Apple's Vietnamese writes, set the hour when typed in capitals ("9:30 SA" is
09:30, "3:30 CH" is 15:30); lowercase "sa" and "ch" stay in the title.

English is read beside Vietnamese, so "3pm", "17:30", and "30 min" work as they
do alone. Vietnamese writes a clock time with the letter h, so beside it "15h"
and "2h" are times (15:00 and 14:00), where English alone reads them as lengths;
a decimal ("1,5h") or an hour count up to 12 with minutes in "p" or "m" ("1h30p",
"1h30m") is still a length, while an hour past 12 with minutes ("15 giờ 30 phút",
"18h30p") is a clock time. A clock time that names a bound ("trước 5 giờ chiều", "chậm
nhất 17h", "sau 18:00") stays in the title, while the day before it is the due
day: "trước thứ Sáu 5 giờ chiều" is due Friday, and "5 giờ chiều" stays. A time
range may leave the part of the day off one side: the side takes the reading
that fits the other, so "từ 9 đến 5 giờ chiều" is 09:00 to 17:00. "Khoảng 3
giờ" and "tầm 3 giờ" are as often about three hours as about three o'clock, and
"12 giờ sáng" and "12 giờ chiều" are meant both ways, so each stays in the
title. French, Portuguese, and German also write a clock time with the letter h
and read "15h" first, so on a device that reads one of them and Vietnamese, a
"lúc" before it stays in the title.

| Detail | Vietnamese |
|---|---|
| Day | hôm nay, sáng nay, tối nay, ngày mai, sáng mai, chiều mai, ngày kia, thứ Sáu, vào thứ Sáu, thứ Sáu tuần này, thứ Sáu tuần sau, chiều thứ Sáu, thứ Sáu chiều, tuần sau, cuối tuần, cuối tuần sau, 3 ngày nữa, sau 3 ngày, 2 tuần nữa |
| Date | 15 tháng 10, ngày 15 tháng 10, 15 thg 10, 15 tháng 10 năm 2027, thứ Sáu 16 tháng 10, 15/10/2026, 15-10-2026, 15.10.2026, vào 15/10, ngày 15 |
| Date range | 3-5 tháng 5, từ 3 đến 5 tháng 5, từ ngày 3 đến ngày 5 tháng 5, từ 3/5 đến 5/5, giữa ngày 3 và ngày 5 tháng 5, từ thứ Hai đến thứ Sáu |
| Due day | trước thứ Sáu, hạn chót thứ Sáu, đến hết hôm nay, chậm nhất ngày mai, trước 15 tháng 10, hạn nộp 15/10, deadline thứ Sáu, hạn thứ Sáu tuần sau |
| Time | 3 giờ chiều, lúc 3 giờ chiều, 15h, 15h30, 15 giờ 30, 3 giờ rưỡi, 3 giờ kém 15, ba giờ chiều, 8 giờ tối, 12 giờ đêm, nửa đêm, 9:30 SA, 3:30 CH; từ 3 giờ đến 5 giờ chiều, 3-5 giờ chiều, từ 14h đến 16h30, 14:00-16:00, giữa 3 giờ và 5 giờ chiều |
| Repeat | mỗi ngày, hằng ngày, mỗi sáng, mỗi thứ Hai, mọi thứ Hai, mỗi thứ Ba và thứ Năm, mỗi thứ Hai đến thứ Sáu, mỗi ngày làm việc, mỗi cuối tuần, mỗi tuần, hàng tuần, mỗi 2 tuần, cách tuần, 2 ngày một lần, mỗi tháng, ngày 15 hàng tháng, mỗi năm |
| Length | 30 phút, 2 tiếng, 1,5 giờ, 1.5h, 1h30p, 1 tiếng rưỡi, nửa tiếng, 1 giờ 30 phút, 2 tiếng 30 phút, mất 2 giờ, khoảng 30 phút, 2 giờ đồng hồ |
| Priority | quan trọng, khẩn cấp, gấp, khẩn (at the end, or "Quan trọng:" at the start), ưu tiên cao, ưu tiên trung bình, ưu tiên thấp, ưu tiên 1 |

A weekday alone, or after "vào", is the coming one, and a weekday that names
today means a week ahead ("thứ Ba" on a Tuesday is next Tuesday). "Thứ Ba tuần
này" is this week's, which may be today, and a weekday of this week that has
passed ("thứ Hai tuần này" on a Tuesday) is not read; "thứ Sáu tuần sau" and
"tuần sau thứ Sáu" are next week's. "Thứ 2" to "thứ 7" are Monday to Saturday
and "Chủ nhật" is Sunday, while the short forms "T2" to "T7" and "CN" stay in
the title. A part of the day may come before or after a weekday ("chiều thứ
Sáu", "thứ Sáu chiều") and before "nay" or "mai" ("sáng mai", "buổi sáng mai");
a part of the day that forms a noun with the word before it stays with that
noun ("Ăn tối mai" is dinner tomorrow, and the title stays "Ăn tối"). Weeks
start on Monday, as the app's weeks do: "tuần sau" plans the task seven days
ahead, and the weekend is Saturday and Sunday ("cuối tuần" is the coming
Saturday, "cuối tuần sau" the one after). "Mai" alone is a name and the apricot
blossom ("Họp Mai", "hoa mai"), so tomorrow is read after "ngày" or a part of
the day only, and "mốt" (the day after tomorrow) is read after "ngày" only
("ngày mốt").

No past day is read: "hôm qua", "hôm kia", "tuần trước", "thứ Hai tuần trước",
"cuối tuần trước", and "3 ngày trước" stay in the title. A phrase whose day
cannot be named stays too: a list of weekdays ("thứ Hai và thứ Tư"), a month or
a year ahead ("tháng sau", "năm sau", "2 tháng nữa"), a count of working days
("3 ngày làm việc nữa"), a bound at a period or a period a task is for ("trước
cuối tuần", "đến tuần sau", "trong 3 ngày nữa", "3 tuần tới"), the ordinals
("lần thứ hai", "ngày thứ hai", which is the second day, and "thứ tự", which is
an order), the names of days ("Thứ Sáu đen", "Chủ nhật Phục Sinh"), and "3 ngày
2 đêm", which is three days and two nights. "Vào" may stand before a day ("vào
ngày mai", "vào thứ Sáu", "vào 15/10").

A written date has its day number before the month ("15 tháng 10", "ngày 15
tháng 10", "15 thg 10"), or is in digits with the day first ("15/10/2026",
"15-10-2026", "15.10.2026"), maybe with a weekday in front ("thứ Sáu 16 tháng
10"). Digits with no year ("15/10") are a date only after "ngày", "vào", or a
deadline word ("trước 15/10"), since without one they could be a fraction, a
score, or a version. A date without a year that has already passed means next
year's, and a year written after it must not be past ("15 tháng 10 năm 2025"
stays in the title). "Ngày 5" alone is the 5th of this month, or of next month
once it has passed. A day the calendar lacks ("30 tháng 2"), a month alone
("tháng 5"), and numbers that number things ("chương 1.5", "phiên bản 2.3.4",
"tỉ số 3-1") stay in the title. So do dates of the lunar calendar ("15 tháng 8
âm lịch", "15/8 AL", "âm lịch 15/8", "mùng 5 tháng 10"), which people use for
Tết, the full moon, and anniversaries and which the planner does not count in.

A date range plans the task on its first day and makes it due on its last: "3-5
tháng 5", "từ 3 đến 5 tháng 5", "từ ngày 3 đến ngày 5 tháng 5", "từ 3/5 đến
5/5", and "giữa ngày 3 và ngày 5 tháng 5" run from the first date to the last,
and a month written once serves both days. A span of weekdays does the same:
"từ thứ Hai đến thứ Sáu" and "thứ Sáu đến Chủ nhật" plan the coming first day
and make the task due on the last day after it, while Monday to Friday after
"mỗi" is the working week, which repeats. The end must come after the start
("5-3 tháng 5" stays in the title), and the end names its month. A number alone
before a spaced dash belongs to the title ("Sprint 12 - 14 tháng 10" is planned
for October 14). A range names both the planned day and the due day, so another
day in the same line stays in the title.

A due day follows "trước", "hạn", "hạn chót", "hạn cuối", "hạn nộp", "hết hạn",
"đến hạn", "đến", "đến hết", "tới", "cho đến", "chậm nhất", "muộn nhất", "trễ
nhất", or "deadline": "trước thứ Sáu", "hạn chót 15 tháng 10", "đến hết hôm
nay", "chậm nhất ngày mai". The weekend is no due day ("trước cuối tuần" stays
in the title), and neither is a count ("trong 3 ngày nữa").

"Mỗi", "mọi", "hằng", or "hàng" with a day, week, month, or year repeats the
task ("mỗi ngày", "hằng ngày", "mỗi tuần", "hàng tháng", "mỗi năm", "mỗi sáng",
"mỗi tối"), and so does a weekday before "hàng tuần" ("thứ Hai hàng tuần"). A
weekday repeats every week ("mỗi thứ Hai", "mọi thứ Hai", "các thứ Hai"), a list
repeats on each of its days ("mỗi thứ Ba và thứ Năm", "mỗi thứ 2, 4, 6"), and
"mỗi thứ Hai đến thứ Sáu", "mỗi ngày làm việc", and "các ngày trong tuần" repeat
on the working days, while "mỗi cuối tuần" repeats on Saturday and Sunday and
"cuối tuần" alone is one day. The counted intervals are "mỗi 2 ngày", "mỗi hai
tuần", "cứ 3 tháng", "2 ngày một lần", "2 tuần/lần", "cách ngày", "cách tuần",
"một lần mỗi tuần", and "mỗi 2 tuần vào thứ Ba" (a weekday after an interval
fixes its days). A day of the month repeats each month ("ngày 15 hàng tháng",
"mỗi tháng vào ngày 5"). A weekday by its place in the month ("thứ Hai đầu tiên
của tháng") has no repeat rule and stays in the title whole, and so does every
day with a day left out ("mỗi ngày trừ Chủ nhật"), a count of times ("2 lần một
tuần", "mỗi tuần ba lần"), an interval of hours ("mỗi 2 giờ"), and "mỗi tháng 10"
(every October).

A length says that it is one: "30 phút", "2 tiếng", "1,5 giờ", "1 tiếng rưỡi",
"nửa tiếng", "1 giờ 30 phút", "2 tiếng 30 phút", "1h30p", and "ba mươi phút",
maybe after "mất", "tốn", "kéo dài", "thời lượng", "ước tính", "dự kiến",
"khoảng", or "tầm". A bare number of "giờ" is a clock hour ("Họp 3 giờ" is 15:00),
so "giờ" is a length with "đồng hồ" ("2 giờ đồng hồ"), after "mất", "tốn", "kéo
dài", "thời lượng", "ước tính", or "dự kiến" ("mất 2 giờ"), and with minutes
counted in "phút" when no lead and no part of the day makes it a clock ("3 giờ
15 phút" is three hours fifteen minutes, and "lúc 3 giờ 15 phút" is 15:15), while
"tiếng" is always a length ("2 tiếng"). An hour past 12 with minutes ("15 giờ
30 phút", "18h30p") is a clock time and no length of 15 or 18 hours, unless one
of those openers comes first ("mất 15 giờ 30 phút"). An amount after "trong",
"sau", "mỗi", "cách", "trước", "tối đa", or "ít nhất", or before "nữa", "trước",
"một ngày", or "một lần", names a moment, an interval, a bound, or a rate, not a
length ("trong 2 tiếng", "sau 30 phút", "2 tiếng nữa", "mỗi 2 giờ", "2 tiếng một
ngày"); each stays in the title whole, and so does a range of amounts ("2-3
tiếng", "2 hoặc 3 tiếng"), a fraction ("1/2 giờ"), and the language of a lesson
("học 2 tiếng Anh").

"Ưu tiên cao", "mức độ ưu tiên cao", and "ưu tiên 1" are high priority, "ưu tiên
trung bình" ("ưu tiên 2") the middle one, and "ưu tiên thấp" ("ưu tiên: thấp",
"ưu tiên 3") the low one. "Khẩn cấp", "quan trọng", "khẩn", and "gấp", also with
"rất", "cực kỳ", "vô cùng", "hết sức", or "khá" ("rất quan trọng"), are high
priority only at the end of the line, or at its start before a colon or a comma
("Quan trọng: nộp báo cáo"); anywhere else they are ordinary words and stay in
the title ("tài liệu quan trọng của dự án", "gấp quần áo"), and "không gấp",
"chưa khẩn cấp", and "không quan trọng" turn the word around, so they stay too,
as does "quan trọng nhất". A full stop or an exclamation mark that ends the line
goes with the word.

Turkish words are read when Turkish is among your device's preferred languages,
in any regional variant. A line may be typed with every Turkish letter, with
none ("persembe", "aksam", "gunu"), or with the dotted and dotless i in either
case ("SALI", "Salı", "sali", and "SALİ" are one word); the title keeps the
letters you typed. A letter typed as a base letter and a separate combining mark
is left alone, so a detail word typed that way is not read. A case ending
belongs to a detail only where it is listed ("cumaya kadar", "15 Ekim'de",
"saat 5'te"), with a straight, a curly, or no apostrophe, so "Cuma'nın",
"yarından", and "cumaya" alone stay in the title.

Turkish says a clock time with "saat" before the hour or a locative ending after
it: "saat 15:00", "saat 3", "saat üç", "3'te", "15:30'da". "Buçuk" adds the half
hour to the hour it follows ("saat üç buçuk" is 3:30, never 2:30), "çeyrek
geçe" and "çeyrek var" add and take off a quarter ("üçü çeyrek geçe" is 3:15,
"dörde çeyrek var" is 3:45), and "on geçe" and "on var" count minutes ("üçe on
var" is 2:50). "Buçuk" is read with "saat", a part of the day, or the ending
"-ta" ("üç buçukta"), since "üç buçuk" alone is as often an amount ("iki buçuk
kilo"), and minutes with a unit word ("üçü on dakika geçe") stay in the title
whole. A bare number is a time only after "saat", a part of the day, or a
locative ending, so "Toplantı 5" and "akşam 8 kişi" stay in the title. An hour
from 1 to 6 with no part of the day is in the afternoon ("saat 3" is 3 PM)
unless it is written with a zero ("saat 03:00"), and a part of the day sets the
hour: "sabah" is the morning, "öğleden sonra" and "akşam" the afternoon and the
evening, "öğlen" noon, and "gece" runs past midnight ("gece 2'de" is 02:00 on
the next day, and "gece 12" and "gece yarısı" are 00:00 on the next day). A
clock time that names a bound ("saat 17:00'ye kadar", "en geç saat 5", "5'ten
önce", "saat 9'dan sonra") stays in the title, while the day before it is the
due day: "cuma saat 17:00'ye kadar" is due Friday, and "saat 17:00'ye kadar"
stays.

English is read beside Turkish, so "3pm", "17:30", and "30 min" work as they do
alone, and a "15:30" with nothing around it is read as it is in English. Turkish
does not write a clock time with the letter h, so "15h" and "2h" stay lengths,
as in English alone.

| Detail | Turkish |
|---|---|
| Day | bugün, bu akşam, bu gece, yarın, yarın sabah, yarın akşam, öbür gün, cuma, cuma günü, bu cuma, haftaya cuma, önümüzdeki cuma, cuma akşamı, haftaya, önümüzdeki hafta, bu hafta sonu, önümüzdeki hafta sonu, 3 gün sonra, bir hafta sonra |
| Date | 15 Ekim, 15 Ekim 2026, 15 Ekim'de, 15 Eki., Cuma 16 Ekim, 15.10.2026, 15/10/2026, tarih 15.10, 15/10'da |
| Date range | 3-5 Mayıs, 3 Mayıs - 5 Mayıs, 3 Mayıs'tan 5 Mayıs'a kadar, 3 ile 5 Mayıs arası, cumadan pazara kadar, cuma-pazar, cuma ile pazar arası |
| Due day | cumaya kadar, yarına kadar, 15 Ekim'e kadar, cumadan önce, son tarih cuma, en geç cuma, teslim cuma, deadline cuma |
| Time | saat 15:00, saat 15.00, 15:30'da, saat 3'te, akşam 8'de, sabah 9, öğleden sonra 3, gece 12, saat üç, saat üç buçuk, üç buçukta, üçü çeyrek geçe, dörde çeyrek var, üçe on var, gece yarısı; saat 14-16, 14.00-16.00, 10:00'dan 11:00'e kadar, saat 14 ile 16 arası |
| Repeat | her gün, her sabah, her pazartesi, her pazartesi ve perşembe, pazartesi günleri, pazartesileri, pazartesi akşamları, her hafta, haftada bir, iki günde bir, iki haftada bir, her 3 hafta, ayda bir, her ay, yılda bir, her yıl, gün aşırı, her ikinci hafta, hafta içi her gün, iş günleri, hafta sonları, her hafta sonu, her ayın 15'inde; günlük, haftalık, aylık, yıllık at the end |
| Length | 30 dakika, 30 dk, 1 saat, 2 saat, 1,5 saat, yarım saat, çeyrek saat, bir buçuk saat, 1 saat 30 dakika, 45 dakikalık, yaklaşık 30 dakika, tahmini süre 2 saat |
| Priority | acil, önemli, çok önemli (at the end, or "Acil:" at the start), yüksek öncelik, orta öncelik, düşük öncelik, öncelik: yüksek, öncelik 1 |

A weekday alone is the coming one, and a weekday that names today means a week
ahead ("salı" on a Tuesday is next Tuesday). "Bu" before a weekday is the coming
one counting today ("bu salı" on a Tuesday is today, "bu pazartesi" is the
Monday ahead), "haftaya cuma" and "önümüzdeki hafta cuma" are next week's, and
"önümüzdeki cuma" and "gelecek cuma" are the coming one. Weeks start on Monday,
as the app's weeks do: "haftaya" plans the task seven days ahead, and the
weekend is Saturday and Sunday ("bu hafta sonu" is the coming Saturday,
"önümüzdeki hafta sonu" the one after). "Pazar" is also the market, so it names
Sunday only after "bu", "önümüzdeki", "gelecek", or "haftaya", or with "günü" or
a part of the day ("pazar günü", "pazar akşamı"); "pzt" and "cmt" read, while
the other short forms ("sal", "çar", "per", "cum", "paz") are words of their own
and stay. "Hafta sonu" and "hafta içi" alone are nouns of many titles and stay
too, and so does the two-word "bu gün", which is "this day" in many sentences;
"bugün" is today.

No past day is read: "dün", "evvelsi gün", "geçen cuma", and "geçen hafta sonu"
stay in the title, and so does a clock time right after one ("dün saat 3'te").

A written date has its day number before the month ("15 Ekim", "15 Ekim 2026",
"15 Ekim'de"), maybe with a weekday in front ("Cuma 16 Ekim"), or is in digits
with the day first ("15.10.2026", "15/10/2026", "15.10."). The month
abbreviations ("Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl",
"Eki", "Kas", "Ara") read when they are capitalized or end in a period, since
several are ordinary words ("ara", "kas", "haz"). Digits with no year ("15.10",
"15/10") are a date only after "tarih" or a deadline word, with a locative
ending ("15/10'da"), or before "kadar", since without one they could be a time,
a score, or a version. A date without a year that has already passed means next
year's, and a year written after the month places the date ("15 Ekim 2027").

A date range plans the task on its first day and makes it due on its last:
"3-5 Mayıs", "3 Mayıs - 5 Mayıs", "3 Mayıs'tan 5 Mayıs'a kadar", and "3 ile 5
Mayıs arası" run from the first date to the last, and a month written once
serves both days. A span of weekdays does the same: "cumadan pazara kadar",
"cuma-pazar", and "cuma ile pazar arası" plan the coming first day and make the
task due on the last day after it, while Monday to Friday ("pazartesi-cuma") is
the working week, which repeats. A range names both the planned day and the due
day, so another day in the same line stays in the title.

A due day is a day with the dative ending before "kadar", "dek", or "değin"
("cumaya kadar", "yarına kadar", "15 Ekim'e kadar"), a day before "önce"
("cumadan önce"), or a day after "son tarih", "en geç", "teslim", "termin", or
"deadline" ("son tarih cuma", "en geç cuma", "teslim: yarın").

"Her" with a day, week, month, or year repeats the task ("her gün", "her hafta",
"her ay", "her yıl"), and so do "her sabah", "her akşam", and "her gece" (each
day). A weekday repeats every week ("her pazartesi", "pazartesi günleri",
"pazartesileri", "cumaları", "pazartesi akşamları"), a list repeats on each of
its days ("her pazartesi ve perşembe", "pazartesi ve perşembe günleri"), and
"hafta içi her gün", "iş günleri", and "her iş günü" repeat on the working days,
while "hafta sonları" and "her hafta sonu" repeat on Saturday and Sunday. The
counted intervals are "iki günde bir", "3 haftada bir", "her 3 hafta", "her üç
gün", "her ikinci hafta", "gün aşırı", "haftada bir", "ayda bir", and "yılda
bir" (a weekday after a weekly interval fixes its day: "iki haftada bir cuma"),
and "her ayın 15'inde" repeats on a day of the month. "Her iki gün" stays in the
title, since it is "both days" as often as "every two days". "Günlük",
"haftalık", "aylık", and "yıllık" repeat the task only at the end of the line,
at its start before a colon or a comma, or with "olarak" ("rapor haftalık
olarak"); before a noun they are adjectives and stay in the title ("haftalık
rapor", "yıllık izin").

A length says that it is one: "30 dakika", "30 dk", "2 saat", "1,5 saat", "yarım
saat", "çeyrek saat", "bir buçuk saat", "1 saat 30 dakika", "iki saat", and the
adjective forms ("45 dakikalık toplantı" is a length of 45 minutes), maybe after
"yaklaşık", "tahmini süre", "süre:", or "toplam", and before "boyunca" or
"kadar". An amount that names a moment, a bound, or an interval ("30 dakika
sonra", "2 saat içinde", "en fazla 2 saat", "her 2 saat", "2 saat önce") is no
length and stays in the title whole, and so does a range of amounts ("2-3
saat").

"Yüksek öncelik", "öncelik: yüksek", and "öncelik 1" are high priority, "orta
öncelik" ("öncelik 2") the middle one, and "düşük öncelik" ("öncelik 3") the low
one. "Acil", "önemli", and "çok önemli" are high priority only at the end of the
line, or at its start before a colon or a comma ("Acil: rapor"); anywhere else
they are ordinary adjectives and stay in the title ("Acil servis", "Önemli bir
toplantı"), and "acil değil" turns the word around, so it stays too. A full stop
or an exclamation mark that ends the line goes with the word.

Greek words are read when Greek is among your device's preferred languages, in
any regional variant. A line may be typed with or without accents and with the
final sigma written either way ("αύριο", "αυριο", and "ΑΥΡΙΟ" are one word, as
are "μέρες" and "μερεσ"); the title keeps the letters you typed. A letter typed
as a base letter and a separate combining mark is left alone, so a detail word
typed that way is not read. A word counts only as a whole word in Greek
letters, so "αυριανό" (of tomorrow) and "Δευτερόλεπτα" (seconds) hold no day,
and a word joined to another by a hyphen ("σήμερα-αύριο") stays in the title.

Greek says a clock time with "στις" (or "στη", "στην", "ώρα") before the hour:
"στις 15:00", "στις 3", "στις τρεις", "ώρα 15:00". "Και μισή" and "και
τέταρτο" add to the hour they follow ("στις 3 και μισή" is 3:30, "στις τρεις
και τέταρτο" is 3:15), "παρά" takes minutes off the hour after it ("στις 4 παρά
τέταρτο" is 3:45, "στις 4 παρά 10" is 3:50), and "εννιάμισι" is 9:30. Minutes
counted with a unit word ("στις 3 και 10 λεπτά") stay in the title whole. A bare
number is a time only after "στις", "στη", "στην", or "ώρα", and only when the
word after it can follow a time, so "Συνάντηση 5", "στις 3 άτομα", and "στις 3
ώρες" stay in the title. An hour from 1 to 6 with no part of the day is in the
afternoon ("στις 3" is 3 PM) unless it is written with a zero ("στις 03:00"),
and a part of the day sets the hour: "το πρωί" is the morning, "το απόγευμα" and
"το βράδυ" the afternoon and the evening, "π.μ." and "μ.μ." count like AM and
PM, "στις 2 τη νύχτα" is 02:00 on the next day, and "τα μεσάνυχτα" (or "12 το
βράδυ") is 00:00 on the next day. "Το μεσημέρι" alone stays in the title, while
"στις 12 το μεσημέρι" is noon. A clock time that names a bound ("μέχρι τις 5",
"πριν τις 17:00", "μετά τις 3", "στις 5 το αργότερο") stays in the title, while
the day before it is the due day: "την Παρασκευή μέχρι τις 5" is due Friday, and
"μέχρι τις 5" stays.

English is read beside Greek, so "3pm", "17:30", and "30 min" work as they do
alone, and a "15:30" with nothing around it is read as it is in English. Greek
does not write a clock time with the letter h, so "15h" and "2h" stay lengths,
as in English alone.

| Detail | Greek |
|---|---|
| Day | σήμερα, απόψε, αύριο, αύριο το πρωί, αύριο βράδυ, μεθαύριο, Παρασκευή, την Παρασκευή, αυτή την Παρασκευή, την επόμενη Παρασκευή, Παρασκευή της επόμενης εβδομάδας, την επόμενη εβδομάδα, την άλλη εβδομάδα, το Σαββατοκύριακο, σε 3 μέρες, μετά από 3 μέρες, σε μία εβδομάδα |
| Date | 15 Οκτωβρίου, 15 Οκτωβρίου 2026, 15 Οκτ., 1η Μαΐου, 25ης Μαρτίου, 15 Οκτώβρη, Παρασκευή 16 Οκτωβρίου, 15.10.2026, 15/10/2026, στις 15/10, ημερομηνία 15.10 |
| Date range | 3-5 Μαΐου, 3 Μαΐου - 5 Μαΐου, από 3 έως 5 Μαΐου, από τις 3 μέχρι τις 5 Μαΐου, από Παρασκευή έως Κυριακή, Παρασκευή-Κυριακή |
| Due day | μέχρι την Παρασκευή, έως Παρασκευή, ως αύριο, μέχρι και την Παρασκευή, μέχρι τις 15 Οκτωβρίου, πριν την Παρασκευή, προθεσμία Παρασκευή, παράδοση αύριο, deadline Παρασκευή, Παρασκευή το αργότερο, για αύριο |
| Time | στις 15:00, στις 3, στις 3 το απόγευμα, 3 μ.μ., 9 π.μ., στις 3 και μισή, στις 3 και τέταρτο, στις 4 παρά τέταρτο, στις 4 παρά 10, στις τρεις και είκοσι, στις εννιάμισι, ώρα 15:00, το απόγευμα στις 7, τα μεσάνυχτα; στις 14-16, από τις 3 έως τις 5 |
| Repeat | κάθε μέρα, κάθε πρωί, κάθε Δευτέρα, κάθε Δευτέρα και Πέμπτη, τις Δευτέρες, τα Σάββατα, κάθε εβδομάδα, κάθε μήνα, κάθε χρόνο, κάθε δύο μέρες, κάθε 2 εβδομάδες, κάθε δεύτερη Παρασκευή, μέρα παρά μέρα, εβδομάδα παρά εβδομάδα, μία φορά την εβδομάδα, τις καθημερινές, κάθε εργάσιμη μέρα, Δευτέρα-Παρασκευή, τα Σαββατοκύριακα, κάθε Σαββατοκύριακο, κάθε μήνα στις 15, κάθε 15 του μήνα; ημερησίως, εβδομαδιαίως, μηνιαίως, ετησίως; καθημερινά, εβδομαδιαία, μηνιαία, ετήσια at the end |
| Length | 30 λεπτά, 30 λ, 1 ώρα, 2 ώρες, 1,5 ώρα, μισή ώρα, μιάμιση ώρα, δύο ώρες και μισή, 1 ώρα και 30 λεπτά, δυόμισι ώρες, ένα τέταρτο, τρία τέταρτα της ώρας, είκοσι λεπτά, για 2 ώρες, περίπου 30 λεπτά, διάρκεια: 2 ώρες |
| Priority | επείγον, επείγουσα, σημαντικό, πολύ σημαντικό (at the end, or "Επείγον:" at the start), υψηλή προτεραιότητα, μεσαία προτεραιότητα, χαμηλή προτεραιότητα, προτεραιότητα: υψηλή, προτεραιότητα 1 |

A weekday alone is the coming one, and a weekday that names today means a week
ahead ("Τρίτη" on a Tuesday is next Tuesday). "Αυτή την" before a weekday is the
coming one counting today ("αυτή την Τρίτη" on a Tuesday is today), "την
επόμενη Παρασκευή" is the coming one, and "Παρασκευή της επόμενης εβδομάδας" and
"την επόμενη εβδομάδα Παρασκευή" are next week's. Weeks start on Monday, as the
app's weeks do: "την επόμενη εβδομάδα" plans the task seven days ahead, and the
weekend is Saturday and Sunday ("το Σαββατοκύριακο" is the coming Saturday, "το
Σαββατοκύριακο της επόμενης εβδομάδας" the one after). "Τρίτη", "Τετάρτη", and
"Πέμπτη" are also "third", "fourth", and "fifth", so they name a day with the
article ("την Τρίτη") or capitalized after another word ("Συνάντηση Τρίτη"),
while "την τρίτη φορά" and "Τρίτη θέση" stay in the title. "Παρασκευή" and
"Κυριακή" are also first names, so "με την Κυριακή" and "την Κυριακή
Παπαδοπούλου" stay. "Παρ." and "Κυρ." read only with their period, and "Δευ",
"Τρι", "Τετ", "Πεμ", and "Σαβ" with or without one. A list of days ("Δευτέρα και
Τρίτη", "Δευτέρα, Τετάρτη") names no single day and stays, and so do holidays
and ordinal weekdays ("Μεγάλη Παρασκευή", "Καθαρά Δευτέρα", "Κυριακή του
Πάσχα", "κάθε πρώτη Δευτέρα του μήνα").

No past day is read: "χθες", "προχθές", "την περασμένη Παρασκευή", and "το
περασμένο Σαββατοκύριακο" stay in the title, and so does a clock time right
after one ("χθες στις 3").

A written date has its day number before the month in the genitive ("15
Οκτωβρίου", "15 Οκτωβρίου 2026", "1η Μαΐου", "25ης Μαρτίου"), maybe with a
weekday in front ("Παρασκευή 16 Οκτωβρίου"), or is in digits with the day first
("15.10.2026", "15/10/2026", "15/10/26"). The colloquial month names ("Γενάρη",
"Φλεβάρη", "Μάρτη", "Μάη", "Οκτώβρη") read like the full ones, and the
abbreviations ("Ιαν", "Φεβ", "Μαρ", "Απρ", "Μαΐ", "Ιουν", "Ιουλ", "Αυγ", "Σεπ",
"Οκτ", "Νοε", "Δεκ") read after a day number. A month alone or in the nominative
("Μάιος") stays in the title. Digits with no year ("15.10", "15/10") are a date
only after "στις", "ημερομηνία", or a deadline word, since without one they
could be a time, a score, or a version. A date without a year that has already
passed means next year's, a year written after the month places the date ("15
Οκτωβρίου 2027"), and a year that is already past leaves the date in the title.

A date range plans the task on its first day and makes it due on its last: "3-5
Μαΐου", "3 Μαΐου - 5 Μαΐου", "από 3 έως 5 Μαΐου", and "από τις 3 μέχρι τις 5
Μαΐου" run from the first date to the last, and a month written once serves
both days. A span of weekdays does the same: "από Παρασκευή έως Κυριακή" and
"Παρασκευή-Κυριακή" plan the coming first day and make the task due on the last
day after it, while Monday to Friday ("Δευτέρα-Παρασκευή") is the working week,
which repeats. A range names both the planned day and the due day, so another
day in the same line stays in the title.

A due day is a day after "μέχρι" (also "μέχρι και"), "έως", "ως", "πριν" (or
"πριν από"), "προθεσμία", "παράδοση", or "deadline" ("μέχρι την Παρασκευή",
"έως Παρασκευή", "ως αύριο", "προθεσμία: Παρασκευή"), a day before "το
αργότερο" ("Παρασκευή το αργότερο"), or a day after "για" ("για αύριο", "για
την Παρασκευή").

"Κάθε" with a day, week, month, or year repeats the task ("κάθε μέρα", "κάθε
εβδομάδα", "κάθε μήνα", "κάθε χρόνο"), and so do "κάθε πρωί", "κάθε απόγευμα",
and "κάθε βράδυ" (each day). A weekday repeats every week ("κάθε Δευτέρα", "τις
Δευτέρες", "τα Σάββατα"), a list repeats on each of its days ("κάθε Δευτέρα και
Πέμπτη"), and "τις καθημερινές", "κάθε εργάσιμη μέρα", and "Δευτέρα-Παρασκευή"
repeat on the working days, while "τα Σαββατοκύριακα" and "κάθε Σαββατοκύριακο"
repeat on Saturday and Sunday. The counted intervals are "κάθε δύο μέρες", "κάθε
2 εβδομάδες", "μέρα παρά μέρα", "εβδομάδα παρά εβδομάδα", and "κάθε δεύτερη
Παρασκευή" (every other Friday), and "κάθε μήνα στις 15" or "κάθε 15 του μήνα"
repeats on a day of the month. "Ημερησίως", "εβδομαδιαίως", "μηνιαίως", and
"ετησίως" repeat the task anywhere in the line. "Καθημερινά", "εβδομαδιαία",
"μηνιαία", and "ετήσια" repeat the task only at the end of the line, at its
start before a colon or a comma, before "στις", or with "βάση" ("σε εβδομαδιαία
βάση"); before a noun they are adjectives and stay in the title ("εβδομαδιαία
αναφορά", "ετήσια άδεια").

A length says that it is one: "30 λεπτά", "30 λ", "2 ώρες", "1,5 ώρα", "μισή
ώρα", "μιάμιση ώρα", "δύο ώρες και μισή", "1 ώρα και 30 λεπτά", "δυόμισι
ώρες", "ένα τέταρτο", maybe after "για", "περίπου", or "διάρκεια:". "Ένα
τέταρτο" alone is a length only at the end of the line or before a word that can
follow a detail, so "ένα τέταρτο κιλό" stays. An amount that names a moment, a
bound, or a rate ("σε 30 λεπτά", "μετά από 2 ώρες", "τουλάχιστον 2 ώρες", "κάθε
2 ώρες", "2 ώρες πριν", "2 ώρες τη μέρα") is no length and stays in the title
whole, and so does a range of amounts ("2-3 ώρες").

"Υψηλή προτεραιότητα", "προτεραιότητα: υψηλή", and "προτεραιότητα 1" are high
priority, "μεσαία προτεραιότητα" ("προτεραιότητα 2") the middle one, and
"χαμηλή προτεραιότητα" ("προτεραιότητα 3") the low one. "Επείγον", "επείγουσα",
"σημαντικό", and "πολύ σημαντικό" are high priority only at the end of the line,
or at its start before a colon or a comma ("Επείγον: αναφορά"); anywhere else
they are ordinary adjectives and stay in the title ("Επείγον μήνυμα", "Σημαντική
συνάντηση"), and "όχι επείγον" and "δεν είναι σημαντικό" turn the word around,
so they stay too. A full stop or an exclamation mark that ends the line goes
with the word.

Thai words are read when Thai is among your device's preferred languages, in
any regional variant. Thai is written without spaces, so a detail may be glued
to the words around it or set apart from them: "ประชุมพรุ่งนี้" and "ประชุม
พรุ่งนี้" both plan "ประชุม" for tomorrow. A word counts only where it begins and
ends on a syllable of its own, so "สาม" inside "สามัคคี" is no hour. A detail
taken out from between two Thai words leaves one space there: "ส่งงานพรุ่งนี้ที่ห้องประชุม"
becomes the title "ส่งงาน ที่ห้องประชุม". Digits may be Arabic or Thai ("๑๕
ตุลาคม", "๓๐ นาที"). A year of 2400 or more is Buddhist Era, the Christian year
plus 543 ("2569" is 2026), and "พ.ศ." and "ค.ศ." name the era outright.

Thai says a clock time in two ways. The traditional clock uses "โมง" for the
hours of the day, "ทุ่ม" for the evening, and "ตี" for the small hours:
"บ่ายสามโมง" is 15:00, "สองทุ่ม" is 20:00, and "ตีห้า" is 05:00. The 24-hour
clock puts "น." or "นาฬิกา" after the time ("15:00 น.", "15.30 น.", "9 น.",
"9 นาฬิกา"), and with that unit the hour is read as written, so "3.30 น." is
03:30. A time with neither a Thai word nor a unit ("15:30", "3pm") is read by
the English rules instead, and "เวลา" or "ตอน" before a time goes with it
("เวลา 15:30").

An hour of "โมง" with no part of the day is in the afternoon from 1 to 6 ("3
โมง" is 15:00, "6 โมง" is 18:00) and in the morning from 7 to 11 ("8 โมง" is
08:00). A part of the day fixes it: "เช้า" goes with 6 to 11, "บ่าย" with 1 to 6
("บ่ายโมง" is 13:00), and "เย็น" with 3 to 11, and an hour that a part never goes
with ("สองโมงเช้า") stays in the title. A part of the day beside the day sets the
hour of a bare "โมง" too: "พรุ่งนี้เย็น 8 โมง" is 20:00 tomorrow and "คืนนี้ 8
โมง" is 20:00 tonight. "ครึ่ง" adds half an hour to the hour it follows
("บ่ายสามครึ่ง" and "3 โมงครึ่ง" are 15:30, "ทุ่มครึ่ง" is 19:30, "ตีสองครึ่ง" is
02:30). Minutes after the hour are written with "นาที" ("3 โมง 15 นาที" is
15:15), so a number of minutes right after "โมง" is part of the clock time:
"บ่ายสามโมง 30 นาที" is 15:30, and a half-hour task at three is "บ่ายสามโมง
ใช้เวลา 30 นาที".

"เที่ยง" is noon when it stands alone or follows a day word or "ตอน" ("นัดพรุ่งนี้เที่ยง"),
and it stays in the title inside another word ("ข้าวเที่ยง" is lunch).
"เที่ยงคืน" is the midnight that ends the day, so it plans the day after the one
named: "ดูบอลพรุ่งนี้เที่ยงคืน" is 00:00 on the day after tomorrow, and "ดูบอลเที่ยงคืน"
with no day plans tomorrow at 00:00. An hour of "ตี" after "คืนนี้" is the small
hours of the next day: "ดูบอลคืนนี้ตีหนึ่ง" is 01:00 tomorrow.

A clock time that names a bound ("ก่อน 5 โมงเย็น", "ภายใน 17:00 น.", "หลังเที่ยง",
"ตั้งแต่ 9 โมงเป็นต้นไป") stays in the title, while the day before it is the due
day: "ส่งงานพรุ่งนี้ก่อน 5 โมงเย็น" is due tomorrow and keeps "ก่อน 5 โมงเย็น".

English is read beside Thai, so "3pm", "17:30", and "30 min" work as they do
alone. Thai does not write a clock time with the letter h, so "15h" and "2h"
stay lengths, as in English alone.

| Detail | Thai |
|---|---|
| Day | วันนี้, คืนนี้, เย็นนี้, พรุ่งนี้, พรุ่งนี้เช้า, พรุ่งนี้ตอนเย็น, มะรืนนี้, วันศุกร์, วันศุกร์นี้, วันศุกร์หน้า, ศุกร์นี้, ศุกร์หน้า, วันศุกร์ที่จะถึง, วันศุกร์ตอนเย็น, สัปดาห์หน้า, สัปดาห์หน้าวันพุธ, วันพุธสัปดาห์หน้า, สุดสัปดาห์, สุดสัปดาห์หน้า, เสาร์อาทิตย์, อีก 3 วัน, อีก 2 สัปดาห์, อีกสัปดาห์ |
| Date | 15 ตุลาคม, 15 ต.ค., 15 ตุลาคมนี้, 15 ตุลาคม 2569, 15 ตุลาคม 2026, 15 ต.ค. พ.ศ. 2569, ๑๕ ตุลาคม ๒๕๖๙, วันศุกร์ที่ 16 ตุลาคม, 15/10/2569, 15-10-2026, 15.10.2569, วันที่ 15, วันที่ 15 ตุลาคม, วันที่ 15/10, วันอังคารที่ 29 |
| Date range | 3-5 พฤษภาคม, 3 ถึง 5 พฤษภาคม, ตั้งแต่ 3 ถึง 5 พฤษภาคม, จาก 3 ถึง 5 พฤษภาคม, 30 พฤษภาคม - 2 มิถุนายน, 3-5 พ.ค. 2570, ตั้งแต่วันศุกร์ถึงวันอาทิตย์, วันศุกร์-อาทิตย์ |
| Due day | ภายในวันศุกร์, ก่อนวันศุกร์, ไม่เกินวันศุกร์, จนถึงวันศุกร์, เดดไลน์วันศุกร์, deadline วันศุกร์, กำหนดส่ง 15/10, ครบกำหนดวันศุกร์, ภายในศุกร์, ภายในพรุ่งนี้, ภายในสัปดาห์หน้า, ภายใน 3 วัน, ภายใน 15 ตุลาคม |
| Time | บ่ายสามโมง, สามโมงเย็น, หกโมงเช้า, 3 โมง, 3 โมงครึ่ง, 3 โมง 15 นาที, สามโมงสิบห้านาที, บ่ายโมง, บ่ายสามครึ่ง, สองทุ่ม, ห้าทุ่ม, ทุ่มครึ่ง, ตีห้า, ตี 5, เที่ยง, เที่ยงคืน, 15:00 น., 15.30 น., 9 น., 9 นาฬิกา, 15 นาฬิกา 30 นาที, เวลา 15:30, ตอนบ่ายสามโมง, 10:00-11:00 น., 9-11 โมงเช้า, บ่ายสองถึงสี่โมง, 9 โมงถึง 11 โมง |
| Repeat | ทุกวัน, ทุกเช้า, ทุกเย็น, ทุกสัปดาห์, ทุกเดือน, ทุกปี, ทุกวันจันทร์, ทุกจันทร์, ทุกวันจันทร์และวันพุธ, ทุกจันทร์ พุธ ศุกร์, ทุกวันจันทร์ถึงวันศุกร์, ทุกวันทำงาน, ทุกสุดสัปดาห์, ทุกเสาร์อาทิตย์, ทุก 2 วัน, ทุกสองสัปดาห์, ทุก 3 เดือน, ทุก 2 สัปดาห์วันศุกร์, ทุก 14 วัน, วันเว้นวัน, สัปดาห์เว้นสัปดาห์, วันละครั้ง, สัปดาห์ละครั้ง, ทุกไตรมาส, ทุกครึ่งปี, ทุกวันที่ 15, ทุกเดือนวันที่ 15, วันที่ 15 ของทุกเดือน |
| Length | 30 นาที, 1 ชั่วโมง, 1 ชม., 1.5 ชั่วโมง, ครึ่งชั่วโมง, ชั่วโมงครึ่ง, 1 ชั่วโมงครึ่ง, 2 ชั่วโมง 30 นาที, สามสิบนาที, หนึ่งชั่วโมง, ชั่วโมงนึง, ใช้เวลา 2 ชั่วโมง, ระยะเวลา 30 นาที, นาน 45 นาที, ประมาณ 20 นาที |
| Priority | ด่วน, ด่วนมาก, ด่วนที่สุด, เร่งด่วน, สำคัญ, สำคัญมาก, สำคัญที่สุด, ไม่ด่วน, ไม่เร่งด่วน, ไม่สำคัญ, ความสำคัญสูง, ความสำคัญปานกลาง, ความสำคัญต่ำ, ลำดับความสำคัญ: สูง, ความสำคัญ 1, ความสำคัญ 2, ความสำคัญ 3 |

A weekday is written with "วัน": "วันศุกร์" is the coming Friday, a full week
ahead when it names today ("วันอังคาร" on a Tuesday is next Tuesday), and
"วันศุกร์นี้" counts today ("วันอังคารนี้" on a Tuesday is today).
"วันศุกร์หน้า", "สัปดาห์หน้าวันศุกร์", and "วันศุกร์สัปดาห์หน้า" are next
week's. Without "วัน" a weekday is read only before "นี้" or "หน้า" ("ศุกร์นี้",
"ศุกร์หน้า") or after a deadline word, because "จันทร์" (the moon), "ศุกร์"
(Venus), and "อังคาร" (Mars) are also names of things and "อาทิตย์" alone is the
word for a week, so a bare "ประชุมศุกร์" or "ประชุมอาทิตย์" stays in the title.
A weekday after "ดาว", "ดวง", "พระ", "คุณ", "นาย", or "นาง" is a name or a body
in the sky ("ดาวศุกร์", "คุณจันทร์โทรมา"), not a day. Weeks start on Monday, as
the app's weeks do: "สัปดาห์หน้า" plans the task seven days ahead, and the
weekend is Saturday and Sunday ("สุดสัปดาห์" is the coming Saturday and
"สุดสัปดาห์หน้า" the one after). A list of days ("วันจันทร์และวันพุธ") names no
single day and stays in the title.

No past day is read: "เมื่อวาน", "เมื่อคืน", "เมื่อเช้า", "วันศุกร์ที่แล้ว",
"สัปดาห์ที่แล้ว", and "3 วันก่อน" stay in the title, and so does a clock time
right after one ("เมื่อวานนี้ 3 โมง"). "ทุกวันนี้" (nowadays) and an ordinal
weekday of the month ("วันพุธที่สองของเดือน") stay whole.

A written date has its day number before the month, in full or abbreviated,
with a year of either era after it or "นี้" ("15 ตุลาคม", "15 ต.ค.", "15
ตุลาคม 2569", "15 ต.ค. พ.ศ. 2569", "15 ตุลาคมนี้"), maybe with a weekday in
front ("วันศุกร์ที่ 16 ตุลาคม"), or is in digits with the day first
("15/10/2569", "15-10-2026", "15.10.2569"). "วันที่ 15" with no month is the next
15th, and "วันอังคารที่ 29" is the next 29th that falls on a Tuesday. Digits with
no year ("15/10") are a date only after "วันที่" or a deadline word
("วันที่ 15/10"), since Thai addresses are written "99/9". A month alone
("ตุลาคม", "เดือนตุลาคม") stays in the title, and so does a day the month lacks
("31 กุมภาพันธ์"). A date without a year that has already passed means next
year's, and a year that is already past leaves the date in the title.

A date range plans the task on its first day and makes it due on its last: "3-5
พฤษภาคม", "3 ถึง 5 พฤษภาคม", "ตั้งแต่ 3 ถึง 5 พฤษภาคม", and "30 พฤษภาคม - 2
มิถุนายน" run from the first date to the last, and a month written once serves
both days. A span of weekdays does the same: "ตั้งแต่วันศุกร์ถึงวันอาทิตย์" and
"วันศุกร์-อาทิตย์" plan the coming first day and make the task due on the last
day after it. A range names both the planned day and the due day, so another day
in the same line stays in the title. With a space around the dash and a number
before it ("Sprint 12 - 20 พฤษภาคม") the number belongs to the title and only the
date is read. A day after "ถึง" or "ตั้งแต่" on its own ("ส่งงานถึงวันศุกร์") is
the end or the start of a stretch of time and stays in the title.

A due day is a day after "ภายใน", "ไม่เกิน", "ก่อน", "จนถึง", "เดดไลน์",
"deadline", "กำหนดส่ง", or "ครบกำหนด" ("ภายในวันศุกร์", "ก่อนพรุ่งนี้", "เดดไลน์:
วันศุกร์", "กำหนดส่ง 15/10", "ภายใน 3 วัน"). After one of these words a weekday
may be written without "วัน" ("ภายในศุกร์") and the short date "15/10" is a date.

"ทุก" with a day, week, month, or year repeats the task ("ทุกวัน", "ทุกสัปดาห์",
"ทุกเดือน", "ทุกปี"), and so do "ทุกเช้า", "ทุกบ่าย", "ทุกเย็น", and "ทุกคืน"
(each day). A weekday repeats every week ("ทุกวันจันทร์", "ทุกจันทร์"), a list
repeats on each of its days ("ทุกวันจันทร์และวันพุธ", "ทุกจันทร์ พุธ ศุกร์"),
"ทุกวันทำงาน" and "ทุกวันจันทร์ถึงวันศุกร์" repeat on the working days, and
"ทุกสุดสัปดาห์" and "ทุกเสาร์อาทิตย์" on Saturday and Sunday. The counted
intervals are "ทุก 2 วัน", "ทุกสองสัปดาห์", "ทุก 3 เดือน", "ทุก 2 สัปดาห์วันศุกร์",
the alternating "วันเว้นวัน" and "สัปดาห์เว้นสัปดาห์", "ทุกไตรมาส" (every three
months), and "ทุกครึ่งปี" (every six months); whole weeks counted in days ("ทุก
14 วัน") are a weekly repeat. "วันละครั้ง", "สัปดาห์ละครั้ง", "เดือนละครั้ง",
and "ปีละครั้ง" repeat the same way, and "ทุกวันที่ 15", "ทุกเดือนวันที่ 15",
and "วันที่ 15 ของทุกเดือน" repeat on a day of the month. "ทุกวันหยุด" (every
holiday), "ทุกวันเกิด" (every birthday), "ทุกวันนี้", "สัปดาห์ละ 2 ครั้ง", and
the weekdays of a month ("ทุกวันพุธที่สองของเดือน", "ทุกวันศุกร์สุดท้ายของเดือน")
name no repeat the app can set and stay in the title, and so do "ประจำสัปดาห์",
"ประจำเดือน", and "ประจำปี" before a noun ("รายงานประจำเดือน").

A length says that it is one: "30 นาที", "1 ชั่วโมง", "1 ชม.", "1.5 ชั่วโมง",
"ครึ่งชั่วโมง", "ชั่วโมงครึ่ง", "2 ชั่วโมง 30 นาที", "สามสิบนาที", maybe after
"ใช้เวลา", "ระยะเวลา", "นาน", or "ประมาณ". An amount that names a moment, a
bound, the past, or a rate ("อีก 30 นาที", "ภายใน 2 ชั่วโมง", "ทุก 30 นาที",
"30 นาทีที่แล้ว", "วันละ 2 ชั่วโมง", "2 ชั่วโมงต่อวัน") is no length and stays in
the title whole, and so do a range of amounts ("2-3 ชั่วโมง"), a single spelled
minute, and more than twenty-four hours. A time range ("10:00-11:00 น.",
"บ่ายสองถึงสี่โมง") sets the start and the length together.

"ด่วน" and "สำคัญ" are priority words only when they stand alone, with a space,
punctuation, or the end of the line on both sides, so "ทางด่วน" (an expressway),
"รถด่วน" (an express train), and "เอกสารสำคัญ" (an important document) stay in the
title. The longer words "ด่วนมาก", "ด่วนที่สุด", "เร่งด่วน", "สำคัญมาก", and
"สำคัญที่สุด" also work glued to the words around them ("ส่งรายงานด่วนมาก"),
and the repetition mark "ๆ" after a priority word belongs to it ("ด่วนมากๆ").
"ไม่ด่วน", "ไม่เร่งด่วน", and "ไม่สำคัญ" are low priority. "ความสำคัญสูง"
("ลำดับความสำคัญ: สูง", "ความสำคัญ 1") is high, "ความสำคัญปานกลาง"
("ความสำคัญ 2") the middle one, and "ความสำคัญต่ำ" ("ความสำคัญ 3") the low one.
A word that goes on into a comparison ("สำคัญมากกว่า", "ไม่สำคัญเท่า") names no
priority, and a polite particle after the word ("ครับ") stays in the title.

Marathi words are read when Marathi is among your device's preferred languages,
in any regional variant. A word counts only as a whole word in Devanagari, so
"आजकाल" (nowadays) and "उद्यान" (a garden) hold no day, and a hyphen between two
Devanagari words joins them. Marathi glues its endings to the word, and Lorvex
reads the endings that go with a detail: "उद्याला", "सोमवारी", "शुक्रवारपर्यंत",
"5 मेपासून", "30 मिनिटांची मीटिंग". A word with any other ending stays in the
title ("उद्यादेखील"), and so does a day that a genitive follows, since the day
then describes a noun ("सोमवारची मीटिंग", "उद्याची मीटिंग"). The Devanagari
digits ("५") read as the digits they stand for, the candrabindu and the
anusvara are one sign ("पाँच" and "पांच"), "ऑगस्ट" and "आगस्ट" are one word, and
a nasal conjunct may be spelled either way ("सप्टेंबर" and "सप्टेम्बर"); a
nukta typed after its consonant is accepted, and the title keeps what you
typed. Marathi written in Latin letters ("udya sakali") is not read. English is
read beside Marathi, so "3pm", "17:30", and "30 min" work as they do alone, and
Marathi does not write a clock time with the letter h, so "2h" stays a length.
If Hindi is among your preferred languages too, Marathi leaves the words the
two languages share ("आज", "सोमवार", "मार्च") to Hindi when a Hindi word that
goes with them follows ("आज की रात", "सोमवार को"), so each language reads as it
does alone.

"परवा" means both the day after tomorrow and the day before yesterday. Lorvex
reads it as the day after tomorrow, and it never reads "काल" (yesterday) or any
other past day. A day stays in the title when its line says that it is past: a
past-tense word anywhere in the line ("उद्या मीटिंग होती", "परवा गेलो होतो",
"आज बैठक झाली"), or "गेल्या", "मागील", "मागच्या", or an ordinal just before it
("गेल्या शुक्रवारी", "पहिल्या शुक्रवारी"). A past statement without such a
word ("परवा मी फोन केला") is read as the day after tomorrow.

Marathi says a clock time with "वाजता" after the hour: "5 वाजता", "5:30
वाजता", "साडेपाच वाजता" (5:30), "सव्वापाच वाजता" (5:15), "पावणेसहा वाजता"
(5:45), "दीड वाजता" (1:30), and "अडीच वाजता" (2:30). The hour may be a number
word before "वाजता" ("पाच वाजता"), while a number word anywhere else is a count
("तीन लोक"). An hour from 1 to 6 with no part of the day is in the afternoon
("5 वाजता" is 5 PM) unless it is written with a zero ("06:30 वाजता"), and a
part of the day sets the hour: "सकाळी" and "पहाटे" are the morning, "दुपारी" is
noon at 12 and the afternoon from 1 to 6, "संध्याकाळी" is the evening, and
"रात्री" runs past midnight, so "रात्री 2 वाजता" is 02:00 on the next day and
"रात्री 10 वाजता" is 22:00. "मध्यरात्री" is the midnight that ends the day. The
part of the day stands before the hour ("सकाळी 9 वाजता", "संध्याकाळच्या 6
वाजता", "सकाळी लवकर 6 वाजता"); one after "वाजता" stays in the title and still
sets the hour. An hour with no part of the day of its own takes the one part of
the day the line names elsewhere: in its day phrase ("उद्या सकाळी मीटिंग 6
वाजता" is 06:00), after "रोज", "दर", or "प्रत्येक" ("रोज सकाळी 6 वाजता योग"), or
in a noun ("रात्रीचे जेवण 8 वाजता" is 20:00, "सकाळची सैर 6 वाजता" is 06:00). A
line that names two different parts of the day leaves the hour as it reads
alone, and an hour written on the 24-hour clock ("20:00 वाजता", "06:30
वाजता") is read as written. The ending "ला" also makes a time: "साडेतीनला"
(3:30), "दीडला", and, after a part of the day, "संध्याकाळी सहाला", "सकाळी 7 ला".
A clock time that names a bound ("5 वाजेपर्यंत", "संध्याकाळी 5 वाजेपूर्वी", "18:00
पर्यंत", "5 वाजल्यानंतर") stays in the title.

| Detail | Marathi |
|---|---|
| Day | आज, आज रात्री, उद्या, उद्या सकाळी, परवा, सोमवारी, या शुक्रवारी, पुढच्या सोमवारी, पुढच्या आठवड्यात, या वीकेंडला, 3 दिवसांनी, एका आठवड्याने |
| Date | 5 मे, 5 मे 2027, तारीख 5 मे, 15 ऑक्टो., 15 तारखेला, 15/10/2026, 15.10., सोमवार 5 ऑक्टोबर |
| Date range | 3 ते 5 मार्च, 3 मार्च ते 5 मार्च, 3 मार्चपासून 5 मार्चपर्यंत, 30 जानेवारी ते 2 फेब्रुवारी, 3-5 मार्च, सोमवार ते बुधवार |
| Due day | शुक्रवारपर्यंत, उद्या संध्याकाळपर्यंत, 5 मेपर्यंत, अंतिम तारीख: 5 मे, डेडलाइन शुक्रवार, शुक्रवारी देय |
| Time | 5 वाजता, 5:30 वाजता, साडेपाच वाजता, पावणेसहा वाजता, दीड वाजता, पाच वाजता, सकाळी 9 वाजता, संध्याकाळी 5 वाजता, रात्रीच्या 10 वाजता, संध्याकाळी 5:30, मध्यरात्री; 3 ते 5 वाजता, सकाळी 9 ते 11 वाजता, 3 वाजेपासून 5 वाजेपर्यंत, 14:00 ते 16:00 |
| Repeat | रोज, दररोज, रोज सकाळी, दर सोमवारी, दर सोमवारी आणि गुरुवारी, दर दुसऱ्या सोमवारी, दर आठवड्याला, दर 2 दिवसांनी, दर महिन्याला, दर महिन्याच्या 5 तारखेला, दरवर्षी, दर वीकेंडला, कामाच्या दिवशी, दर सोमवार ते शुक्रवार, दिवसाआड |
| Length | 30 मिनिटे, 2 तास, 1.5 तास, 1 तास 30 मिनिटे, अर्धा तास, पाऊण तास, दीड तास, साडेतीन तास, दोन तास, 30 मिनिटांसाठी |
| Priority | उच्च प्राधान्य, मध्यम प्राधान्य, निम्न प्राधान्य, प्राधान्य: उच्च, तातडीचे (at the end, or "तातडीचे:" at the start) |

A weekday is a day only with its full name in "वार" (सोमवार, मंगळवार, बुधवार,
गुरुवार, शुक्रवार, शनिवार, रविवार): the short forms "रवि", "सोम", "मंगळ",
"बुध", "गुरु", "शुक्र", and "शनि" are ordinary words and names ("मंगळ ग्रह
पाहणे") and stay in the title. A weekday alone is the coming one, a week ahead
when it names today; "या" and "ह्या" make it this week's, "पुढच्या" and
"पुढील" next week's (weeks start on Monday), and "येत्या" the coming one. "या
आठवड्यात" alone names no single day. The weekend is Saturday and Sunday:
"वीकेंड", "आठवडा अखेर", "आठवड्याच्या शेवटी", and "शनिवार-रविवार" mean the
coming Saturday, and today on a Saturday or a Sunday.

A date range plans the task on its first day and makes it due on its last: "3
ते 5 मार्च", "3 मार्च ते 5 मार्च", and "3 मार्चपासून 5 मार्चपर्यंत" run from
March 3 to March 5, and a month written once serves both days. The end must come
after the start ("5 ते 3 मार्च" stays in the title), and the end names a month,
so "3 ते 5" is never a range of days. A span of weekdays does the same: "सोमवार
ते बुधवार" plans the task on the coming Monday and makes it due on the Wednesday
after it, while "सोमवार ते शुक्रवार" alone stays in the title, since it is a
week of work as often as it is the working week. As in English, a number alone
before a spaced dash belongs to the title ("Sprint 12 - 20 मार्च" is planned for
March 20), while "12-20 मार्च" is a range. A range in the past tense, or one
that a genitive follows ("5 ते 8 मेची सुट्टी"), stays in the title whole, since
it may be an event the task only prepares for. "3 ते 5 वाजता" is a time range:
its end carries "वाजता", so "3 ते 5" alone stays in the title.

A date needs its day number before the month name (जानेवारी, फेब्रुवारी,
मार्च, एप्रिल, मे, जून, जुलै, ऑगस्ट, सप्टेंबर, ऑक्टोबर, नोव्हेंबर, डिसेंबर, in the
spellings people type, and the short forms the system writes, such as
"ऑक्टो."). A month without a day, a month before its day, a date in digits with
no label and no ending ("5/10"), a date the calendar lacks ("31 एप्रिल"), and a
month of the Marathi calendar ("चैत्र", "श्रावण") stay in the title. A date in
digits with the day first ("15/10/2026", "15.10.2026", "15.10.") is a date, and
"15/10" is a date only after "तारीख" or "दिनांक" or before "ला". A date without
a year that has already passed means next year's.

A due day is a day before "पर्यंत", "पूर्वी", "आधी", or "अगोदर", or after a
deadline label ("अंतिम तारीख", "शेवटचा दिनांक", "देय तारीख", "डेडलाइन"), or before
"देय" ("शुक्रवारपर्यंत", "अंतिम तारीख: 5 मे", "शुक्रवारी देय"). "आजपर्यंत" means
"so far" and is not read, and a clock time before a deadline word ("शुक्रवारी
संध्याकाळी 5 वाजेपर्यंत") makes the day the due day while the time stays in the
title.

A repeat is "दर" or "प्रत्येक" with a unit ("दर आठवड्याला", "दर महिन्याला",
"दरवर्षी"), "रोज", "दररोज", or "नित्य" (every day), a weekday ("दर सोमवारी", "दर
सोमवारी आणि गुरुवारी", "दर दुसऱ्या सोमवारी"), the working days ("कामाच्या
दिवशी", "दर सोमवार ते शुक्रवार"), the weekend ("दर वीकेंडला"), a counted
interval ("दर 2 दिवसांनी", "दर तीन महिन्यांनी"), "दिवसाआड" and its forms for
the other units, "आठवड्यातून एकदा" and its forms, or a day of the month ("दर
महिन्याच्या 5 तारखेला"). An interval shorter than a day ("दर 2 तासांनी") and a
cadence word that describes a noun ("रोजचे काम", "दर महिन्याचा खर्च") name no
repeat and stay in the title, and "रोजगार" and "रोजा" are other words. "दर" also
means a price rate, so "मजुरी दर दिवस 500 रुपये" is read as a daily repeat.

A length says that it is one: "30 मिनिटे", "2 तास", "1.5 तास", "अर्धा तास",
"दीड तास", "साडेतीन तास", maybe with a genitive or "साठी" glued to the unit
("30 मिनिटांची मीटिंग" is a 30-minute meeting). An amount that names a moment,
an interval, or a bound ("2 तास आधी", "दर 2 तास", "2 तासांच्या आत", "दिवसातून
2 तास", "किमान 2 तास") is no length and stays in the title whole, and so does a
range of amounts ("2 ते 3 तास").

A priority is "उच्च प्राधान्य", "मध्यम प्राधान्य", or "निम्न प्राधान्य" (also
with "प्राथमिकता"), or an urgent word at the end of the line ("तातडीचे",
"अत्यावश्यक", "अर्जंट", "महत्त्वाचे") or at its start before a colon or a comma
("तातडीचे: रिपोर्ट पाठवा"). Anywhere else these are ordinary adjectives and stay
in the title ("तातडीची औषधे आणणे", "रिपोर्ट पाठवा तातडीचे आहे").

Bengali words are read when Bengali is among your device's preferred languages,
in any regional variant. A word counts only as a whole word in the Bengali
script, so "আজকাল" (nowadays) and "কালো" (black) hold no day, and a hyphen
between two Bengali words joins them ("আজ-কাল"). Bengali glues its endings to
the word, and Lorvex reads the endings that go with a detail: "সোমবারে",
"কালকে", "15 অক্টোবরে", "5টায়", "30 মিনিটের মিটিং". A word with any other
ending stays in the title, and so does a day that a genitive follows, since the
day then describes a noun ("সোমবারের মিটিং", "আজকের কাজ"). The Bengali digits
("৫") read as the digits they stand for, the letters য়, ড়, and ঢ় read the same
typed as one character, as a letter and a nukta, or without the nukta, a joiner
typed before an ending changes nothing, and the title keeps what you typed.
Bengali written in Latin letters ("kal sokale") is not read. English is read
beside Bengali, so "3pm", "17:30", and "30 min" work as they do alone, and
Bengali does not write a clock time with the letter h, so "2h" stays a length.

"কাল" and "পরশু" look both ways: "কাল" means tomorrow and yesterday, and "পরশু"
the day after tomorrow and the day before yesterday. Lorvex reads them as the
coming day, and it never reads "গতকাল" (yesterday) or any other past day. A day
stays in the title when its line says that it is past: a past-tense word
anywhere in the line ("কাল মিটিং ছিল", "পরশু গিয়েছিলাম", "আজ বৈঠক হয়েছিল"), or
"গত", "গেল", "আগের", "বিগত", or an ordinal just before it ("গত শুক্রবার",
"প্রথম শুক্রবার"). A past statement without such a word ("পরশু আমি ফোন
দিলাম") is read as the day after tomorrow.

Bengali says a clock time with "টা" after the hour and an ending: "5টায়",
"5:30টায়", "সাড়ে 5টায়" (5:30), "সোয়া 5টায়" (5:15), "পৌনে 6টায়" (5:45),
"দেড়টায়" (1:30), and "আড়াইটায়" (2:30). The hour may be a number word
("পাঁচটায়"), while a number word anywhere else is a count ("তিন জন"). The hour
with "টা" and no ending counts things, as in "5টা বই", so it is a time only
after a part of the day ("সকাল 9টা"), as a fraction, or as a range. An hour from
1 to 6 with no part of the day is in the afternoon ("5টায়" is 5 PM) unless it
is written with a zero ("06:30টায়"), and a part of the day sets the hour:
"সকাল" and "ভোর" are the morning, "দুপুর" is noon at 12 and the afternoon from
1 to 6, "বিকেল" and "সন্ধ্যা" are the evening, and "রাত" runs past midnight, so
"রাত 2টায়" is 02:00 on the next day and "রাত 10টায়" is 22:00. "মধ্যরাতে" is the
midnight that ends the day. The part of the day stands before the hour ("সকাল
9টা", "বিকেল 5টায়"); one after the hour stays in the title and still sets the
hour. An hour with no part of the day of its own takes the one part the line
names elsewhere: in its day phrase ("আগামীকাল সকালে মিটিং 6টায়" is 06:00),
after "রোজ" or "প্রতি" ("রোজ সকালে 6টায় যোগব্যায়াম"), or in a noun ("রাতের
খাবার 8টায়" is 20:00, "সকালের হাঁটা 6টায়" is 06:00). A line that names two
different parts of the day leaves the hour as it reads alone, and an hour
written on the 24-hour clock ("20:00টায়", "06:30টায়") is read as written. The
minutes may follow the hour: "সকাল 10টা 30 মিনিটে" is 10:30. A clock time that
names a bound ("5টার মধ্যে", "সন্ধ্যা 6টার আগে", "18:00 পর্যন্ত") stays in the
title.

| Detail | Bengali |
|---|---|
| Day | আজ, আজ রাতে, আগামীকাল, আগামীকাল সকালে, পরশু, সোমবার, এই শুক্রবার, পরের সোমবার, পরের সপ্তাহে, এই উইকেন্ডে, 3 দিন পর, 1 সপ্তাহ পর |
| Date | 5 মে, 5 মে 2027, তারিখ 5 মে, 15 অক্টো, 15 তারিখে, 15/10/2026, 15.10., সোমবার 5 অক্টোবর |
| Date range | 3 থেকে 5 মার্চ, 3 মার্চ থেকে 5 মার্চ, 3 মার্চ থেকে 5 মার্চ পর্যন্ত, 30 জানুয়ারি থেকে 2 ফেব্রুয়ারি, 3-5 মার্চ, সোমবার থেকে বুধবার |
| Due day | শুক্রবার পর্যন্ত, কাল সন্ধ্যা পর্যন্ত, 5 মে পর্যন্ত, শুক্রবারের মধ্যে, শেষ তারিখ: 5 মে, ডেডলাইন শুক্রবার |
| Time | 5টায়, 5:30টায়, সাড়ে 5টায়, সোয়া 5টায়, পৌনে 6টায়, দেড়টায়, পাঁচটায়, সকাল 9টা, বিকেল 5টায়, রাত 10টায়, সকাল 9:30, মধ্যরাতে; 3টা থেকে 5টা, সকাল 9টা থেকে 11টা, 14:00 থেকে 16:00 |
| Repeat | প্রতিদিন, রোজ, রোজ সকালে, প্রতি সোমবার, প্রতি সোমবার ও বৃহস্পতিবার, প্রতি দ্বিতীয় সোমবারে, প্রতি সপ্তাহে, প্রতি 2 দিনে, প্রতি মাসে, প্রতি মাসের 5 তারিখে, প্রতি বছর, প্রতি উইকেন্ডে, কর্মদিবসে, প্রতি সোমবার থেকে শুক্রবার, 2 দিন অন্তর, সপ্তাহে একবার |
| Length | 30 মিনিট, 2 ঘণ্টা, 1.5 ঘণ্টা, 1 ঘণ্টা 30 মিনিট, আধ ঘণ্টা, পৌনে এক ঘণ্টা, দেড় ঘণ্টা, সাড়ে তিন ঘণ্টা, দুই ঘণ্টা, 30 মিনিটের জন্য |
| Priority | উচ্চ প্রাধান্য, মধ্যম প্রাধান্য, নিম্ন প্রাধান্য, প্রাধান্য: উচ্চ, জরুরি (at the end, or "জরুরি:" at the start) |

A weekday is a day only with its full name in "বার" (রবিবার, সোমবার, মঙ্গলবার,
বুধবার, বৃহস্পতিবার, শুক্রবার, শনিবার): the short forms "রবি", "সোম", "মঙ্গল",
"বুধ", "বৃহস্পতি", "শুক্র", and "শনি" are ordinary words and names ("মঙ্গল গ্রহ
দেখা") and stay in the title. A weekday alone is the coming one, a week ahead
when it names today; "এই" makes it this week's, "পরের" next week's (weeks start
on Monday), and "আগামী", "আসছে", "সামনের", and "আসন্ন" the coming one. "এই
সপ্তাহে" alone names no single day. The weekend is Saturday and Sunday:
"উইকেন্ড", "সপ্তাহান্ত", "সপ্তাহের শেষে", and "শনিবার ও রবিবার" mean the coming
Saturday, and today on a Saturday or a Sunday.

A date range plans the task on its first day and makes it due on its last: "3
থেকে 5 মার্চ", "3 মার্চ থেকে 5 মার্চ", and "3-5 মার্চ" run from March 3 to March
5, with "হতে" for "থেকে" and "পর্যন্ত" after the end if you like, and a month
written once serves both days. The end must come after the start ("5 থেকে 3
মার্চ" stays in the title), and the end names a month, so "3 থেকে 5" is never a
range of days. A span of weekdays does the same: "সোমবার থেকে বুধবার" plans the
task on the coming Monday and makes it due on the Wednesday after it, while
"সোমবার থেকে শুক্রবার" alone stays in the title, since it is a week of work as
often as it is the working week. As in English, a number alone before a spaced
dash belongs to the title ("Sprint 12 - 20 মার্চ" is planned for March 20),
while "12-20 মার্চ" is a range. A range in the past tense, or one that a genitive
follows ("3 থেকে 5 মার্চের ছুটি"), stays in the title whole, since it may be an
event the task only prepares for. "3টা থেকে 5টা" is a time range: its end
carries "টা", so "3 থেকে 5" alone stays in the title.

A date needs its day number beside the month name (জানুয়ারি, ফেব্রুয়ারি, মার্চ,
এপ্রিল, মে, জুন, জুলাই, আগস্ট, সেপ্টেম্বর, অক্টোবর, নভেম্বর, ডিসেম্বর, in the
spellings people type, and the short forms the system writes next to a day,
such as "অক্টো"); "5ই মে" and "1লা মে" read too. A month without a day, a
short month before its day, a date in digits with no label and no ending
("5/10"), a date the calendar lacks ("31 এপ্রিল"), and a month of the Bengali
calendar ("বৈশাখ", "আষাঢ়") stay in the title. A date in digits with the day
first ("15/10/2026", "15.10.2026", "15.10.") is a date, and "15/10" is a date
only after "তারিখ" or before "এ". A date without a year that has already passed
means next year's.

A due day is a day before "পর্যন্ত" or "অবধি", a day with a genitive before
"মধ্যে", "আগে", or "পূর্বে", or a day after a deadline label ("শেষ তারিখ",
"অন্তিম তারিখ", "ডেডলাইন", "সময়সীমা"): "শুক্রবার পর্যন্ত", "শুক্রবারের
মধ্যে", "শেষ তারিখ: 5 মে". "আজ পর্যন্ত" means "so far" and is not read, and a
clock time before a deadline word ("শুক্রবার সন্ধ্যা 5টার মধ্যে") makes the day
the due day while the time stays in the title. "নির্ধারিত" names a planned day
as much as a due one, so it is not a deadline word.

A repeat is "প্রতি" or "প্রত্যেক" with a unit ("প্রতি সপ্তাহে", "প্রতি মাসে",
"প্রতি বছর"), "প্রতিদিন", "রোজ", or "প্রত্যহ" (every day), a weekday ("প্রতি
সোমবার", "প্রতি সোমবার ও বৃহস্পতিবার", "প্রতি দ্বিতীয় সোমবারে"), the working
days ("কর্মদিবসে", "প্রতি সোমবার থেকে শুক্রবার"), the weekend ("প্রতি
উইকেন্ডে"), a counted interval ("প্রতি 2 দিনে", "প্রতি তিন মাসে", "2 দিন
অন্তর", "3 মাস পর পর"), "একদিন অন্তর" and its forms for the other units,
"সপ্তাহে একবার" and its forms, or a day of the month ("প্রতি মাসের 5 তারিখে").
"দৈনিক", "সাপ্তাহিক", "মাসিক", and "বার্ষিক" are read only at the end of the
line, before a colon or a comma, or with "ভিত্তিতে" or "হিসেবে" after them,
since they are ordinary adjectives too ("দৈনিক রিপোর্ট" is a daily report). An
interval shorter than a day ("প্রতি 2 ঘণ্টায়") and a cadence word that
describes a noun ("প্রতিদিনের কাজ", "প্রতি মাসের খরচ") name no repeat and stay
in the title, and "রোজা" and "রোজকার" are other words. "প্রতি" also means a
price rate, so "মজুরি প্রতি দিন 500 টাকা" is read as a daily repeat.

A length says that it is one: "30 মিনিট", "2 ঘণ্টা", "1.5 ঘণ্টা", "আধ ঘণ্টা",
"দেড় ঘণ্টা", "সাড়ে তিন ঘণ্টা", maybe with a genitive or "জন্য" after the unit
("30 মিনিটের মিটিং" is a 30-minute meeting). An amount that names a moment, an
interval, or a bound ("2 ঘণ্টা পর", "প্রতি 2 ঘণ্টা", "2 ঘণ্টার মধ্যে", "দিনে 2
ঘণ্টা", "অন্তত 2 ঘণ্টা") is no length and stays in the title whole, and so does
a range of amounts ("2 থেকে 3 ঘণ্টা").

A priority is "উচ্চ প্রাধান্য", "মধ্যম প্রাধান্য", or "নিম্ন প্রাধান্য" (also with
"অগ্রাধিকার"), or an urgent word at the end of the line ("জরুরি", "অতি জরুরি",
"আর্জেন্ট", "গুরুত্বপূর্ণ") or at its start before a colon or a comma ("জরুরি:
রিপোর্ট পাঠান"). Anywhere else these are ordinary adjectives and stay in the
title ("জরুরি বিভাগে যান", "রিপোর্ট জরুরি আছে").

Telugu words are read when Telugu is among your device's preferred languages, in
any regional variant. A word counts only as a whole word in the Telugu script,
so "ఈరోజుల్లో" (nowadays) holds no day, and a hyphen between two Telugu words
joins them ("రేపు-ఎల్లుండి"). Telugu glues its endings to the word, and Lorvex
reads the endings that go with a detail: "సోమవారానికి", "రేపే", "15న", "సాయంత్రం
5కి", "30 నిమిషాల మీటింగ్". A word with any other ending stays in the title, and
so does a day in its genitive form or followed by "నాటి", since the day then
describes a noun ("రేపటి మీటింగ్", "సోమవారపు మీటింగ్", "శుక్రవారం నాటి
మీటింగ్"). "రేపటి నుండి" and "రేపటి లోపు" are still read. The Telugu digits
("౫") read as the digits they stand for, the vowel sign ై reads the same typed
as one sign or as the two signs it is made of, a joiner typed before an ending
changes nothing, and the title keeps what you typed. Telugu written in Latin
letters ("repu udayam") is not read. English is read beside Telugu, so "3pm",
"17:30", and "30 min" work as they do alone, and Telugu does not write a clock
time with the letter h, so "2h" stays a length.

Telugu has one word each for yesterday ("నిన్న"), the day before ("మొన్న"),
tomorrow ("రేపు"), and the day after ("ఎల్లుండి"), so Lorvex never reads a past
day. A day stays in the title when its line says that it is past: a past-tense
word anywhere in the line ("రేపు మీటింగ్ జరిగింది", "శుక్రవారం రిపోర్ట్ పంపాను",
"శుక్రవారం గడువు ముగిసింది"), or "గత", "పోయిన", "మునుపటి", "ఆ", "ఆఖరి", "చివరి",
or an ordinal just before it ("గత శుక్రవారం", "మొదటి శుక్రవారం"). Only the
past-tense forms of the common verbs that Lorvex lists are recognised, so a past
statement that uses another verb is still read as a plan.

Telugu says a clock time with "గంటలకు" after the hour: "5 గంటలకు", "5:30
గంటలకు", "ఒంటి గంటకు" (one o'clock), and the half hours "ఐదున్నరకు" (5:30) and
"ఒంటి గంటన్నరకు" (1:30). The hour may be a number word ("ఐదు గంటలకు"), while a
number word anywhere else is only a count ("మూడు పుస్తకాలు"). "5 గంటలు" without
the ending is an amount of hours, which Lorvex reads as a length, and "ఐదున్నర"
without an ending is a time only after a part of the day. An hour from 1 to 6
with no part of the day is in the afternoon ("5 గంటలకు" is 5 PM) unless it is
written with a zero ("06:30 గంటలకు"), and a part of the day sets the hour:
"ఉదయం" is the morning, "మధ్యాహ్నం" is noon at 12 and the afternoon from 1 to 6,
"సాయంత్రం" is the evening, and "రాత్రి" runs past midnight, so "రాత్రి 2 గంటలకు"
is 02:00 on the next day and "రాత్రి 10 గంటలకు" is 22:00. "అర్ధరాత్రి" is the
midnight that ends the day. The part of the day stands before the hour ("ఉదయం 9
గంటలకు", "సాయంత్రం 5కి"); one after the hour stays in the title and still sets
the hour ("మీటింగ్ 7 గంటలకు సాయంత్రం" is 19:00). An hour with no part of the day
of its own takes the one part the line names elsewhere: in its day phrase ("రేపు
ఉదయం మీటింగ్ 6 గంటలకు" is 06:00), after "ప్రతి" or "రోజూ" ("రోజూ ఉదయం 6 గంటలకు
యోగా"), or in a noun ("రాత్రి భోజనం 8 గంటలకు" is 20:00). A line that names two
different parts of the day leaves the hour as it reads alone, and an hour
written on the 24-hour clock ("20:00 గంటలకు", "06:30 గంటలకు") is read as
written. The minutes may follow the hour: "ఉదయం 10 గంటల 30 నిమిషాలకు" is 10:30.
A clock time that names a bound ("5 గంటలలోగా", "సాయంత్రం 6 గంటల లోపు", "5 గంటలకు
ముందు", "18:00 వరకు") stays in the title.

| Detail | Telugu |
|---|---|
| Day | ఈరోజు, ఈ రాత్రి, రేపు, రేపు ఉదయం, ఎల్లుండి, సోమవారం, ఈ శుక్రవారం, తదుపరి సోమవారం, వచ్చే వారం, ఈ వారాంతం, 3 రోజుల్లో, 1 వారం తర్వాత |
| Date | 5 మే, 5 మే 2027, తేదీ 5 మే, 15 అక్టో, 15వ తేదీన, 15/10/2026, 15.10., సోమవారం 5 అక్టోబర్ |
| Date range | 3 నుండి 5 మార్చి, 3 మార్చి నుండి 5 మార్చి వరకు, 30 జనవరి నుండి 2 ఫిబ్రవరి, 3-5 మార్చి, సోమవారం నుండి బుధవారం వరకు |
| Due day | శుక్రవారం వరకు, రేపు సాయంత్రం వరకు, 5 మే లోగా, శుక్రవారం లోపు, శుక్రవారానికల్లా, గడువు: 5 మే, శుక్రవారం గడువు, డెడ్‌లైన్ శుక్రవారం |
| Time | 5 గంటలకు, 5:30 గంటలకు, ఐదున్నరకు, ఒంటి గంటకు, సాయంత్రం 5 గంటలకు, రాత్రి 10 గంటలకు, ఉదయం 9:30, సాయంత్రం 5కి, 17:30కి, అర్ధరాత్రి; 9 గంటల నుండి 11 గంటల వరకు, ఉదయం 9 నుండి 11 వరకు, 14:00 నుండి 16:00 వరకు |
| Repeat | ప్రతిరోజు, రోజూ, ప్రతి ఉదయం, ప్రతి సోమవారం, ప్రతి సోమవారం మరియు గురువారం, ప్రతి వారం, ప్రతి 2 రోజులకు, ప్రతి నెల, ప్రతి నెల 5వ తేదీన, ప్రతి సంవత్సరం, ప్రతి వారాంతం, పనిదినాల్లో, ప్రతి సోమవారం నుండి శుక్రవారం, 2 రోజులకోసారి, వారానికి ఒకసారి |
| Length | 30 నిమిషాలు, 2 గంటలు, 1.5 గంటలు, 1 గంట 30 నిమిషాలు, అరగంట, పావు గంట, గంటన్నర, రెండున్నర గంటలు, రెండు గంటలు, 30 నిమిషాల పాటు |
| Priority | అధిక ప్రాధాన్యత, సాధారణ ప్రాధాన్యత, తక్కువ ప్రాధాన్యత, ప్రాధాన్యత: అధికం, అత్యవసరం (at the end, or "అత్యవసరం:" at the start) |

A weekday is a day only with its full name in "వారం" (ఆదివారం, సోమవారం,
మంగళవారం, బుధవారం, గురువారం, శుక్రవారం, శనివారం): the short forms "ఆది", "సోమ",
"మంగళ", "బుధ", "గురు", "శుక్ర", and "శని" are ordinary words, names, and planets
("శుక్ర గ్రహం చూడాలి") and stay in the title. A weekday alone is the coming one,
a week ahead when it names today; "ఈ" makes it this week's, "తదుపరి" next week's
(weeks start on Monday), and "వచ్చే" and "రాబోయే" the coming one. "ఈ వారం" alone
names no single day. The weekend is Saturday and Sunday: "వారాంతం", "వీకెండ్",
"శని ఆదివారాలు", and "శనివారం మరియు ఆదివారం" mean the coming Saturday, and today
on a Saturday or a Sunday, and "తదుపరి వారాంతం" is the one after.

A date range plans the task on its first day and makes it due on its last: "3
నుండి 5 మార్చి", "3 మార్చి నుండి 5 మార్చి వరకు", and "3-5 మార్చి" run from March
3 to March 5, with "నుంచి" for "నుండి" and "వరకు", "వరకూ", or "దాకా" after the
end if you like, and a month written once serves both days. The end must come
after the start ("5 నుండి 3 మార్చి" stays in the title), and the range names a
month, so "3 నుండి 5" is never a range of days. A span of weekdays does the
same: "సోమవారం నుండి బుధవారం" plans the task on the coming Monday and makes it
due on the Wednesday after it, while "సోమవారం నుండి శుక్రవారం" alone stays in
the title, since it is a week of work as often as it is the working week. As in
English, a number alone before a spaced dash belongs to the title ("Sprint 12 -
20 మార్చి" is planned for March 20), while "12-20 మార్చి" is a range. A range in
the past tense stays in the title whole, since it may be an event the task only
prepares for, and so does one whose end carries an ending other than "న", "కి",
or "కు" ("3 నుండి 5 మార్చిలో"). "9 గంటల నుండి 11 గంటల వరకు" is a time range: it
carries "గంటల" or a part of the day, so "3 నుండి 5 వరకు" alone stays in the
title.

A date needs its day number beside the month name (జనవరి, ఫిబ్రవరి, మార్చి,
ఏప్రిల్, మే, జూన్, జులై, ఆగస్టు, సెప్టెంబర్, అక్టోబర్, నవంబర్, డిసెంబర్, in the
spellings people type, and the short forms the system writes next to a day, such
as "అక్టో"). A month without a day, a short month before its day, a date in
digits with no label and no ending ("15/10"), a date the calendar lacks ("31
ఏప్రిల్"), and a month of the Telugu calendar ("వైశాఖం", "కార్తీకం") stay in the
title. A date in digits with the day first ("15/10/2026", "15.10.2026",
"15.10.") is a date, and "15/10" is a date only after "తేదీ" or before an ending
such as "న", "కి", "కు", or "నుండి". A date without a year that has already
passed means next year's.

A due day is a day before "వరకు", "దాకా", "లోగా", "లోపు", "కల్లా", or "నాటికి",
a day after a deadline label ("గడువు", "గడువు తేదీ", "చివరి తేదీ", "డెడ్‌లైన్"),
or a day before "గడువు" as the app writes it: "శుక్రవారం వరకు", "శుక్రవారంలోగా",
"శుక్రవారానికల్లా", "గడువు: 5 మే", "శుక్రవారం గడువు". "ఈరోజు వరకు" means "so
far" and is not read, and neither is a day in a line that says a deadline has
passed ("శుక్రవారం గడువు ముగిసింది"). A clock time before a deadline word
("శుక్రవారం సాయంత్రం 5 గంటలలోగా") makes the day the due day while the time stays
in the title.

A repeat is "ప్రతి" with a unit ("ప్రతి వారం", "ప్రతి నెల", "ప్రతి సంవత్సరం"),
"ప్రతిరోజు" or "రోజూ" (every day), a weekday ("ప్రతి సోమవారం", "ప్రతి సోమవారం
మరియు గురువారం"), the working days ("పనిదినాల్లో", "పనిరోజుల్లో", "ప్రతి సోమవారం
నుండి శుక్రవారం"), the weekend ("ప్రతి వారాంతం"), a counted interval ("ప్రతి 2
రోజులకు", "ప్రతి మూడు నెలలకు", "2 రోజులకోసారి", "ప్రతి రెండవ రోజు"), "రోజు
విడిచి రోజు" and its forms for the other units, "వారానికి ఒకసారి" and its forms,
or a day of the month ("ప్రతి నెల 5వ తేదీన"). "రోజువారీ", "వారంవారీ", "నెలవారీ",
and "సంవత్సరంవారీ" are read only at the end of the line, before a colon or a
comma, or with "ప్రాతిపదికన" or "గా" after them, since they are ordinary
adjectives too ("రోజువారీ రిపోర్ట్" is a daily report). An interval shorter than
a day ("ప్రతి 2 గంటలకు") and a count of weekends or working days ("3
వారాంతాల్లో") name no repeat and stay in the title. "ప్రతి" also means a price
rate, so "ప్రతి రోజు 500 రూపాయలు" is read as a daily repeat.

A length says that it is one: "30 నిమిషాలు", "2 గంటలు", "1.5 గంటలు", "అరగంట",
"పావు గంట", "గంటన్నర", "రెండున్నర గంటలు", maybe with "పాటు" or "సేపు" after the
unit ("2 గంటల పాటు") or the unit in its form before a noun ("30 నిమిషాల మీటింగ్"
is a 30-minute meeting). An amount that names a moment, an interval, or a bound
("2 గంటల తర్వాత", "ప్రతి 2 గంటలు", "2 గంటల లోపు", "రోజుకు 2 గంటలు", "కనీసం 2
గంటలు") is no length and stays in the title whole, and so does a range of
amounts ("2 నుండి 3 గంటలు").

A priority is "అధిక ప్రాధాన్యత", "సాధారణ ప్రాధాన్యత", or "తక్కువ ప్రాధాన్యత"
(also written "ప్రాధాన్యత: అధికం"), or an urgent word at the end of the line
("అత్యవసరం", "ముఖ్యం", "అర్జెంట్", "ముఖ్యమైనది") or at its start before a colon
or a comma ("అత్యవసరం: రిపోర్ట్ పంపండి"). Anywhere else these are ordinary words
and stay in the title ("అత్యవసర విభాగానికి వెళ్ళండి", "రిపోర్ట్ ముఖ్యం కాదు").

### From the Menu Bar Icon

Click the Lorvex icon in the menu bar. The compact menu shows an inline
quick-add field — type a line and press **Return** to save it to your inbox. The
line is read like any capture field's: a day, a time, a length, a `#list`, or a
priority you write in it becomes the task's own and shows under the field before
you save, and a line that names no day stays undated. Under it, **Today** shows the task you are on, the rest of the day's schedule
(events and timed tasks still ahead), then your other tasks and your habits;
**Next 7 Days** shows the week ahead. Click a task or an event to open it in
the main window: an event of today opens beside Today, one of a later day on
its day in the Calendar.

### From Home Screen Shortcuts (iOS/iPadOS)

On iPhone and iPad, long-press the Lorvex icon and choose **Quick Capture** from
the context menu. This opens the capture sheet directly, bypassing the main app
navigation. You can also add the **Capture Task** shortcut from the Shortcuts
app to your Home Screen for single-tap capture, or the **Lorvex Capture**
control to Control Center or the Lock Screen (see Control Center, below).

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
list card to move them; lists with assigned tasks must be emptied before deletion.

### The Circle on a Task Row

The circle at the start of a task row checks the task off when you click or tap
it. Its color says how much the task matters: red for high priority, orange
for normal, and gray for low. A done task's circle is a green check, a
cancelled task's is an ×, and a Someday task's is a moon.

With **Differentiate Without Color** turned on (System Settings ▸
Accessibility ▸ Display on Mac, Settings ▸ Accessibility ▸ Display & Text Size
on iPhone and iPad), an open task's circle also carries a mark, so the priority
does not depend on color: an exclamation point for high priority, a down arrow
for low priority, and a plain ring for normal. VoiceOver reads a priority other
than normal after the task's title.

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

On the Mac, drag a task row onto a list in the sidebar to move it; the list is
outlined while the task is over it, the task leaves the pane it came from, and
a short message names the list it landed in. Press ⌘Z (**Edit → Undo Move to
List**) to put it back. Dragging a row that is part of a multi-task selection
moves the whole selection, and dropping the tasks on **Today** instead plans
them for today. To move one task without dragging, right-click it and choose
**Move to List**; to reassign several at once, select them and use the **Lists**
submenu in the workspace selection menu — the batch menu that appears in the
header while a selection is active. Each of these moves shows the same message
and can be undone with ⌘Z. On iPhone and iPad, tap **Select** in the Tasks
toolbar, tap the tasks, then choose **List** in the bottom bar and pick the list
to file them in.

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

### Searching Tasks

The search field in All Tasks (⌘F on the Mac), the command palette, and the
assistant's `search_tasks` tool share one search. It ignores capitals and
accents, lets the last word be a start of a word, and needs every word to
appear in the title, notes, assistant context, or tags. Letters typed in a
simpler form than the stored text still match: `lodz` finds `Łódź`, `все`
finds `всё`, `strasse` finds `Straße`, `isik` finds `Işık`, `καλημερα` finds
`Καλημέρα`, and `اسماء` finds `أسماء`. Text in scripts that put no spaces
between words (Chinese, Japanese, Korean, Thai, Lao, Burmese, and Khmer)
matches wherever the typed characters appear inside it. Searching lists,
habits, and memory entries, the command palette, tag suggestions, and the
pickers that Shortcuts and Siri show compare text the same way.

When a word you searched for is in a task's notes, its assistant context, or a
tag the row does not show, and not in the title, the row quotes the text around
it on a line under the title, with the word in bold. A task whose title holds
the word, or whose visible tags do, shows no quote. The command palette's task
results quote the same way, and since they show no tags, they quote a tag too.

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
rows to select them; a bottom action bar offers Complete, Defer, Reopen, and
List, which opens a menu of the lists to move the selection to.

---

## Calendar & EventKit

### Viewing Calendar Events

The **Calendar** workspace shows a merged timeline of Lorvex planning blocks
and Apple Calendar events. EventKit events appear in a distinct style alongside
your Lorvex tasks so you can see scheduling conflicts at a glance.
Use the row buttons or context menu to edit or delete Lorvex-owned events.
Imported EventKit events are read-only overlays.

On iPhone and iPad, the control at the top of the **Calendar** tab switches
between **Day**, **Week**, and **Month**, and keeps the day you were looking
at. The calendar opens in the view you used last. Month view shows six weeks of days: on iPhone each day carries a dot for
each event and a ring for each task, and on iPad the days name them. Tap a
day to list its events and tasks under or beside the month, swipe to change
months, and tap **Today** to come back. To move a task to another day, drag it
from that list onto the day.

On the Mac, the week and day grids show a task planned for a day as a pill in
the all-day row, or as a block at its time. Drag a pill onto a time in any
column to give the task that time: the column marks where it will start, and
the task keeps its length (its estimate, or half an hour when it has none). Drag
a block to another time or day to move it in 15-minute steps. Drag a block's top
or bottom edge to change when the task starts or ends, down to 15 minutes; the
task's estimate stays as it is. Either drag shows the block's new time as you
go. Drop a task on the all-day row to plan it for that day without a time.
Right-click a task for **Plan a Day Later** and **Plan a Week Later**. Every one
of these changes can be undone with ⌘Z (**Plan Task**), and a finished task
stays where it is.

Month view takes the same drops: drag a task chip onto another day and the task
moves there, keeping its time if it has one. Right-click a day for **Create
Event** on that day (at 9 AM, or at the next full hour for today), and
right-click a chip for its menu: **Open Details**, **Edit**, and **Delete** for
an event you own, and the same menu as in every task list for a task. The side-panel button in the toolbar
(**Unplanned Tasks**) opens a column beside the calendar that lists the open
tasks with no planned day, most important first, and ends with how many more
there are. Drag one onto a time in a day, onto a day's all-day row, or onto a
month cell, and it leaves the column. The column stays as you left it the next
time you open the Calendar. To plan a task without dragging, right-click it in
any task list, the column included, and choose **Plan Task**, then Today,
Tomorrow, In 3 days, or Next Week. The **Task** menu in the menu bar has the same
submenu for every selected task. A task keeps its time of day, and ⌘Z undoes
the change.

While the Calendar is open, the **View** menu carries its controls too. **Today**
(⌘T; **This Week** or **This Month** in those views) goes back to the current
period, **Day**, **Week**, and **Month** switch the view, and **Show Unplanned
Tasks** or **Hide Unplanned Tasks** (⌥⌘U) opens or closes the column. These
items appear only while a window shows the Calendar.

An event that lasts 24 hours or more appears in the all-day row of each day it
covers. A shorter event that runs past midnight appears on both days: the
first shows when it starts, and the second shows when it ends. Month view reads
the same way: a chip names its time after the title where the width allows, and
an event that ends on a day sits first among that day's timed items, since it
runs from midnight.

Calendar permission is required to display EventKit events. If permission is
denied, Lorvex shows only its own planning blocks with a permission prompt in
the Settings diagnostics panel.

### Creating and Editing Events

On the Mac, click **+** (Create Event) in the Calendar toolbar, or click or
drag across empty time in the grid. On iPhone and iPad, tap **New Event** in
the **Calendar** tab, or touch and hold a day in Month view. An event from the
toolbar or **New Event** starts at the next full hour and lasts one hour; on
iPhone and iPad, an event for a day other than today (the day the calendar
shows, or the day chosen in Month view) starts at 9 AM. A click on the grid
starts at that time, and a drag covers the time you dragged across.

**Start** and **End** each have a day and, unless the event is all day, a
time, so an event can run overnight, such as from 10 PM to 1 AM, or across
several days. Changing the start moves the end with it, so the event keeps its
length. Picking an end time earlier than the start time ends the event the
next day. An event can't be saved while its end is not after its start.

To move an event, drag it in the grid; on iPhone and iPad, touch and hold it
first. On the Mac, drag an event's top or bottom edge to change when it starts
or ends; the block shows its new time as you drag. Repeating events and events
that continue past midnight into the next day can't be dragged; open them to
change their times. An event that ends at exactly midnight counts as a one-day
event and drags like any other. On the Mac, press ⌘Z (**Edit → Undo Move Event**) to put a dragged or resized event back
at its earlier times. Only the times are restored, so a title or location you
changed afterwards stays.

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
- **What moved forward**: the tasks you finished that day. The list shows up
  to five and counts the rest.
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
- **What moved forward**: the week's top finished tasks. The list shows up to
  five and counts the rest.
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

Lorvex provides two controls. **Lorvex Today**, on iPhone, iPad, and Mac, shows
the task at the top of Today and opens Lorvex directly to Today when tapped.
**Lorvex Capture**, on iPhone and iPad, opens Lorvex with the capture sheet
ready for a new task, so a thought is one swipe and one tap away from any app
or from the Lock Screen. On iPhone or iPad, swipe down to open Control Center,
long-press to enter edit mode, tap **＋ Add a Control**, and search for
**Lorvex Today** or **Lorvex Capture**. On a Mac, open Control Center from the
menu bar, click **Edit Controls**, and search for **Lorvex Today**. Either
control can also replace one of the two buttons at the bottom of the iPhone
Lock Screen, and an iPhone with an Action button can be set to run one from
there.

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
| ⌥⌘N | Quick Capture: the small capture window over the current app |
| ⌘K | Command Palette: find a task, go somewhere, or capture |
| ⌘F | Find: focus the search field in All Tasks or Memory; from any other workspace, open All Tasks and focus its search field |
| ⌘1 | Today |
| ⌘2 | Calendar |
| ⌘3 | All Tasks |
| ⌘4 | Review |
| ⌘5 | Habits |
| ⌘6 | Memory |
| ⌥⌘1–⌥⌘5 | Open Today, Calendar, All Tasks, Review, or Habits in its own window |
| ⌘← / ⌘→ | Previous / next day, week, or month in Calendar, and day or week in Review (the keys swap in right-to-left languages) |
| ⌃⌘S | Show or hide the sidebar |
| ⌘T | Calendar: go back to today (or this week, or this month) |
| ⌥⌘U | Calendar: show or hide the Unplanned Tasks column |
| ⌘R | Refresh data |
| ⌘, | Settings |

The numeric accelerators follow the sidebar from top to bottom, then Memory in
its footer (⌘1–⌘6). Adding ⌥ opens the same destination in its own window
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
| ⌘⌫ | Cancel task (while you type in a text field or editor, it deletes to the start of the line instead) |

Complete and Cancel (for a task that does not repeat) can be undone with ⌘Z,
**Edit → Undo Complete Task** or **Undo Cancel Task**, however you started them:
from the task's circle, from these shortcuts or the **Task** menu, or from a
selection menu. Completing several selected tasks at once is one step to undo.

### Quick-Add Field (macOS)

The inline quick-add sits under today's tasks on Today and at the top of the
Tasks list; ⌘N (or File → New Task) focuses it.

| Shortcut | Action |
|---|---|
| Return | Save the task and keep the field focused for the next one |

Text pasted over several lines becomes one task: each line break reads as a
space. The menu bar field, the command palette, and the Quick Capture window do
the same.

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
