#!/usr/bin/env bash
# Capture every macOS workspace of the DEBUG build as PNGs without activating
# the app or stealing focus. Runs `LorvexApple --ui-preview -uiPreviewTour`,
# which renders the real main window over a seeded in-memory core (the
# production App Group store is never opened), then screenshots the window
# by its window number at each `LORVEX_UI_PREVIEW_STOP=<workspace>` marker.
# The tour holds each workspace on screen until this script acknowledges the
# stop, so a settle loop that runs longer than the app's own dwell time can
# never photograph the next workspace under the previous one's name.
#
# Usage: script/ui_tour_macos.sh <light|dark> <outdir>
# The tour seeds the day the preview's assistant planned (-uiPreviewPlannedDay):
# today's briefing and two timed tasks, 9:45 and 10:55. The product-day clock
# is pinned to LORVEX_PREVIEW_NOW (default 11:20, when the first task's time
# has passed and the second's is running) so the captures read the same at any
# hour. LORVEX_TOUR_EXTRA_ARGS appends launch arguments, e.g.
# `-uiPreviewUntimed` to seed the same day without its times, the state of
# anyone who never schedules, or `-lorvexPreviewDayState <state>` to open Today
# in a state the seeded day never reaches: `empty` (nothing listed, nothing
# done, no meetings), `allDone` (every listed task done; pair it with
# LORVEX_PREVIEW_NOW=17:45, after the day's meetings, for the done sentence),
# or `overbooked` (more estimated work than free time), or `-uiPreviewEmptyStore`
# to open every workspace on an empty store, as someone sees the app before
# adding anything (stops that need a task, habit, or list are skipped).
# Requires a debug build first: `swift build -j 4 --product LorvexApple`.
# Output: <outdir>/<workspace>-<appearance>.png for today, today-suggestion
# (Today with suggested times waiting in the schedule pane), today-event (a
# timed event from Today's schedule open in the inspector), tasks,
# tasks-inspector, tasks-inspector-waiting (a task that waits on an unfinished
# one, so its Start is unavailable), tasks-list (Tasks scoped to the first list
# that is not the Inbox), lists, calendar, calendar-day, calendar-month, habits,
# habits-inspector and habits-inspector-open (a habit done today and one
# still open), reviews, reviews-weekly, memory, settings-<category> for
# each Settings category (general, permissions, calendar, cloudSync, mcpHost,
# data, diagnostics; the Settings window in its own window), and, each in a
# window of its own: menubar and menubar-week (the menu bar panel on Today
# and on Next 7 Days), list-window (a detached
# list window, on the list tasks-list scopes to), palette-jump and
# palette-search (the command palette on a list's name and on a word that
# names no destination), task-editor-doOn, task-editor-due,
# task-editor-estimate, task-editor-repeat, task-editor-reminders,
# task-editor-tags, and task-editor-dependencies (the task detail's field popovers, on a task that
# waits on another), habits-inspector-fields (a habit with ten weeks of
# history, reminders, and a goal), habit-editor-repeat, habit-editor-reminder,
# and habit-editor-goal
# (that habit's field popovers), sheet-createList, sheet-editList, and
# sheet-createHabit (the list and habit create sheets and the list edit
# sheet), and setup-welcome, setup-cloudSync,
# setup-permissions, setup-permissions-answered (Calendar allowed and
# Notifications denied, the page's tallest state), and setup-done (the
# first-run wizard's pages); plus tour-<appearance>.log.
set -u
APPEARANCE="${1:-light}"
OUT="${2:?usage: ui_tour_macos.sh <light|dark> <outdir>}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/.build/debug/LorvexApple"
if [[ ! -x "$APP" ]]; then
  echo "missing $APP — run: swift build -j 4 --product LorvexApple" >&2
  exit 1
fi
mkdir -p "$OUT"
LOG="$OUT/tour-$APPEARANCE.log"
: > "$LOG"
# Acknowledgement drop box for the stop handshake. Recreated each run: a stale
# ack from an earlier round would release a stop before it was photographed.
ACK="$OUT/.ack-$APPEARANCE"
rm -rf "$ACK"
mkdir -p "$ACK"

# The preview process is our own child; kill it by PID, never by name, so the
# owner's installed Lorvex.app is never touched.
# One screenshot attempt, retried: screencapture fails intermittently when it is
# called in quick succession, and silently dropping a workspace from the round
# is worse than taking a moment longer.
shoot() {
  local win="$1" dest="$2" try
  for try in 1 2 3 4; do
    if screencapture -x -o -l "$win" "$dest" 2>>"$LOG" && [[ -s "$dest" ]]; then
      return 0
    fi
    /bin/sleep 0.4
  done
  echo "warning: could not capture window $win for $(basename "$dest")" | tee -a "$LOG" >&2
  return 1
}

# A workspace can still be settling when its marker arrives: under load SwiftUI
# layout and insertion animations run past the app's own settle delay, and a
# half-laid-out frame is indistinguishable from a layout bug when the capture is
# reviewed later. Shoot until two consecutive frames are identical, so every PNG
# kept is a settled one.
capture_settled() {
  local win="$1" dest="$2" prev="$2.prev" attempt=0
  shoot "$win" "$dest" || return 1
  while (( attempt < 4 )); do
    mv "$dest" "$prev"
    if ! shoot "$win" "$dest"; then
      mv "$prev" "$dest"
      return 0
    fi
    if cmp -s "$prev" "$dest"; then
      rm -f "$prev"
      return 0
    fi
    attempt=$((attempt + 1))
  done
  rm -f "$prev"
  echo "warning: $(basename "$dest") never settled after $attempt recaptures" >&2
  return 0
}


# Launch as a real background job and stream its markers through a FIFO. With
# `exec 3< <(...)` the shell's `$!` does not name the substituted process, so the
# kill below silently hit nothing and every run left a preview app alive with an
# ordered-front window on the user's desktop. A background job's `$!` is exact,
# and the trap kills it even when the script exits early.
FIFO="$OUT/.tour-$APPEARANCE.fifo"
rm -f "$FIFO"
mkfifo "$FIFO"
# shellcheck disable=SC2086  # LORVEX_TOUR_EXTRA_ARGS is a space-separated argument list.
"$APP" --ui-preview -uiPreviewPlannedDay -uiPreviewTour \
  -uiPreviewAppearance "$APPEARANCE" -uiPreviewAckDir "$ACK" -lorvexPreviewNow "${LORVEX_PREVIEW_NOW:-11:20}" \
  ${LORVEX_TOUR_EXTRA_ARGS:-} >"$FIFO" 2>>"$LOG" &
APP_PID=$!
trap 'kill "$APP_PID" 2>/dev/null; rm -f "$FIFO"; rm -rf "$ACK"' EXIT
exec 3< "$FIFO"
WIN=""
while IFS= read -r -t 120 line <&3; do
  echo "$line" >> "$LOG"
  case "$line" in
    LORVEX_UI_PREVIEW_WINDOW=*) WIN="${line#*=}"; echo "window=$WIN" ;;
    LORVEX_UI_PREVIEW_STOP=*)
      STOP="${line#*=}"
      if [[ -n "$WIN" && "$WIN" != "-1" ]]; then
        capture_settled "$WIN" "$OUT/$STOP-$APPEARANCE.png" && echo "captured $STOP"
      else
        echo "no window for $STOP"
      fi
      : > "$ACK/$STOP.ack" ;;
    LORVEX_UI_PREVIEW_TOUR_DONE) echo "tour done"; break ;;
  esac
done
kill "$APP_PID" 2>/dev/null
wait "$APP_PID" 2>/dev/null
exec 3<&-
rm -f "$FIFO"
rm -rf "$ACK"

# Two byte-identical PNGs mean one capture landed on a workspace that had
# already moved on. Reviewed one at a time the pair looks fine, so the round
# says so itself.
shasum -a 256 "$OUT"/*-"$APPEARANCE".png 2>/dev/null |
  awk '{ name = $2; sub(/.*\//, "", name); names[$1] = names[$1] " " name; count[$1]++ }
       END { for (hash in count) if (count[hash] > 1)
               print "warning: identical captures —" names[hash] }' >&2

echo "finished $APPEARANCE → $OUT"
