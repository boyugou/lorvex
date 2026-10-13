#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyjwt", "cryptography"]
# ///
"""Lists the crash reports TestFlight testers submitted for Lorvex and saves each log.

A tester who taps "Share" on TestFlight's "Did Lorvex crash?" prompt creates a crash
submission, and App Store Connect keeps its crash log, which is the only crash log
available for a TestFlight build (the Organizer shows nothing until enough users
report). The script prints, for each submission, the date, device, OS, build, and
the crash log's exception and termination lines, and writes the whole log to
<out-dir>/crash-<date>-<id>.crash. A submission whose log App Store Connect no longer
holds is listed without one.

    uv run script/testflight_crashes.py <out-dir>

Reads the key from ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH (the variable names
in secrets/apple-developer.env; export them first). Read-only: it never prints the
key, a token, or a tester's address.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.lorvex.apple"
LOG_LINES = (
    "Version:",
    "Hardware Model:",
    "Date/Time:",
    "Launch Time:",
    "Exception Type:",
    "Exception Codes:",
    "Termination Reason:",
    "Triggered by Thread:",
)


def token() -> str:
    now = int(time.time())
    with open(os.environ["ASC_KEY_PATH"], "rb") as handle:
        key = handle.read()
    claims = {
        "iss": os.environ["ASC_ISSUER_ID"],
        "iat": now,
        "exp": now + 600,
        "aud": "appstoreconnect-v1",
    }
    headers = {"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}
    return jwt.encode(claims, key, algorithm="ES256", headers=headers)


def get(path: str) -> tuple[int, dict]:
    request = urllib.request.Request(API + path, headers={"Authorization": "Bearer " + token()})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        try:
            return error.code, json.load(error)
        except ValueError:
            return error.code, {}


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    out_dir = sys.argv[1]
    for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"):
        if not os.environ.get(name):
            print(f"{name} is not set")
            return 2

    status, body = get(f"/v1/apps?filter[bundleId]={BUNDLE_ID}&fields[apps]=name")
    if status != 200 or not body.get("data"):
        print(f"cannot find the app: HTTP {status}")
        return 1
    app_id = body["data"][0]["id"]

    query = urllib.parse.urlencode(
        {"limit": 50, "sort": "-createdDate", "include": "build", "fields[builds]": "version"}
    )
    status, body = get(f"/v1/apps/{app_id}/betaFeedbackCrashSubmissions?{query}")
    if status != 200:
        print(f"crash submissions: HTTP {status}")
        return 1
    submissions = body.get("data", [])
    build_numbers = {
        included["id"]: included["attributes"].get("version")
        for included in body.get("included", [])
        if included.get("type") == "builds"
    }
    print(f"{len(submissions)} crash submission(s)")
    os.makedirs(out_dir, exist_ok=True)

    for item in submissions:
        attrs = item["attributes"]
        created = str(attrs.get("createdDate"))[:19]
        build_id = ((item.get("relationships") or {}).get("build") or {}).get("data") or {}
        print(
            f"\n- {created}  build {build_numbers.get(build_id.get('id'), '?')}"
            f"  {attrs.get('deviceModel')}  OS {attrs.get('osVersion')}  {attrs.get('appPlatform')}"
        )
        if attrs.get("comment"):
            print("  comment:", attrs["comment"][:300])
        status, log = get(f"/v1/betaFeedbackCrashSubmissions/{item['id']}/crashLog")
        if status != 200:
            print(f"  no crash log (HTTP {status})")
            continue
        text = log["data"]["attributes"].get("logText") or ""
        path = os.path.join(out_dir, f"crash-{created.replace(':', '')}-{item['id'][:8]}.crash")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        for line in text.splitlines():
            if line.strip().startswith(LOG_LINES):
                print("  ", line.strip()[:160])
        print("   saved", path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
