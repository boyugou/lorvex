#!/usr/bin/env python3
"""Freeze the released baseline schema once the app is launched.

Pre-launch the schema is evolved the cheap way: edit ``schema/schema.sql`` (and
the Apple embedded copy) and regenerate ``checksums.lock`` with
``apps/apple/script/verify_migration_ladder.py --seed`` (Apple-owned), keeping the
canonical migration ladder (``schema/migrations/``) empty. That is safe only
while no install carries a database. The first public release pins the version-1
baseline onto real devices: from then on, re-seeding a released checksum makes
shipped installs either fail verification (they quarantine healthy data) or drift
silently, so the baseline and every already-released checksum entry are frozen
forever and schema changes happen ONLY by appending a numbered migration.

This gate enforces that split. It is GATED behind the ``launched`` sentinel in
``schema/migration_policy.json``:

* Dormant (``launched: false`` — the current pre-launch regime): prints an
  advisory line and returns 0. It does not touch or fight the ``--seed`` regen
  workflow.
* Armed (``launched: true``): fails if any checksum entry identity (name + sha)
  frozen at launch was changed or removed relative to the current
  ``checksums.lock``. New entries may be appended (that is exactly how a
  post-launch migration is registered); only
  mutation of an already-released entry is a violation.

``--release`` adds the archive-time rule: every current migration identity and
sync-payload contract must already be captured by ``--arm``. This keeps ordinary
post-launch development append-friendly while preventing an un-rearmed identity
from shipping.

Arm it at first public release with ``verify_schema_freeze.py --arm``: that flips
the sentinel to ``true`` and captures both the current ``checksums.lock`` entries
and the versioned sync-payload contract hashes into ``frozen_baseline``. Before
writing anything, ``--arm`` validates the current on-disk state against four
checks — this module's own freeze check, the canonical migration-ladder check,
the embed-parity check (the Apple embed must be byte-identical to the canonical
``schema/`` copies, replicating ``verify_schema_embed.sh``), and the sync-payload
contract/version/freeze check — and refuses to arm at all if any fails. That
makes ``--arm`` self-sufficient: a first freeze cannot bless a drifted embed or
payload contract, or launder a mutated released entry into the new frozen truth
even if the operator skipped ``verify_all.sh``. Re-run ``--arm`` before each
subsequent public release to fold newly shipping migration and payload-contract
versions into the frozen set. See
``docs/design/SCHEMA_OPTIMALITY.md`` -> "Migration model".
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import TypeVar

from verify_migration_ladder import (
    CANONICAL_DIR as CANONICAL_MIGRATIONS_DIR,
    LOCK_PATH as CANONICAL_LOCK_PATH,
    SCHEMA_SQL_PATH as CANONICAL_SCHEMA_SQL_PATH,
    ladder_violations,
    load_lock as load_canonical_lock,
    load_migration_files,
)
from verify_sync_payload_contract import (
    MANIFEST_DIR as PAYLOAD_CONTRACTS_DIR,
    VERSION_SOURCE_PATH as PAYLOAD_VERSION_SOURCE_PATH,
    frozen_contract_violations,
    inspect_contracts,
)

REPO_ROOT = Path(__file__).resolve().parents[3]
APPLE_ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = REPO_ROOT / "schema" / "migration_policy.json"
# The Apple app bundles a byte-identical copy of the canonical schema/ authority
# (schema.sql, checksums.lock, and the migration ladder). arm() re-proves that
# parity itself (embed_parity_violations, replicating verify_schema_embed.sh)
# before it freezes, so a first freeze can never bless a drifted embed; these are
# the Apple-side copies it reads.
APPLE_RESOURCES_DIR = APPLE_ROOT / "Sources" / "LorvexCore" / "Resources"
LOCK_PATH = APPLE_RESOURCES_DIR / "checksums.lock"
APPLE_SCHEMA_SQL_PATH = APPLE_RESOURCES_DIR / "schema.sql"
APPLE_MIGRATIONS_DIR = APPLE_RESOURCES_DIR / "Migrations"

REMEDIATION = (
    "Do NOT re-seed a released baseline checksum. Revert schema/schema.sql to the "
    "frozen baseline and evolve the schema by APPENDING a numbered migration: add "
    "schema/migrations/NNN_<name>.sql and a new NNN entry to checksums.lock (never "
    "touch 001 or any already-released entry), then mirror both into the Apple "
    "embedded copies. See schema/migrations/README.md and "
    "docs/design/SCHEMA_OPTIMALITY.md -> \"Migration model\"."
)


def load_policy(path: Path = POLICY_PATH) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def load_lock_entries(path: Path = LOCK_PATH) -> dict[str, dict[str, str]]:
    """Return each migration's complete frozen identity from ``checksums.lock``."""
    raw = json.loads(path.read_text(encoding="utf-8"))
    return {
        version: {"name": entry["name"], "sha256": entry["sha256"]}
        for version, entry in raw.items()
    }


def freeze_violations(
    policy: dict, current_lock: dict[str, dict[str, str]]
) -> list[str]:
    """Return freeze violations for ``policy`` against ``current_lock``.

    An empty list means the tree is clean. Dormant policy (``launched`` falsy)
    always returns ``[]`` — the check is a no-op until the launch sentinel is
    flipped, so it can never break the pre-launch ``--seed`` regen workflow.

    Armed policy (``launched`` truthy) treats every entry captured in
    ``frozen_baseline.checksums_lock`` as immutable: a frozen entry that is
    missing or whose name or sha changed in ``current_lock`` is a violation. Entries
    present in ``current_lock`` but absent from the frozen set are appended
    migrations and are allowed.
    """
    if not policy.get("launched", False):
        return []

    frozen = (policy.get("frozen_baseline") or {}).get("checksums_lock")
    if not frozen:
        return [
            "migration_policy.json is launched but frozen_baseline.checksums_lock is "
            "empty. Run `apps/apple/script/verify_schema_freeze.py --arm` to freeze "
            "the shipped baseline before arming."
        ]

    violations: list[str] = []
    for version in sorted(frozen):
        frozen_entry = frozen[version]
        current_entry = current_lock.get(version)
        if current_entry is None:
            violations.append(
                f"released checksum entry {version} was removed from checksums.lock "
                f"(frozen identity {frozen_entry!r}). A shipped baseline/migration "
                f"identity cannot be dropped. {REMEDIATION}"
            )
            continue
        if not (
            isinstance(frozen_entry, dict)
            and isinstance(frozen_entry.get("name"), str)
            and isinstance(frozen_entry.get("sha256"), str)
        ):
            violations.append(
                f"migration_policy.json frozen checksum entry {version} must contain "
                f"the released name and sha256. Run the release audit before arming."
            )
            continue
        if not isinstance(current_entry, dict):
            violations.append(
                f"current checksums.lock entry {version} is not a name/sha256 object. "
                f"{REMEDIATION}"
            )
            continue
        if current_entry != frozen_entry:
            changed: list[str] = []
            if current_entry.get("name") != frozen_entry["name"]:
                changed.append(
                    f"name frozen as {frozen_entry['name']!r}, now {current_entry.get('name')!r}"
                )
            if current_entry.get("sha256") != frozen_entry["sha256"]:
                changed.append(
                    "sha256 frozen as "
                    f"{frozen_entry['sha256'][:16]}..., now "
                    f"{str(current_entry.get('sha256'))[:16]}..."
                )
            violations.append(
                f"released checksum entry {version} changed ({'; '.join(changed)}). "
                "Shipped installs carry the frozen migration identity; mutating it can "
                "lock them out or erase trustworthy migration provenance. "
                f"{REMEDIATION}"
            )
    return violations


def release_coverage_violations(
    policy: dict,
    current_lock: dict[str, dict[str, str]],
    current_payload_contracts: dict[str, str],
) -> list[str]:
    """Return current identities that have not yet been captured by ``--arm``.

    Normal post-launch development deliberately permits append-only migration
    and payload versions before the next release is cut. A distributable archive
    is stricter: every identity it can ship must already be in the frozen policy,
    otherwise a later rename could pass the repository checks yet disagree with
    databases that applied the unrecorded release.
    """
    if not policy.get("launched", False):
        return []

    baseline = policy.get("frozen_baseline") or {}
    frozen_lock = baseline.get("checksums_lock") or {}
    frozen_payload_contracts = baseline.get("sync_payload_contracts") or {}
    violations = [
        f"release migration {version} is not captured in migration_policy.json. "
        "Run `apps/apple/script/verify_schema_freeze.py --arm` before archiving."
        for version in sorted(set(current_lock) - set(frozen_lock))
    ]
    violations += [
        f"release payload contract {version} is not captured in migration_policy.json. "
        "Run `apps/apple/script/verify_schema_freeze.py --arm` before archiving."
        for version in sorted(
            set(current_payload_contracts) - set(frozen_payload_contracts)
        )
    ]
    return violations


EMBED_REMEDIATION = (
    "Reconcile the Apple embed so it is byte-identical to the schema/ authority "
    "(run apps/apple/script/verify_schema_embed.sh) before arming. Arming freezes "
    "the shipped baseline permanently; a drifted embed frozen here would pin the "
    "wrong baseline onto real installs forever."
)


def _read_bytes_or_none(path: Path) -> bytes | None:
    try:
        return path.read_bytes()
    except FileNotFoundError:
        return None


def embed_parity_violations(
    canonical_schema_sql_path: Path,
    apple_schema_sql_path: Path,
    canonical_lock_path: Path,
    apple_lock_path: Path,
    canonical_migrations_dir: Path,
    apple_migrations_dir: Path,
) -> list[str]:
    """Return byte-parity violations between the canonical ``schema/`` authority
    and the Apple embed, replicating ``verify_schema_embed.sh``.

    The Apple app realizes ``schema/`` byte-for-byte, so ``schema.sql``,
    ``checksums.lock``, and every ``NNN_<name>.sql`` migration must be identical
    to their canonical source, and no Apple migration embed may exist without a
    canonical source (version ``001`` is the baseline ``schema.sql``, covered by
    the ``schema.sql`` comparison). An empty list means the embed is faithful.

    ``arm()`` runs this against the CURRENT on-disk state before freezing:
    ``verify_schema_freeze.py --arm`` only requires the freeze/ladder to be sound,
    but a first freeze captures the baseline permanently, so an embed that has
    silently drifted from canonical — a drift otherwise caught only by the
    separate ``verify_schema_embed.sh`` inside ``verify_all.sh`` — must block the
    arm rather than be blessed into the frozen truth.
    """
    violations: list[str] = []

    def compare(canonical: Path, embed: Path, label: str) -> None:
        canonical_bytes = _read_bytes_or_none(canonical)
        if canonical_bytes is None:
            violations.append(
                f"embed parity: canonical {label} is missing at {canonical}. {EMBED_REMEDIATION}"
            )
            return
        embed_bytes = _read_bytes_or_none(embed)
        if embed_bytes is None:
            violations.append(
                f"embed parity: Apple {label} embed is missing at {embed}. {EMBED_REMEDIATION}"
            )
            return
        if canonical_bytes != embed_bytes:
            violations.append(
                f"embed parity: Apple {label} embed ({embed}) is not byte-identical to the "
                f"canonical {canonical}. {EMBED_REMEDIATION}"
            )

    compare(canonical_schema_sql_path, apple_schema_sql_path, "schema.sql")
    compare(canonical_lock_path, apple_lock_path, "checksums.lock")

    # Every canonical migration (versions 002+; 001 is the baseline schema.sql)
    # must have a byte-identical Apple embed.
    for canonical_file in sorted(canonical_migrations_dir.glob("[0-9][0-9][0-9]_*.sql")):
        compare(
            canonical_file,
            apple_migrations_dir / canonical_file.name,
            f"migration {canonical_file.name}",
        )

    # No Apple migration embed may exist without a canonical source.
    for embed_file in sorted(apple_migrations_dir.glob("[0-9][0-9][0-9]_*.sql")):
        if embed_file.name == "001_schema.sql":
            continue
        if not (canonical_migrations_dir / embed_file.name).is_file():
            violations.append(
                f"embed parity: Apple migration embed {embed_file} has no canonical source at "
                f"{canonical_migrations_dir / embed_file.name}. {EMBED_REMEDIATION}"
            )

    return violations


class SchemaFreezeArmError(RuntimeError):
    """Raised by :func:`arm` when re-arming would bless a broken frozen state.

    ``violations`` carries the human-readable freeze/ladder/embed/payload
    violation messages so callers can report exactly what failed without
    re-deriving it. Raising this leaves ``migration_policy.json`` untouched.
    """

    def __init__(self, violations: list[str]) -> None:
        super().__init__("; ".join(violations))
        self.violations = violations


_Entry = TypeVar("_Entry")


def _contiguous_new_entries(
    prior_frozen: dict[str, _Entry], current_lock: dict[str, _Entry]
) -> dict[str, _Entry]:
    """``current_lock`` entries not yet in ``prior_frozen``, capped at the
    first version gap.

    Only a contiguous run immediately after the highest version already in
    ``prior_frozen`` is returned (starting at 1 when ``prior_frozen`` is
    empty): a later, out-of-sequence, or gapped version present in
    ``current_lock`` is excluded rather than folded in, so arming never
    freezes a version ahead of a gap even if some other validator missed it.
    """
    max_frozen = max((int(version) for version in prior_frozen), default=0)
    candidates = sorted(
        (int(version), version) for version in current_lock if version not in prior_frozen
    )
    new_entries: dict[str, _Entry] = {}
    expected = max_frozen + 1
    for version_int, version_key in candidates:
        if version_int != expected:
            break
        new_entries[version_key] = current_lock[version_key]
        expected += 1
    return new_entries


def arm(
    policy_path: Path = POLICY_PATH,
    lock_path: Path = LOCK_PATH,
    canonical_lock_path: Path = CANONICAL_LOCK_PATH,
    canonical_schema_sql_path: Path = CANONICAL_SCHEMA_SQL_PATH,
    canonical_migrations_dir: Path = CANONICAL_MIGRATIONS_DIR,
    apple_schema_sql_path: Path = APPLE_SCHEMA_SQL_PATH,
    apple_migrations_dir: Path = APPLE_MIGRATIONS_DIR,
    payload_contracts_dir: Path = PAYLOAD_CONTRACTS_DIR,
    payload_version_source_path: Path = PAYLOAD_VERSION_SOURCE_PATH,
) -> dict:
    """Flip the sentinel to launched and freeze the current checksums.lock.

    Arming is never a blind seed: BEFORE writing anything, four checks run
    against the CURRENT on-disk state, and any violation raises
    ``SchemaFreezeArmError`` and leaves ``migration_policy.json`` untouched:

    * this module's freeze check (``freeze_violations``, against the Apple lock
      at ``lock_path``),
    * the canonical migration-ladder check
      (``verify_migration_ladder.ladder_violations``, against
      ``canonical_lock_path``/``canonical_schema_sql_path``/
      ``canonical_migrations_dir``), and
    * the embed-parity check (``embed_parity_violations``): the Apple embed
      (``lock_path``, ``apple_schema_sql_path``, ``apple_migrations_dir``) must
      be byte-identical to the canonical ``schema/`` authority, and
    * the sync-payload contract check: manifests must be canonical and contiguous
      through ``LorvexVersion.payloadSchemaVersion``, and any previously released
      manifest must still match its frozen hash.

    The embed-parity check makes ``--arm`` self-sufficient even when invoked
    directly: without it a first arm could freeze a baseline whose shipped embed
    had silently drifted from canonical.

    This validation is UNCONDITIONAL — a FIRST arm (no prior
    ``frozen_baseline``) is checked too. A first arm captures the baseline
    permanently, so freezing a ``schema.sql`` whose checksum no longer matches
    lock entry ``001`` (or an otherwise malformed ladder, or a drifted embed)
    would pin a wrong baseline forever; these checks catch that before it can be
    blessed. The freeze check is a dormant no-op while the policy is still
    ``launched: false`` (a genuine first arm), so it adds signal without a
    false positive there; on a re-arm it also rejects any previously-frozen
    entry that was mutated on disk.

    Only entries genuinely new since the last arm are folded in, and only
    the contiguous run immediately following the previously-frozen max
    version (see ``_contiguous_new_entries``) — this keeps the frozen set
    itself always contiguous even if the on-disk lock momentarily isn't.
    Returns the written policy.
    """
    policy = load_policy(policy_path)
    current_lock = load_lock_entries(lock_path)
    prior_frozen = (policy.get("frozen_baseline") or {}).get("checksums_lock") or {}
    current_payload_contracts, payload_contract_violations = inspect_contracts(
        payload_contracts_dir, payload_version_source_path
    )
    prior_payload_contracts = (
        (policy.get("frozen_baseline") or {}).get("sync_payload_contracts") or {}
    )
    if not policy.get("launched", False):
        # A dormant sentinel carries no released state. Ignore a stale manually
        # populated value rather than blessing it into the first public freeze.
        prior_frozen = {}
        prior_payload_contracts = {}

    violations = freeze_violations(policy, current_lock)
    violations += ladder_violations(
        load_canonical_lock(canonical_lock_path),
        canonical_schema_sql_path.read_text(encoding="utf-8"),
        load_migration_files(canonical_migrations_dir),
        policy,
    )
    violations += embed_parity_violations(
        canonical_schema_sql_path,
        apple_schema_sql_path,
        canonical_lock_path,
        lock_path,
        canonical_migrations_dir,
        apple_migrations_dir,
    )
    violations += payload_contract_violations
    violations += frozen_contract_violations(policy, current_payload_contracts)
    if violations:
        raise SchemaFreezeArmError(violations)

    frozen_baseline = policy.get("frozen_baseline")
    if not isinstance(frozen_baseline, dict):
        frozen_baseline = {}
        policy["frozen_baseline"] = frozen_baseline
    updated_frozen = dict(prior_frozen)
    updated_frozen.update(_contiguous_new_entries(prior_frozen, current_lock))
    frozen_baseline["checksums_lock"] = updated_frozen
    updated_payload_contracts = dict(prior_payload_contracts)
    updated_payload_contracts.update(
        _contiguous_new_entries(prior_payload_contracts, current_payload_contracts)
    )
    frozen_baseline["sync_payload_contracts"] = updated_payload_contracts

    policy["launched"] = True
    policy_path.write_text(json.dumps(policy, indent=2) + "\n", encoding="utf-8")
    return policy


def main(argv: list[str]) -> int:
    if "--arm" in argv:
        try:
            policy = arm()
        except SchemaFreezeArmError as error:
            print(
                "schema-freeze arm REFUSED (the current on-disk state is not safe to "
                "freeze — a mutated frozen entry, a broken migration ladder, a "
                "drifted Apple embed, or an invalid sync payload contract):",
                file=sys.stderr,
            )
            for violation in error.violations:
                print(f"- {violation}", file=sys.stderr)
            return 1
        frozen = policy["frozen_baseline"]["checksums_lock"]
        payload_contracts = policy["frozen_baseline"]["sync_payload_contracts"]
        print(
            "schema-freeze tripwire ARMED: migration_policy.json launched=true; "
            f"froze {len(frozen)} released checksum entr"
            f"{'y' if len(frozen) == 1 else 'ies'} ({', '.join(sorted(frozen))}) and "
            f"{len(payload_contracts)} sync payload contract(s) "
            f"({', '.join(sorted(payload_contracts))})."
        )
        return 0

    policy = load_policy()
    current_lock = load_lock_entries()
    current_payload_contracts, payload_violations = inspect_contracts()
    payload_violations += frozen_contract_violations(policy, current_payload_contracts)

    if payload_violations:
        print("schema-freeze tripwire FAILED (sync payload contract drift):", file=sys.stderr)
        for violation in payload_violations:
            print(f"- {violation}", file=sys.stderr)
        return 1

    if not policy.get("launched", False):
        print(
            "schema-freeze tripwire DORMANT: migration_policy.json launched=false "
            "(pre-launch regime). schema.sql is freely editable and checksums.lock is "
            "regenerated with `apps/apple/script/verify_migration_ladder.py --seed`; the "
            "migration ladder stays empty. This gate arms at first public release via "
            "`verify_schema_freeze.py --arm`."
        )
        return 0

    violations = freeze_violations(policy, current_lock)
    if "--release" in argv:
        violations += release_coverage_violations(
            policy, current_lock, current_payload_contracts
        )
    if violations:
        print(
            "schema-freeze tripwire FAILED (post-launch identity drift or release not re-armed):",
            file=sys.stderr,
        )
        for violation in violations:
            print(f"- {violation}", file=sys.stderr)
        return 1

    frozen = policy["frozen_baseline"]["checksums_lock"]
    payload_contracts = policy["frozen_baseline"]["sync_payload_contracts"]
    coverage = (
        "release coverage complete."
        if "--release" in argv
        else "appended versions only."
    )
    print(
        f"schema-freeze tripwire PASS: {len(frozen)} released checksum "
        f"entr{'y' if len(frozen) == 1 else 'ies'} frozen and intact; "
        f"{len(payload_contracts)} released sync payload contract(s) frozen and intact; "
        f"{coverage}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
