from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from verify_core_service_coverage import service_coverage_failures


class CoreServiceCoverageTests(unittest.TestCase):
    def test_complete_service_passes(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            services = Path(tempdir)
            self.write_minimal_sources(
                services,
                swift_methods=["requiredMethod", "extendedMethod"],
            )

            self.assertEqual(service_coverage_failures(services), [])

    def test_missing_required_protocol_method_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            services = Path(tempdir)
            self.write_minimal_sources(
                services,
                swift_methods=["requiredMethod"],
            )

            failures = service_coverage_failures(services)

            self.assertTrue(any("SwiftLorvexCoreService" in failure for failure in failures))
            self.assertTrue(any("extendedMethod" in failure for failure in failures))

    def test_missing_unsupported_default_override_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            services = Path(tempdir)
            self.write_minimal_sources(
                services,
                swift_methods=["requiredMethod"],
            )

            failures = service_coverage_failures(services)

            self.assertTrue(any("unsupported default" in failure for failure in failures))
            self.assertTrue(any("extendedMethod" in failure for failure in failures))

    def test_non_protocol_helpers_are_not_service_requirements(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            services = Path(tempdir)
            self.write_minimal_sources(
                services,
                swift_methods=["requiredMethod", "extendedMethod"],
            )
            protocol_path = services / "LorvexTaskServicing.swift"
            protocol_path.write_text(
                """
                public enum ProtocolAdjacentHelper {
                  public static func helperMethod() -> String { "helper" }
                }

                public protocol LorvexTaskServicing {
                  func requiredMethod() async throws -> String
                  func extendedMethod() async throws -> String
                }
                """,
                encoding="utf-8",
            )

            self.assertEqual(service_coverage_failures(services), [])

    def write_minimal_sources(
        self,
        services: Path,
        *,
        swift_methods: list[str],
    ) -> None:
        (services / "LorvexTaskServicing.swift").write_text(
            """
            public protocol LorvexTaskServicing {
              func requiredMethod() async throws -> String
              func extendedMethod() async throws -> String
            }
            """,
            encoding="utf-8",
        )
        (services / "LorvexTaskServicing+Defaults.swift").write_text(
            """
            extension LorvexTaskServicing {
              public func extendedMethod() async throws -> String {
                throw LorvexCoreError.unsupportedServiceOperation("extendedMethod")
              }
            }
            """,
            encoding="utf-8",
        )
        (services / "SwiftLorvexCoreService.swift").write_text(
            self.implementation_source("SwiftLorvexCoreService", swift_methods),
            encoding="utf-8",
        )

    def implementation_source(self, type_name: str, methods: list[str]) -> str:
        body = "\n".join(
            f"  public func {method}() async throws -> String {{ \"ok\" }}" for method in methods
        )
        return f"public struct {type_name} {{\n{body}\n}}\n"


if __name__ == "__main__":
    unittest.main()
