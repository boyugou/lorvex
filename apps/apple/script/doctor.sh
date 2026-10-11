#!/usr/bin/env bash
# doctor.sh - checks that this Mac can build, test, and release Lorvex, and prints
# the fix for whatever it cannot. Read-only: it never prints a secret value and
# never changes the keychain, the simulators, or the repository.
#
# Usage:
#   script/doctor.sh              toolchain, repository identity, simulators
#   script/doctor.sh --release    also what a TestFlight upload needs: signing
#                                 identities, provisioning profiles, App Store
#                                 Connect credentials
#
# Exit status is 1 when any check fails, 0 otherwise (warnings do not fail).
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/../.." && pwd)"
SECRETS="$REPO_ROOT/secrets/apple-developer.env"
PROFILES_DIR="$ROOT_DIR/secrets/profiles"
CHECK_RELEASE=0
[[ "${1:-}" == "--release" ]] && CHECK_RELEASE=1

FAILURES=0
WARNINGS=0
ok() { printf '  ok    %s\n' "$1"; }
warn() { printf '  warn  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '          fix: %s\n' "$2"; WARNINGS=$((WARNINGS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '          fix: %s\n' "$2"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n%s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

xcode_major() {  # <Xcode.app> -> major version, empty when unreadable
  local version
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist" 2>/dev/null || true)"
  printf '%s' "${version%%.*}"
}

section "Toolchain"
sdk="$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || true)"
if [[ -z "$sdk" ]]; then
  bad "no iOS SDK is selected" "install Xcode 26 or later, then export DEVELOPER_DIR=<Xcode.app>/Contents/Developer"
elif (( ${sdk%%.*} < 26 )); then
  bad "the selected Xcode ships iOS SDK $sdk, below the App Store floor (26)" "export DEVELOPER_DIR=<an Xcode 26.x>/Contents/Developer"
else
  ok "selected Xcode: $(xcodebuild -version 2>/dev/null | head -1), iOS SDK $sdk, $(swift --version 2>&1 | sed -n 's/.*Swift version \([0-9.]*\).*/Swift \1/p' | head -1)"
fi
selected_major="$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null | cut -d. -f1)"
if [[ -n "$selected_major" ]] && (( selected_major >= 27 )); then
  for app in /Applications/Xcode*.app; do
    [[ -d "$app" && "$(xcode_major "$app")" == "26" ]] || continue
    warn "the selected Xcode is 27.x but $(basename "$app") is 26.x; the pipeline targets Xcode 26" \
      "export DEVELOPER_DIR=$app/Contents/Developer"
    break
  done
fi
for tool in uv xcodegen gh python3; do
  if have "$tool"; then ok "$tool is installed"; else bad "$tool is missing" "brew install $tool"; fi
done

section "Repository"
email="$(git -C "$REPO_ROOT" config user.email 2>/dev/null || true)"
if [[ "$email" == *"@users.noreply.github.com" ]]; then
  ok "commits use a GitHub noreply address"
else
  bad "git user.email is not a GitHub noreply address" \
    "git config --local user.email '<id>+<user>@users.noreply.github.com'"
fi
if have gh && gh auth status 2>&1 | grep -q 'Active account: true'; then
  ok "gh is signed in"
else
  warn "gh is not signed in" "gh auth login"
fi

section "Simulators"
simctl_list="$(xcrun simctl list devices available 2>/dev/null || true)"
for name in "iPhone 17 Pro" "iPad Pro 13-inch (M5)" "Apple Watch Series 11 (46mm)"; do
  count="$(grep -c -F "    $name (" <<<"$simctl_list" || true)"
  if [[ "$count" == "0" ]]; then
    warn "no simulator named '$name'" "Xcode > Settings > Components, or xcrun simctl create"
  elif [[ "$count" != "1" ]]; then
    warn "$count simulators share the name '$name' (several runtimes)" \
      "pass LORVEX_SIM_UDID or LORVEX_WATCH_SIM_UDID, choosing the device on the iOS/watchOS 26 runtime"
  else
    ok "simulator '$name'"
  fi
done

if (( CHECK_RELEASE == 1 )); then
  section "Release credentials (names and states only, never values)"
  if [[ ! -f "$SECRETS" ]]; then
    bad "secrets/apple-developer.env is missing" "copy it from the previous development machine"
  else
    for name in APPLE_ID APPLE_PASSWORD APPLE_TEAM_ID MAS_APP_SIGN_IDENTITY MAS_INSTALLER_SIGN_IDENTITY ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH; do
      if grep -q "^export $name=" "$SECRETS"; then ok "$name is defined"; else bad "$name is not defined in secrets/apple-developer.env"; fi
    done
    # Read the identities and the key path in a subshell; print only verdicts.
    # shellcheck disable=SC1090
    eval "$( (set -a; source "$SECRETS" >/dev/null 2>&1; set +a
      printf 'APP_IDENTITY=%q\nPKG_IDENTITY=%q\nKEY_PATH=%q\n' \
        "${MAS_APP_SIGN_IDENTITY:-}" "${MAS_INSTALLER_SIGN_IDENTITY:-}" "${ASC_KEY_PATH:-}") )"

    valid="$(security find-identity -v 2>/dev/null || true)"
    all_identities="$(security find-identity 2>/dev/null || true)"
    for pair in "Apple Distribution identity:$APP_IDENTITY" "Mac installer identity:$PKG_IDENTITY"; do
      label="${pair%%:*}"; identity="${pair#*:}"
      [[ -n "$identity" ]] || continue
      if grep -qF "\"$identity\"" <<<"$valid"; then
        ok "$label is valid in the keychain"
      elif grep -qF "\"$identity\"" <<<"$all_identities"; then
        bad "$label is in the keychain but not valid" \
          "install the Apple intermediates from Xcode: security add-certificates -k ~/Library/Keychains/login.keychain-db <Xcode.app>/Contents/SharedFrameworks/DVTFoundation.framework/Versions/A/Resources/{AppleWWDRCA-2030.cer,DeveloperIDCA-G2.cer}"
      else
        bad "$label is not in the keychain" "export the certificate with its private key from the previous Mac and import the .p12"
      fi
    done

    if [[ -n "$KEY_PATH" && -f "$KEY_PATH" ]]; then
      mode="$(stat -f '%Lp' "$KEY_PATH" 2>/dev/null || echo '?')"
      if [[ "$mode" == "600" || "$mode" == "400" ]]; then ok "App Store Connect key file is present and private"; else warn "App Store Connect key file mode is $mode" "chmod 600 <key file>"; fi
    elif [[ -n "$KEY_PATH" ]]; then
      bad "App Store Connect key file is missing at ASC_KEY_PATH" "place the AuthKey_<id>.p8 there"
    fi
  fi

  for profile in LorvexApple LorvexMCPHost LorvexWidgets; do
    file="$PROFILES_DIR/$profile.provisionprofile"
    if [[ ! -f "$file" ]]; then
      bad "provisioning profile $profile.provisionprofile is missing" "download it from the Apple Developer portal into apps/apple/secrets/profiles/"
      continue
    fi
    expiry="$(security cms -D -i "$file" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null || true)"
    if [[ -z "$expiry" ]]; then
      warn "cannot read the expiry of $profile.provisionprofile"
    else
      expiry_epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expiry" +%s 2>/dev/null || echo 0)"
      days_left=$(( (expiry_epoch - $(date +%s)) / 86400 ))
      if (( days_left < 0 )); then bad "$profile.provisionprofile expired" "regenerate it in the Apple Developer portal";
      elif (( days_left < 30 )); then warn "$profile.provisionprofile expires in $days_left days" "regenerate it in the Apple Developer portal";
      else ok "$profile.provisionprofile valid for $days_left more days"; fi
    fi
  done

  if xcrun --find altool >/dev/null 2>&1; then ok "altool is available"; else bad "altool is missing" "install Xcode 26.x"; fi
fi

printf '\ndoctor: %d failure(s), %d warning(s)\n' "$FAILURES" "$WARNINGS"
(( FAILURES == 0 ))
