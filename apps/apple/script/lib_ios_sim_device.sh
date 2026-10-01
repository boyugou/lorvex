#!/usr/bin/env bash
# Shared iOS-simulator device resolution for the headless QA scripts.
#
# resolve_ios_sim_udid <device name>
#   Prints the UDID to use. `LORVEX_SIM_UDID` wins when set; otherwise the
#   available device with that name on the NEWEST iOS runtime is chosen, so a
#   stale device from an older runtime (with an older app database) is never
#   picked by accident. Exits non-zero when no such device exists.
resolve_ios_sim_udid() {
  local name="$1"
  if [[ -n "${LORVEX_SIM_UDID:-}" ]]; then
    echo "$LORVEX_SIM_UDID"
    return 0
  fi
  xcrun simctl list devices available -j | python3 -c '
import json, re, sys
name = sys.argv[1]
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(int(part) for part in re.findall(r"\d+", runtime.rsplit(".iOS-", 1)[1]))
    for device in devices:
        if device["name"] == name and device.get("isAvailable", True):
            if best is None or version > best[0]:
                best = (version, device["udid"], runtime)
if best is None:
    sys.exit(1)
print(best[1])
print("using simulator %s (%s, iOS %s)" % (name, best[1], ".".join(map(str, best[0]))), file=sys.stderr)
' "$name"
}
