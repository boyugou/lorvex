#!/usr/bin/env bash
# Shared watchOS-simulator device resolution for the headless QA scripts.
#
# resolve_watch_sim_udid <device name>
#   Prints the UDID to use. `LORVEX_WATCH_SIM_UDID` wins when set; otherwise
#   the available device with that name on the NEWEST watchOS runtime is
#   chosen, so a stale device from an older runtime is never picked by
#   accident. Exits non-zero when no such device exists.
#
# paired_phone_udid <watch udid>
#   Prints the UDID of the iPhone simulator paired with that watch, or nothing
#   when the watch is unpaired. A watch simulator launches apps more reliably
#   when its phone is booted beside it.
resolve_watch_sim_udid() {
  local name="$1"
  if [[ -n "${LORVEX_WATCH_SIM_UDID:-}" ]]; then
    echo "$LORVEX_WATCH_SIM_UDID"
    return 0
  fi
  xcrun simctl list devices available -j | python3 -c '
import json, re, sys
name = sys.argv[1]
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if ".watchOS-" not in runtime:
        continue
    version = tuple(int(part) for part in re.findall(r"\d+", runtime.rsplit(".watchOS-", 1)[1]))
    for device in devices:
        if device["name"] == name and device.get("isAvailable", True):
            if best is None or version > best[0]:
                best = (version, device["udid"], runtime)
if best is None:
    sys.exit(1)
print(best[1])
print("using watch simulator %s (%s, watchOS %s)" % (name, best[1], ".".join(map(str, best[0]))), file=sys.stderr)
' "$name"
}

paired_phone_udid() {
  local watch="$1"
  xcrun simctl list pairs -j | python3 -c '
import json, sys
watch = sys.argv[1]
for pair in json.load(sys.stdin)["pairs"].values():
    if pair["watch"]["udid"] == watch:
        print(pair["phone"]["udid"])
        break
' "$watch"
}
