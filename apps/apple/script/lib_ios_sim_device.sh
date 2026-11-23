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

# clear_ios_sim_seeded_store <udid> <bundle id>
#   Deletes the app's store from the booted simulator's App Group container,
#   so the next launch with `-lorvexSeedSampleData` seeds today's sample day.
#   The seed only fills a store with no tasks in it, and the container
#   survives both a reinstall and `simctl uninstall`, so without this a run
#   shows whatever an earlier one seeded, however old. Refuses to delete
#   anything outside that simulator's device directory, and warns when the
#   app has no container yet (it was never installed on the device).
clear_ios_sim_seeded_store() {
  local udid="$1" bundle="$2" container
  container="$(xcrun simctl get_app_container "$udid" "$bundle" groups 2>/dev/null | awk '$1 == "group.com.lorvex.apple" { print $2 }')"
  case "$container" in
    */CoreSimulator/Devices/"$udid"/*) rm -rf "${container:?}/Lorvex" ;;
    "") echo "warning: no simulator App Group container; the run may show stale seed data" >&2 ;;
    *) echo "refusing to clear unexpected container path: $container" >&2; return 1 ;;
  esac
}
