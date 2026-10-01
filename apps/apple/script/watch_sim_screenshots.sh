#!/usr/bin/env bash
# Headless Apple Watch screenshots of the built LorvexWatchApp. Boots the watch
# simulator (and its paired iPhone, which the watch needs to launch apps)
# without Simulator.app, launches the app once per page with the DEBUG
# `-lorvexUIPreview` replica — a fixed sample day written by the app itself, so
# no phone has to push a snapshot — screenshots via `simctl io`, and shuts the
# devices it booted down again. Nothing is opened on screen. Run it on its own:
# a watch simulator on a loaded machine misses its launch window, so a fresh
# boot gets time to settle, each launch is retried, and the page gets a few
# seconds to settle before its shot. A page that still comes back as the watch
# face (the app was not in front yet) is rerun by naming just that page.
#
# Usage: script/watch_sim_screenshots.sh <outdir> <page ...>
# Pages: today habits capture, or actions (Today with its lead task's actions
#        open). watchOS has one appearance, so there is no light/dark argument.
# Env:   LORVEX_WATCH_SIM_DEVICE  device name (default: Apple Watch Series 11
#                                 (46mm)); the newest watchOS runtime wins
#        LORVEX_WATCH_SIM_UDID    exact device UDID, overriding the name lookup
#        LORVEX_WATCH_SIM_EXTRA_ARGS  launch arguments appended to every page,
#                                 e.g. `-AppleLanguages (zh-Hans) -AppleLocale
#                                 zh_CN` to capture the app in Simplified Chinese
# Requires script/watch_sim_build.sh to have produced the .app.
set -u
OUT="${1:?usage: watch_sim_screenshots.sh <outdir> <page ...>}"
shift 1 || true
PAGES=("$@")
[[ ${#PAGES[@]} -gt 0 ]] || PAGES=(today habits capture)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/dist/DerivedData-LorvexWatchApp/Build/Products/Debug-watchsimulator/LorvexWatchApp.app"
BUNDLE=com.lorvex.apple.watchkitapp
DEVICE="${LORVEX_WATCH_SIM_DEVICE:-Apple Watch Series 11 (46mm)}"
if [[ ! -d "$APP" ]]; then
  echo "missing $APP — run script/watch_sim_build.sh first" >&2
  exit 1
fi
source "$ROOT_DIR/script/lib_watch_sim_device.sh"
UDID="$(resolve_watch_sim_udid "$DEVICE")"
if [[ -z "$UDID" ]]; then
  echo "no available watch simulator named '$DEVICE'" >&2
  exit 1
fi
PHONE="$(paired_phone_udid "$UDID")"
is_booted() { xcrun simctl list devices -j | python3 -c '
import json, sys
udid = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["udid"] == udid:
            sys.exit(0 if device.get("state") == "Booted" else 1)
sys.exit(1)' "$1"; }
BOOTED_HERE=()
# Shut down what this run booted however it ends, including an early exit.
# ${arr[@]+...} keeps an empty array from tripping `set -u` in bash 3.2.
shutdown_booted_here() {
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
  for DEVICE_ID in ${BOOTED_HERE[@]+"${BOOTED_HERE[@]}"}; do
    xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1
  done
}
trap shutdown_booted_here EXIT
boot() {
  is_booted "$1" && return 0
  xcrun simctl boot "$1" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$1" -b >/dev/null 2>&1 || sleep 8
  BOOTED_HERE+=("$1")
}
launch_args_for() {
  case "$1" in
    actions) echo "-lorvexUIPreviewPage today -lorvexUIPreviewActions" ;;
    today|habits|capture) echo "-lorvexUIPreviewPage $1" ;;
    *) echo "unknown page: $1" >&2; return 1 ;;
  esac
}
mkdir -p "$OUT"
[[ -n "$PHONE" ]] && boot "$PHONE"
boot "$UDID"
# A watch simulator keeps doing first-boot work after bootstatus returns, and
# launches during that window are slow to reach the front.
[[ ${#BOOTED_HERE[@]} -gt 0 ]] && sleep 15
# Right after a boot the paired phone's appconduitd can still be reconciling
# watch apps and ask for an uninstall that fails the install; a retry lands.
INSTALLED=0
for ATTEMPT in 1 2 3; do
  if xcrun simctl install "$UDID" "$APP" 2>"$OUT/install.err"; then
    INSTALLED=1
    break
  fi
  sleep 5
done
if [[ $INSTALLED -eq 0 ]]; then
  echo "install failed on $UDID: $(tail -n 1 "$OUT/install.err")" >&2
  exit 1
fi
rm -f "$OUT/install.err"
xcrun simctl status_bar "$UDID" override --time 9:41 >/dev/null 2>&1 || true
for PAGE in "${PAGES[@]}"; do
  ARGS="$(launch_args_for "$PAGE")" || continue
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
  sleep 2
  LAUNCHED=0
  for ATTEMPT in 1 2 3; do
    # shellcheck disable=SC2086  # ARGS and LORVEX_WATCH_SIM_EXTRA_ARGS are space-separated argument lists.
    if xcrun simctl launch "$UDID" "$BUNDLE" -lorvexUIPreview $ARGS ${LORVEX_WATCH_SIM_EXTRA_ARGS:-} >/dev/null 2>"$OUT/launch_$PAGE.err"; then
      LAUNCHED=1
      break
    fi
    sleep 3
  done
  if [[ $LAUNCHED -eq 0 ]]; then
    echo "launch failed on $UDID for $PAGE: $(tail -n 1 "$OUT/launch_$PAGE.err")" >&2
    continue
  fi
  rm -f "$OUT/launch_$PAGE.err"
  sleep 7
  xcrun simctl io "$UDID" screenshot "$OUT/$PAGE.png" >/dev/null 2>&1 && echo "captured $PAGE"
done
echo "finished → $OUT (devices booted here: ${#BOOTED_HERE[@]}, shut down on exit)"
