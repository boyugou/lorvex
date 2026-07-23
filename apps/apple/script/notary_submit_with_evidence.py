#!/usr/bin/env python3
"""Submit one artifact to Apple's notary service and retain its evidence."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def run_notary_submission(
    artifact: Path,
    keychain_profile: str,
    evidence_prefix: Path,
    *,
    runner=subprocess.run,
) -> tuple[dict, dict]:
    submit = runner(
        [
            "xcrun",
            "notarytool",
            "submit",
            str(artifact),
            "--keychain-profile",
            keychain_profile,
            "--wait",
            "--output-format",
            "json",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    try:
        submit_payload = json.loads(submit.stdout)
    except json.JSONDecodeError as error:
        detail = submit.stderr.strip() or submit.stdout.strip()
        if submit.returncode != 0:
            raise RuntimeError(f"notarytool submit failed: {detail}") from error
        raise RuntimeError("notarytool submit returned invalid JSON") from error

    submission_id = submit_payload.get("id")
    status = submit_payload.get("status")
    if not isinstance(submission_id, str) or not submission_id:
        raise RuntimeError("notarytool submit result has no submission id")

    # Persist the service response before making any acceptance decision.  An
    # Invalid submission is precisely the case where the release operator needs
    # durable evidence, and notarytool still gives it a submission id whose log
    # explains the rejection.
    write_json_atomically(
        evidence_prefix.with_name(f"{evidence_prefix.name}-submit.json"),
        submit_payload,
    )

    log = runner(
        [
            "xcrun",
            "notarytool",
            "log",
            submission_id,
            "--keychain-profile",
            keychain_profile,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if log.returncode != 0:
        raise RuntimeError(
            "notarytool log failed: " + (log.stderr.strip() or log.stdout.strip())
        )
    try:
        log_payload = json.loads(log.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError("notarytool log returned invalid JSON") from error

    write_json_atomically(
        evidence_prefix.with_name(f"{evidence_prefix.name}-log.json"),
        log_payload,
    )

    if status != "Accepted":
        raise RuntimeError(f"notary submission was not accepted: {status!r}")
    if submit.returncode != 0:
        raise RuntimeError(
            "notarytool submit exited nonzero despite an Accepted response: "
            + (submit.stderr.strip() or str(submit.returncode))
        )
    if log_payload.get("status") != "Accepted":
        raise RuntimeError(
            f"notary log status is not Accepted: {log_payload.get('status')!r}"
        )
    errors = [
        issue
        for issue in (log_payload.get("issues") or [])
        if isinstance(issue, dict) and issue.get("severity") == "error"
    ]
    if errors:
        raise RuntimeError(f"notary log contains errors: {errors!r}")
    return submit_payload, log_payload


def write_json_atomically(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact", required=True, type=Path)
    parser.add_argument("--keychain-profile", required=True)
    parser.add_argument("--evidence-prefix", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.artifact.is_file():
        print(f"notary artifact not found: {args.artifact}", file=sys.stderr)
        return 2
    try:
        submit, _ = run_notary_submission(
            args.artifact,
            args.keychain_profile,
            args.evidence_prefix,
        )
    except RuntimeError as error:
        print(f"notarization failed: {error}", file=sys.stderr)
        return 1
    print(
        f"Notarization accepted: {args.artifact} "
        f"(submission {submit['id']})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
