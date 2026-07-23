#!/usr/bin/env python3
from __future__ import annotations

import unittest

from verify_mas_release_readiness import (
    base_entitlements_failures,
    helper_entitlements_failures,
    mas_entitlements_failures,
    provisioning_profile_wiring_failures,
    release_build_configuration_failures,
    release_readiness_failures,
)


class VerifyMasReleaseReadinessTests(unittest.TestCase):
    def test_mas_entitlements_accept_required_app_store_cloudkit_fields(self) -> None:
        self.assertEqual(
            mas_entitlements_failures(
                {
                    "com.apple.security.app-sandbox": True,
                    "com.apple.security.application-groups": ["group.com.lorvex.apple"],
                    "com.apple.security.files.user-selected.read-write": True,
                    "com.apple.security.personal-information.calendars": True,
                    "com.apple.developer.icloud-container-identifiers": [
                        "iCloud.com.lorvex.apple"
                    ],
                    "com.apple.developer.icloud-services": ["CloudKit"],
                    "com.apple.developer.icloud-container-environment": "Production",
                    "com.apple.developer.aps-environment": "production",
                },
                "group.com.lorvex.apple",
                "iCloud.com.lorvex.apple",
            ),
            [],
        )

    def test_mas_entitlements_reject_non_production_cloudkit_template(self) -> None:
        failures = mas_entitlements_failures(
            {
                "com.apple.security.app-sandbox": True,
                "com.apple.security.application-groups": ["group.com.lorvex.apple"],
                "com.apple.security.files.user-selected.read-write": True,
                "com.apple.security.personal-information.calendars": True,
                "com.apple.developer.icloud-container-identifiers": ["iCloud.com.other"],
                "com.apple.developer.icloud-services": ["Documents"],
                "com.apple.developer.aps-environment": "development",
            },
            "group.com.lorvex.apple",
            "iCloud.com.lorvex.apple",
        )

        self.assertEqual(
            failures,
            [
                "MAS entitlements missing CloudKit container 'iCloud.com.lorvex.apple'",
                "MAS entitlements missing CloudKit iCloud service",
                "MAS entitlements must declare com.apple.developer.icloud-container-environment "
                "= 'Production'",
                "MAS entitlements must use com.apple.developer.aps-environment 'production'",
            ],
        )

    def test_base_entitlements_reject_cloudkit_or_push_keys(self) -> None:
        self.assertEqual(
            base_entitlements_failures(
                {
                    "com.apple.developer.icloud-container-identifiers": [
                        "iCloud.com.lorvex.apple"
                    ],
                    "com.apple.developer.icloud-container-environment": "Production",
                    "com.apple.developer.aps-environment": "production",
                    "aps-environment": "production",
                }
            ),
            [
                "base macOS entitlements unexpectedly include production-only key "
                "'com.apple.developer.icloud-container-identifiers'",
                "base macOS entitlements unexpectedly include production-only key "
                "'com.apple.developer.icloud-container-environment'",
                "base macOS entitlements unexpectedly include production-only key "
                "'com.apple.developer.aps-environment'",
                "base macOS entitlements unexpectedly include production-only key "
                "'aps-environment'",
            ],
        )

    def test_helper_entitlements_accept_sandbox_and_app_group_only(self) -> None:
        self.assertEqual(
            helper_entitlements_failures(
                {
                    "com.apple.security.app-sandbox": True,
                    "com.apple.security.application-groups": ["group.com.lorvex.apple"],
                },
                "group.com.lorvex.apple",
            ),
            [],
        )

    def test_helper_entitlements_reject_missing_sandbox_and_group(self) -> None:
        self.assertEqual(
            helper_entitlements_failures({}, "group.com.lorvex.apple"),
            [
                "MCP helper entitlements must enable app sandbox",
                "MCP helper entitlements missing app group 'group.com.lorvex.apple'",
            ],
        )

    def test_helper_entitlements_reject_unexpected_keys(self) -> None:
        self.assertEqual(
            helper_entitlements_failures(
                {
                    "com.apple.security.app-sandbox": True,
                    "com.apple.security.application-groups": ["group.com.lorvex.apple"],
                    "com.apple.security.files.user-selected.read-write": True,
                    "com.apple.security.files.bookmarks.app-scope": True,
                },
                "group.com.lorvex.apple",
            ),
            [
                "MCP helper entitlements declare unexpected key(s): "
                "['com.apple.security.files.bookmarks.app-scope', "
                "'com.apple.security.files.user-selected.read-write']"
            ],
        )

    def test_release_build_configuration_accepts_wired_up_scripts(self) -> None:
        self.assertEqual(
            release_build_configuration_failures(
                package_local_text=(
                    'export LORVEX_BUILD_CONFIGURATION="${LORVEX_BUILD_CONFIGURATION:-release}"'
                ),
                build_and_run_text=(
                    'BUILD_CONFIGURATION="${LORVEX_BUILD_CONFIGURATION:-debug}"\n'
                    'swift build -c "$BUILD_CONFIGURATION" --product "$APP_PRODUCT_NAME"\n'
                    'SWIFT_BIN_PATH="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"\n'
                ),
            ),
            [],
        )

    def test_release_build_configuration_rejects_debug_only_packaging(self) -> None:
        failures = release_build_configuration_failures(
            package_local_text="./script/build_and_run.sh --stage-only",
            build_and_run_text='swift build --product "$APP_PRODUCT_NAME"\n',
        )

        self.assertEqual(
            failures,
            [
                "package_local.sh does not default LORVEX_BUILD_CONFIGURATION to release",
                "build_and_run.sh missing release-config marker "
                '\'BUILD_CONFIGURATION="${LORVEX_BUILD_CONFIGURATION:-debug}"\'',
                "build_and_run.sh missing release-config marker "
                '\'swift build -c "$BUILD_CONFIGURATION"\'',
                "build_and_run.sh missing release-config marker '--show-bin-path'",
            ],
        )

    def test_provisioning_profile_wiring_accepts_fully_wired_scripts(self) -> None:
        self.assertEqual(
            provisioning_profile_wiring_failures(
                archive_script_text=(
                    '"$ROOT_DIR/script/verify_mas_provisioning.py" "$APP_BUNDLE"'
                ),
                sign_app_bundle_text=(
                    "APP_PROVISIONING_PROFILE\n"
                    "HELPER_PROVISIONING_PROFILE\n"
                    "WIDGET_PROVISIONING_PROFILE\n"
                    "embedded.provisionprofile\n"
                ),
            ),
            [],
        )

    def test_provisioning_profile_wiring_rejects_missing_verifier_call(self) -> None:
        failures = provisioning_profile_wiring_failures(
            archive_script_text="echo package done",
            sign_app_bundle_text=(
                "APP_PROVISIONING_PROFILE\n"
                "HELPER_PROVISIONING_PROFILE\n"
                "WIDGET_PROVISIONING_PROFILE\n"
                "embedded.provisionprofile\n"
            ),
        )
        self.assertEqual(
            failures,
            ["archive_mas.sh does not run verify_mas_provisioning.py"],
        )

    def test_provisioning_profile_wiring_rejects_missing_embed_support(self) -> None:
        failures = provisioning_profile_wiring_failures(
            archive_script_text='"$ROOT_DIR/script/verify_mas_provisioning.py" "$APP_BUNDLE"',
            sign_app_bundle_text="codesign --force --sign - \"$APP_BUNDLE\"",
        )
        self.assertEqual(
            failures,
            [
                "sign_app_bundle.sh missing provisioning-profile marker "
                "'APP_PROVISIONING_PROFILE'",
                "sign_app_bundle.sh missing provisioning-profile marker "
                "'HELPER_PROVISIONING_PROFILE'",
                "sign_app_bundle.sh missing provisioning-profile marker "
                "'WIDGET_PROVISIONING_PROFILE'",
                "sign_app_bundle.sh missing provisioning-profile marker "
                "'embedded.provisionprofile'",
            ],
        )

    def test_release_readiness_requires_human_gated_pending_items(self) -> None:
        self.assertEqual(
            release_readiness_failures(
                {
                    "ready": [
                        "mas_cloudkit_entitlement_template",
                        "mas_entitlement_verifier",
                    ],
                    "pending": [
                        "cloudkit_production_schema_promotion",
                        "app_store_connect_provisioning",
                    ],
                }
            ),
            [],
        )


if __name__ == "__main__":
    unittest.main()
