#!/usr/bin/env bash
# Headless iPhone/iPad screenshots of the built LorvexMobileApp. Boots the
# simulator without Simulator.app, launches the app once per route with the
# seeded sample data and a deep link, screenshots via `simctl io`, and shuts
# the device down again. Nothing is opened on screen.
#
# Usage: script/ios_sim_screenshots.sh <outdir> <light|dark> <route ...>
# The product-day clock is pinned to LORVEX_PREVIEW_NOW (default 11:20, when
# the sample day's first timed task has passed and its second is running) so the
# captures read the same at any hour. LORVEX_SIM_EXTRA_ARGS appends launch
# arguments to every route, e.g. `-AppleLanguages (zh-Hans) -AppleLocale zh_CN`
# to capture the app in Simplified Chinese without changing the simulator's
# own language, `-lorvexPreviewDayState <empty|allDone|overbooked>` to open
# Today in a state the sample day never reaches (pair `allDone` with
# LORVEX_PREVIEW_NOW=17:45, after the day's meetings), or
# `-UIPreferredContentSizeCategoryName
# UICTContentSizeCategoryXXXL` to check a larger text size (the widgets* routes
# show whether a fixed-size widget still fits), or
# `-lorvexPreviewOrientation landscape` to lay the app out in landscape (the
# screenshot comes out in landscape too), or `-lorvexSeedStressData` to add the
# content that breaks layouts (very long titles, lists and tags, a 25-item
# checklist, overlapping, all-day and overnight events, a crowded day, ten
# habits) on top of the sample day, with `-lorvexScrollListTo <middle|end>` to
# scroll the tallest list on screen before the shot. LORVEX_SIM_SETTLE sets the
# seconds to wait after each launch before the screenshot (default 4.5); raise
# it when a loaded machine draws a screen late, and to about 11 for the stress
# seed, which takes a few seconds to write.
# Routes: today today-suggestion tasks calendar calendar-week calendar-month
#         habits review
#         review-week setup-welcome setup-cloudSync setup-notifications setup-done
#         settings settings-bottom settings-export memory lists task-detail habit-detail
#         habit-detail-middle habit-detail-end habit-editor review-end review-week-end
#         memory-detail task-detail-checklist task-detail-reminder capture
#         capture-filled capture-repeat
#         task-detail-repeat task-detail-repeat-editor task-detail-depends memory-composer
#         memory-composer-filled tasks-search-empty habits-search-empty
#         sheet-newlist sheet-editlist sheet-newhabit task-edit
#         sheet-newlist-appearance sheet-editlist-appearance sheet-newhabit-appearance
#         widgets widgets-large widgets-lock widgets-more, or any raw
#         lorvex:// URL. A route written as <first>+<second> launches on
#         <first> and opens <second> two seconds later (the DEBUG
#         -lorvexOpenURLLater hook), so the capture shows <second> pushed
#         onto a tab that is already on screen, the way an in-app tap or a
#         Spotlight open reaches it; the file is named <second>-pushed.
#         The widgets* routes open one section of the DEBUG widget gallery
#         (-lorvexWidgetGallery -lorvexWidgetGallerySection <section>): the
#         real widget views at their canonical sizes over a sample day —
#         widgets shows the small and medium Today families, widgets-large the
#         large one, widgets-lock the Lock Screen families, and widgets-more
#         the Habits and Progress widgets.
#         today-suggestion opens Today with suggested times waiting (the
#         DEBUG -lorvexUIPreviewSuggestedTimes hook): in the pane beside Today
#         on iPad, in the schedule sheet on iPhone.
#         capture-filled types a line with a day, a length, a deadline,
#         a priority, and a #word into the capture sheet (the DEBUG
#         lorvex://sheet/capture/<text> hook), so the preview of what
#         Add will create renders under it; capture-repeat types a
#         repeating line with a clock time.
#         calendar-week and calendar-month open the calendar on its
#         seven-day grid or its month grid (the DEBUG
#         lorvex://tab/calendar/week and lorvex://tab/calendar/month hooks)
#         instead of the default day grid, and review-week opens Review on
#         its week digest (lorvex://tab/review/week).
#         task-detail-repeat and task-detail-depends open the seeded weekly
#         task and the task with a dependency (the DEBUG
#         lorvex://findtask/<title> hook); task-detail-repeat-editor opens the
#         weekly task's repeat editor (lorvex://findtask/<title>/field/repeat),
#         where the day a plain weekly rule falls on shows chosen. The raw URL
#         lorvex://firsttask/field/<field> raises the editor behind one
#         sentence word of Today's first task (waitsOn, due, tags, …).
#         sheet-newlist and sheet-editlist open the Tasks home with its New
#         List sheet raised, or the Edit List sheet of the first list that has
#         a description; sheet-newhabit opens Habits with its New Habit sheet
#         raised; task-edit opens Today's first task with its full Edit sheet
#         raised (the DEBUG lorvex://sheet/<newlist|editlist|newhabit> and
#         lorvex://firsttask/edit hooks). The -appearance variants of the
#         New List, Edit List, and New Habit routes also open the icon and
#         color popover over the sheet's header.
#         habit-detail-end opens the first habit's detail scrolled to its end
#         (the DEBUG -lorvexScrollHabitDetailToEnd hook), where its reminders
#         and the Archive and Delete buttons sit; habit-detail-middle opens it
#         on the middle of its content (-lorvexScrollHabitDetailToMiddle),
#         where the Progress panels sit on a page taller than the screen.
#         habit-editor opens that habit's editor over its detail
#         (-lorvexOpenHabitEditor), where its cadence and weekdays are set.
#         review-end and review-week-end open the Day and Week reviews at
#         their end (-lorvexScrollReviewToEnd), where the day rows and the
#         task lists sit on a page taller than the screen.
#         setup-welcome, setup-cloudSync, setup-notifications, and setup-done
#         open the first-run wizard on that page (the DEBUG -lorvexSetupStep
#         hook) over Today, with the setup-completed flag cleared for that
#         launch only.
#         settings-bottom opens Settings scrolled to its Diagnostics section
#         (the DEBUG -lorvexScrollSettingsToDiagnostics hook), which puts the
#         summary card and the newest failure rows on screen together;
#         settings-export opens it scrolled to Data Export
#         (-lorvexScrollSettingsToDataExport); the
#         *-search-empty routes
#         pre-fill a query that matches nothing so the no-results row renders.
# Env:    LORVEX_SIM_DEVICE  device name (default: iPhone 17 Pro; e.g.
#                            "iPad Pro 13-inch (M5)"); the device on the newest
#                            iOS runtime with that name is used
#         LORVEX_SIM_UDID    exact device UDID, overriding the name lookup
#         LORVEX_SIM_FRESH   1 to skip the sample seed, so every route shows the
#                            empty store a fresh install starts with
#         LORVEX_SIM_INCREASE_CONTRAST  "enabled" to capture with the Increase
#                            Contrast accessibility setting on; any other
#                            value (the default) pins it off
# Requires script/ios_sim_build.sh to have produced the .app.
set -u
OUT="${1:?usage: ios_sim_screenshots.sh <outdir> <light|dark> <route ...>}"
APPEARANCE="${2:-light}"
shift 2 || true
ROUTES=("$@")
[[ ${#ROUTES[@]} -gt 0 ]] || ROUTES=(today tasks calendar habits review)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/dist/DerivedData-LorvexMobileApp/Build/Products/Debug-iphonesimulator/LorvexMobileApp.app"
BUNDLE=com.lorvex.apple
DEVICE="${LORVEX_SIM_DEVICE:-iPhone 17 Pro}"
if [[ ! -d "$APP" ]]; then
  echo "missing $APP — run script/ios_sim_build.sh first" >&2
  exit 1
fi
source "$ROOT_DIR/script/lib_ios_sim_device.sh"
UDID="$(resolve_ios_sim_udid "$DEVICE")"
if [[ -z "$UDID" ]]; then
  echo "no available simulator named '$DEVICE'" >&2
  exit 1
fi
url_for() {
  case "$1" in
    lorvex://*) echo "$1" ;;
    today|tasks|calendar|habits|review) echo "lorvex://tab/$1" ;;
    calendar-week) echo "lorvex://tab/calendar/week" ;;
    calendar-month) echo "lorvex://tab/calendar/month" ;;
    review-week|review-week-end) echo "lorvex://tab/review/week" ;;
    review-end) echo "lorvex://tab/review" ;;
    settings|memory|lists) echo "lorvex://dest/$1" ;;
    settings-bottom|settings-export) echo "lorvex://dest/settings" ;;
    today-suggestion) echo "lorvex://tab/today" ;;
    tasks-search-empty) echo "lorvex://tab/tasks/search/quokka" ;;
    habits-search-empty) echo "lorvex://tab/habits/search/quokka" ;;
    task-detail) echo "lorvex://firsttask" ;;
    habit-detail|habit-detail-end|habit-detail-middle|habit-editor) echo "lorvex://firsthabit" ;;
    memory-detail) echo "lorvex://firstmemory/push" ;;
    task-detail-checklist) echo "lorvex://firsttask/compose/checklist" ;;
    task-detail-reminder) echo "lorvex://firsttask/compose/reminder" ;;
    task-detail-repeat) echo "lorvex://findtask/Submit%20the%20weekly%20timesheet" ;;
    task-detail-repeat-editor) echo "lorvex://findtask/Submit%20the%20weekly%20timesheet/field/repeat" ;;
    task-detail-depends) echo "lorvex://findtask/Book%20the%20offsite%20venue" ;;
    capture) echo "lorvex://sheet/capture" ;;
    capture-filled) echo "lorvex://sheet/capture/Call%20the%20caterer%20about%20the%20offsite%20menu%20tomorrow%2020%20min%20by%20friday%20urgent%20%23work" ;;
    capture-repeat) echo "lorvex://sheet/capture/Standup%20every%20mon%20and%20thu%209%3A30am" ;;
    memory-composer) echo "lorvex://memorycomposer" ;;
    memory-composer-filled) echo "lorvex://memorycomposer/filled" ;;
    sheet-newlist) echo "lorvex://sheet/newlist" ;;
    sheet-editlist) echo "lorvex://sheet/editlist" ;;
    sheet-newhabit) echo "lorvex://sheet/newhabit" ;;
    sheet-newlist-appearance) echo "lorvex://sheet/newlist/appearance" ;;
    sheet-editlist-appearance) echo "lorvex://sheet/editlist/appearance" ;;
    sheet-newhabit-appearance) echo "lorvex://sheet/newhabit/appearance" ;;
    task-edit) echo "lorvex://firsttask/edit" ;;
    *) echo "lorvex://tab/today" ;;
  esac
}
# Extra launch arguments a route needs beyond the seed and deep link.
extra_args_for() {
  case "$1" in
    settings-bottom) echo "-lorvexScrollSettingsToDiagnostics" ;;
    settings-export) echo "-lorvexScrollSettingsToDataExport" ;;
    habit-detail-end) echo "-lorvexScrollHabitDetailToEnd" ;;
    habit-detail-middle) echo "-lorvexScrollHabitDetailToMiddle" ;;
    habit-editor) echo "-lorvexOpenHabitEditor" ;;
    review-end|review-week-end) echo "-lorvexScrollReviewToEnd" ;;
    today-suggestion) echo "-lorvexUIPreviewSuggestedTimes" ;;
    widgets) echo "-lorvexWidgetGallery -lorvexWidgetGallerySection today" ;;
    widgets-large) echo "-lorvexWidgetGallery -lorvexWidgetGallerySection large" ;;
    widgets-lock) echo "-lorvexWidgetGallery -lorvexWidgetGallerySection lock" ;;
    widgets-more) echo "-lorvexWidgetGallery -lorvexWidgetGallerySection more" ;;
    setup-*) echo "-lorvexSetupStep ${1#setup-}" ;;
    *) echo "" ;;
  esac
}
mkdir -p "$OUT"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || sleep 8
xcrun simctl install "$UDID" "$APP" || { echo "install failed on $UDID" >&2; exit 1; }
# Delete the seeded store before launching. `-lorvexSeedSampleData` only seeds a
# store with no tasks in it, and the store lives in the shared App Group
# container, which survives both a reinstall and `simctl uninstall` — so without
# this the capture silently renders whatever a previous run seeded, however old.
# Refuses to delete anything outside a simulator device directory.
GROUP_CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" groups 2>/dev/null | awk '$1 == "group.com.lorvex.apple" { print $2 }')"
case "$GROUP_CONTAINER" in
  */CoreSimulator/Devices/"$UDID"/*) rm -rf "${GROUP_CONTAINER:?}/Lorvex" ;;
  "") echo "warning: no simulator App Group container; capture may show stale seed data" >&2 ;;
  *) echo "refusing to clear unexpected container path: $GROUP_CONTAINER" >&2; exit 1 ;;
esac
SEED_ARG="-lorvexSeedSampleData"
[[ "${LORVEX_SIM_FRESH:-}" == 1 ]] && SEED_ARG=""
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 >/dev/null 2>&1
xcrun simctl ui "$UDID" appearance "$APPEARANCE" >/dev/null 2>&1
# A device keeps the text size it was last given, so pin the default (Large)
# for captures to show what a new iPhone shows; a launch argument
# (-UIPreferredContentSizeCategoryName) still picks another size for the app.
xcrun simctl ui "$UDID" content_size large >/dev/null 2>&1
# Increase Contrast is a device setting too: pin it off unless asked for, so a
# capture taken after a contrast run does not silently keep it.
xcrun simctl ui "$UDID" increase_contrast "${LORVEX_SIM_INCREASE_CONTRAST:-disabled}" >/dev/null 2>&1
for ROUTE in "${ROUTES[@]}"; do
  LATER=""
  if [[ "$ROUTE" == *+* ]]; then
    LATER="${ROUTE#*+}"
    ROUTE="${ROUTE%%+*}"
  fi
  NAME="${ROUTE##*/}"; NAME="${NAME//:/-}"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
  # The first-run wizard covers every screen until setup completes, so only
  # the setup-* routes launch with the flag cleared.
  SETUP_COMPLETED=true
  [[ "$ROUTE" == setup-* ]] && SETUP_COMPLETED=false
  xcrun simctl spawn "$UDID" defaults write "$BUNDLE" setupCompleted -bool "$SETUP_COMPLETED" >/dev/null 2>&1
  EXTRA_ARGS="$(extra_args_for "$ROUTE")"
  if [[ -n "$LATER" ]]; then
    NAME="${LATER##*/}-pushed"; NAME="${NAME//:/-}"
    EXTRA_ARGS="$EXTRA_ARGS -lorvexOpenURLLater $(url_for "$LATER")"
  fi
  # shellcheck disable=SC2086  # SEED_ARG, EXTRA_ARGS, and LORVEX_SIM_EXTRA_ARGS are space-separated argument lists.
  xcrun simctl launch "$UDID" "$BUNDLE" $SEED_ARG -lorvexOpenURL "$(url_for "$ROUTE")" \
    -lorvexPreviewNow "${LORVEX_PREVIEW_NOW:-11:20}" $EXTRA_ARGS ${LORVEX_SIM_EXTRA_ARGS:-} >/dev/null 2>&1
  sleep "${LORVEX_SIM_SETTLE:-4.5}"
  # The scroll hooks settle over a few runloop turns after the data loads.
  [[ -n "$EXTRA_ARGS" ]] && sleep 3
  xcrun simctl io "$UDID" screenshot "$OUT/$NAME-$APPEARANCE.png" >/dev/null 2>&1 && echo "captured $NAME $APPEARANCE"
done
xcrun simctl ui "$UDID" appearance light >/dev/null 2>&1
xcrun simctl ui "$UDID" increase_contrast disabled >/dev/null 2>&1
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
xcrun simctl shutdown "$UDID" >/dev/null 2>&1
echo "finished → $OUT (booted devices left: $(xcrun simctl list devices booted | grep -c Booted))"
