#!/usr/bin/env python3
"""Verify the canonical cross-runtime migration ladder (``schema/migrations/``).

The ladder is the single source for post-launch schema migrations: numbered
``NNN_<name>.sql`` files (versions 002+; version 001 is the baseline
``schema/schema.sql``) pinned by ``schema/migrations/checksums.lock`` (one
entry per version, ``sha256`` = the canonical *normalized* SQL digest). The
Apple app embeds a byte-identical copy — ``apps/apple/script/verify_schema_embed.sh``
enforces the Apple embed's byte parity; this gate enforces the semantic contract
on the canonical artifacts:

* the lock is well-formed: zero-padded keys, contiguous versions from 001,
  lowercase 64-hex shas, entry names shaped ``NNN_<snake_case>.sql``;
* entry ``001`` pins the baseline: its sha equals the normalized digest of
  ``schema/schema.sql``;
* every entry 002+ has a migration file whose normalized digest matches, and
  every ``.sql`` file present is recorded — a frozen file that was edited, or
  a file that was never locked, is a violation;
* the launch regime (``schema/migration_policy.json``) holds: while
  ``launched`` is false the ladder must be EMPTY (pre-launch schema changes
  edit ``schema.sql`` directly); once ``launched`` is true every entry frozen
  at launch must be intact and a ``schema.sql`` edit is rejected with the
  remediation "express the change as a new migration" (the freeze tripwire,
  ``verify_schema_freeze.py``, enforces the same append-only rule on the
  Apple lock copy).

The normalization here is Apple-owned. It matches the Swift
``MigrationSqlChecksum`` (the runtime authority) — both are pinned against the
same lock entries by their test suites, and this gate's baseline check re-pins
Python against the real ``schema.sql`` on every run. The Tauri Rust/Node digest
uses the same normalization convention but is a separate, directionally-aligned
implementation the Apple gate neither runs nor compares against.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SCHEMA_SQL_PATH = REPO_ROOT / "schema" / "schema.sql"
CANONICAL_DIR = REPO_ROOT / "schema" / "migrations"
LOCK_PATH = CANONICAL_DIR / "checksums.lock"
APPLE_EMBED_LOCK = (
    REPO_ROOT / "apps" / "apple" / "Sources" / "LorvexCore" / "Resources" / "checksums.lock"
)
POLICY_PATH = REPO_ROOT / "schema" / "migration_policy.json"

MIGRATION_NAME_RE = re.compile(r"^(\d{3})_([a-z0-9_]+)\.sql$")


def normalize_migration_sql(raw_text: str) -> str:
    """Normalize SQL for the canonical digest.

    Steps, in order (byte-for-byte the same contract as the Rust, Node, and
    Swift implementations): strip a UTF-8 BOM; replace CRLF with LF; strip SQL
    comments (``-- line`` and ``/* block */``) dropping lines left
    whitespace-only and trimming trailing whitespace before an inline comment;
    trim leading/trailing whitespace. Interior whitespace inside non-comment
    SQL is preserved so semantic edits cannot hide behind reformatting.
    """
    normalized = raw_text
    if normalized.startswith("\ufeff"):
        normalized = normalized[1:]
    normalized = normalized.replace("\r\n", "\n")
    return _strip_sql_comments(normalized).strip()


def _strip_sql_comments(sql: str) -> str:
    """Strip SQL comments while preserving string literals and identifiers.

    Per-line buffering: each line accumulates into ``pending`` until a newline
    (outside any literal) flushes it; a line with no non-whitespace content
    after comment removal is dropped entirely, including its newline. Quoted
    runs (``'`` literals, ``"`` identifiers) pass through verbatim — embedded
    newlines and ``--``/``/*`` markers included — with SQLite-style escaped
    quotes (``''`` / ``""``) keeping the run open. Block comments do not nest;
    an unterminated block runs to end-of-input.
    """
    out: list[str] = []
    pending: list[str] = []
    pending_has_content = False
    i = 0
    n = len(sql)

    def trim_pending_end() -> bool:
        while pending and pending[-1] in " \t\n\r\v\f":
            pending.pop()
        return bool(pending)

    while i < n:
        c = sql[i]

        if c == "\n":
            if pending_has_content:
                out.extend(pending)
                out.append("\n")
            pending.clear()
            pending_has_content = False
            i += 1
            continue

        if c in ("'", '"'):
            quote = c
            pending.append(quote)
            pending_has_content = True
            i += 1
            while i < n:
                pending.append(sql[i])
                if sql[i] == quote:
                    i += 1
                    if i < n and sql[i] == quote:
                        pending.append(sql[i])
                        i += 1
                        continue
                    break
                i += 1
            continue

        if c == "-" and i + 1 < n and sql[i + 1] == "-":
            if not trim_pending_end():
                pending_has_content = False
            i += 2
            while i < n and sql[i] != "\n":
                i += 1
            continue

        if c == "/" and i + 1 < n and sql[i + 1] == "*":
            if not trim_pending_end():
                pending_has_content = False
            i += 2
            while i + 1 < n and not (sql[i] == "*" and sql[i + 1] == "/"):
                i += 1
            i = i + 2 if i + 1 < n else n
            continue

        pending.append(c)
        if not c.isspace():
            pending_has_content = True
        i += 1

    if pending_has_content:
        out.extend(pending)
    return "".join(out)


def sha256_migration_hex(raw_text: str) -> str:
    """The canonical normalized SHA-256 of ``raw_text`` as lowercase hex."""
    return hashlib.sha256(normalize_migration_sql(raw_text).encode("utf-8")).hexdigest()


def load_lock(path: Path = LOCK_PATH) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def load_migration_files(directory: Path = CANONICAL_DIR) -> dict[str, str]:
    """``{file name: contents}`` for every ``.sql`` file in ``directory``."""
    if not directory.is_dir():
        return {}
    return {
        entry.name: entry.read_text(encoding="utf-8")
        for entry in sorted(directory.iterdir())
        if entry.is_file() and entry.name.endswith(".sql")
    }


# --- Ladder closure (permits destructive migrations) --------------------------
#
# Post-launch the frozen baseline is no longer replayed on open, so a numbered
# migration MAY drop a baseline object (a table, a column, an index, a trigger).
# What must hold instead is *closure*: after each migration, no surviving
# index / trigger / foreign key references an object the ladder has dropped. A
# migration that drops a table or column must, in the same migration, drop or
# rebuild every dependent object — otherwise a later open hits a dangling
# reference (`no such column`, `no such table`). This static check enforces
# that on the canonical ladder.
#
# The analysis is deliberately one-sided: a violation fires only when a
# surviving object references an object the ladder EXPLICITLY dropped, so
# imperfect SQL parsing can only miss a violation, never invent one. An empty
# ladder (the pre-launch regime) drops nothing, so the check is a guaranteed
# no-op there and on any additive-only ladder.

_IDENT = r'(?:"[^"]*"|[A-Za-z_][A-Za-z0-9_]*)'
_IDENT_RE = re.compile(_IDENT)
_STRING_RE = re.compile(r"'(?:[^']|'')*'")

# Words that show up as bare identifiers inside index/trigger expressions but
# are SQL keywords, not columns. Only cosmetic: a closure violation fires only
# on an identifier that equals an explicitly dropped column, so a stray keyword
# left in the reference set can never produce a false positive on its own.
_EXPR_KEYWORDS = frozenset(
    {
        "where", "and", "or", "not", "null", "is", "in", "like", "glob", "between",
        "asc", "desc", "collate", "nocase", "binary", "case", "when", "then",
        "else", "end", "cast", "as", "on", "using", "exists", "select", "from",
        "abs", "coalesce", "length", "lower", "upper", "strftime",
    }
)
_TABLE_CONSTRAINT_KEYWORDS = frozenset(
    {"constraint", "primary", "unique", "check", "foreign", "key"}
)


def _lower_ident(token: str) -> str:
    token = token.strip()
    if len(token) >= 2 and token[0] == '"' and token[-1] == '"':
        token = token[1:-1]
    return token.lower()


def _blank_string_literals(sql: str) -> str:
    """Replace single-quoted string literals with same-length blanks.

    Keeps every byte offset stable while removing literal contents, so the DDL
    scanners never mistake keywords inside a string (e.g. a logged message in a
    trigger body) for statements.
    """
    return _STRING_RE.sub(lambda m: " " * len(m.group(0)), sql)


def _prepare_ddl(sql: str) -> str:
    """Ready DDL for closure scanning: strip SQL comments FIRST (so a stray
    apostrophe inside a ``--``/``/* */`` comment can't open a phantom string
    literal), then blank genuine string literals."""
    return _blank_string_literals(_strip_sql_comments(sql))


def _balanced_parens(text: str, open_index: int) -> tuple[str, int]:
    """Return ``(inner, end)`` for the parenthesis group starting at
    ``open_index`` (which must be a ``'('``): ``inner`` is the content between
    the matching parens, ``end`` the index just past the closing ``')'``.
    Operates on already-blanked text, so quotes need no special handling."""
    depth = 0
    for i in range(open_index, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return text[open_index + 1 : i], i + 1
    return text[open_index + 1 :], len(text)


def _split_top_level_commas(body: str) -> list[str]:
    parts: list[str] = []
    depth = 0
    current: list[str] = []
    for c in body:
        if c == "(":
            depth += 1
            current.append(c)
        elif c == ")":
            depth -= 1
            current.append(c)
        elif c == "," and depth == 0:
            parts.append("".join(current))
            current = []
        else:
            current.append(c)
    if current:
        parts.append("".join(current))
    return parts


def _reference_idents(expr: str) -> set[str]:
    """Column-name candidates referenced by an index column list / WHERE clause
    or similar expression — every bare identifier minus the obvious keywords."""
    return {
        _lower_ident(token)
        for token in _IDENT_RE.findall(expr)
        if _lower_ident(token) not in _EXPR_KEYWORDS
    }


def _parse_create_table_body(body: str) -> tuple[set[str], set[str]]:
    """From a CREATE TABLE parenthesized body, return
    ``(column_names, foreign_key_target_tables)`` (both lowercased)."""
    columns: set[str] = set()
    for part in _split_top_level_commas(body):
        first = _IDENT_RE.match(part.strip())
        if first is None:
            continue
        name = _lower_ident(first.group(0))
        if name not in _TABLE_CONSTRAINT_KEYWORDS:
            columns.add(name)
    fk_targets = {
        _lower_ident(m.group(1))
        for m in re.finditer(r"\bREFERENCES\s+(" + _IDENT + r")", body, re.IGNORECASE)
    }
    return columns, fk_targets


_RE_CREATE_TABLE = re.compile(
    r"\bCREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(" + _IDENT + r")\s*\(", re.IGNORECASE
)
_RE_CREATE_INDEX = re.compile(
    r"\bCREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?(" + _IDENT + r")\s+ON\s+("
    + _IDENT
    + r")\s*\(",
    re.IGNORECASE,
)
_RE_CREATE_TRIGGER = re.compile(
    r"\bCREATE\s+(?:TEMP\s+|TEMPORARY\s+)?TRIGGER\s+(?:IF\s+NOT\s+EXISTS\s+)?"
    + _IDENT
    + r".*?\bON\s+("
    + _IDENT
    + r")\b",
    re.IGNORECASE | re.DOTALL,
)
_RE_TRIGGER_DDL_BOUNDARY = re.compile(
    r"\b(?:"
    r"CREATE\s+(?:(?:UNIQUE|TEMP|TEMPORARY)\s+)*(?:TABLE|INDEX|TRIGGER|VIRTUAL\s+TABLE)"
    r"|ALTER\s+TABLE"
    r"|DROP\s+(?:TABLE|INDEX|TRIGGER)"
    r")\b",
    re.IGNORECASE,
)
_RE_TRIGGER_TABLE_REFERENCE = re.compile(
    r"\b(?:"
    r"INSERT\s+(?:OR\s+(?:ROLLBACK|ABORT|REPLACE|FAIL|IGNORE)\s+)?INTO"
    r"|REPLACE\s+INTO"
    r"|UPDATE\s+(?:OR\s+(?:ROLLBACK|ABORT|REPLACE|FAIL|IGNORE)\s+)?"
    r"|DELETE\s+FROM"
    r"|FROM"
    r"|JOIN"
    r")\s+(?:(?:" + _IDENT + r")\s*\.\s*)?(" + _IDENT + r")",
    re.IGNORECASE,
)
_RE_TRIGGER_ROW_COLUMN_REFERENCE = re.compile(
    r"\b(?:OLD|NEW)\s*\.\s*(" + _IDENT + r")", re.IGNORECASE
)
_RE_TRIGGER_DEPENDENCY_TOKEN = re.compile(_IDENT + r"|[(),.;]")
_TRIGGER_FROM_BOUNDARIES = frozenset(
    {
        "except",
        "group",
        "having",
        "intersect",
        "limit",
        "order",
        "returning",
        "union",
        "where",
        "window",
    }
)
_TRIGGER_DERIVED_TABLE_STARTERS = frozenset({"select", "values", "with"})
_RE_DROP_TABLE = re.compile(
    r"\bDROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?(" + _IDENT + r")", re.IGNORECASE
)
_RE_DROP_INDEX = re.compile(
    r"\bDROP\s+INDEX\s+(?:IF\s+EXISTS\s+)?(" + _IDENT + r")", re.IGNORECASE
)
_RE_DROP_TRIGGER = re.compile(
    r"\bDROP\s+TRIGGER\s+(?:IF\s+EXISTS\s+)?(" + _IDENT + r")", re.IGNORECASE
)
_RE_ALTER = re.compile(
    r"\bALTER\s+TABLE\s+(" + _IDENT + r")\s+(.*?)(?=;|$)", re.IGNORECASE | re.DOTALL
)


def _trigger_from_clause_tables(body: str) -> set[str]:
    """Tables in ``FROM``/``JOIN`` sources, including comma-separated lists.

    This deliberately small token walk tracks one FROM clause per parenthesis
    depth. That lets nested SELECTs and derived tables coexist without treating
    commas in expressions or function arguments as table separators.
    """
    tokens = [match.group(0) for match in _RE_TRIGGER_DEPENDENCY_TOKEN.finditer(body)]
    tables: set[str] = set()
    # depth -> whether the clause is currently waiting for a table source.
    from_clauses: dict[int, bool] = {}
    depth = 0
    index = 0
    while index < len(tokens):
        raw = tokens[index]
        if raw == "(":
            waiting_for_source = from_clauses.get(depth, False)
            if waiting_for_source:
                from_clauses[depth] = False
            depth += 1
            if waiting_for_source:
                next_raw = tokens[index + 1] if index + 1 < len(tokens) else ""
                next_is_query = (
                    _IDENT_RE.fullmatch(next_raw) is not None
                    and not next_raw.startswith('"')
                    and _lower_ident(next_raw) in _TRIGGER_DERIVED_TABLE_STARTERS
                )
                if not next_is_query:
                    # SQLite also permits a parenthesized table group:
                    # FROM (table_a, table_b) or FROM (table_a JOIN table_b).
                    # Unlike a derived SELECT, its first token is a source.
                    from_clauses[depth] = True
            index += 1
            continue
        if raw == ")":
            from_clauses.pop(depth, None)
            depth = max(0, depth - 1)
            index += 1
            continue
        if raw == ";":
            from_clauses.pop(depth, None)
            index += 1
            continue

        is_identifier = _IDENT_RE.fullmatch(raw) is not None
        is_keyword = is_identifier and not raw.startswith('"')
        token = _lower_ident(raw) if is_identifier else raw
        if is_keyword and token == "from":
            from_clauses[depth] = True
        elif is_keyword and token in _TRIGGER_FROM_BOUNDARIES:
            from_clauses.pop(depth, None)
        elif is_keyword and token == "join" and depth in from_clauses:
            from_clauses[depth] = True
        elif raw == "," and depth in from_clauses:
            from_clauses[depth] = True
        elif is_identifier and from_clauses.get(depth):
            # SQLite permits schema-qualified SELECT sources in trigger bodies
            # (e.g. FROM main.audit_log); the dependency is the final name.
            if (
                index + 2 < len(tokens)
                and tokens[index + 1] == "."
                and _IDENT_RE.fullmatch(tokens[index + 2]) is not None
            ):
                index += 2
                raw = tokens[index]
            tables.add(_lower_ident(raw))
            from_clauses[depth] = False
        index += 1
    return tables


def _trigger_dependencies(text: str, match: re.Match[str]) -> tuple[set[str], set[str]]:
    """Tables and ``OLD``/``NEW`` columns referenced by one trigger body.

    ``match`` ends after the trigger's ``ON <table>`` header. Trigger bodies may
    contain ``CASE ... END`` expressions, so the final ``END;`` before the next
    top-level DDL statement is the trigger terminator; choosing the last one keeps
    those inner ``END`` tokens inside the scanned body.
    """
    next_ddl = _RE_TRIGGER_DDL_BOUNDARY.search(text, match.end())
    statement_end = next_ddl.start() if next_ddl is not None else len(text)
    remainder = text[match.end() : statement_end]
    terminators = list(re.finditer(r"\bEND\s*;", remainder, re.IGNORECASE))
    if terminators:
        remainder = remainder[: terminators[-1].start()]
    begin = re.search(r"\bBEGIN\b", remainder, re.IGNORECASE)
    body = remainder[begin.end() :] if begin is not None else remainder
    tables = {
        _lower_ident(reference.group(1))
        for reference in _RE_TRIGGER_TABLE_REFERENCE.finditer(body)
    }
    tables.update(_trigger_from_clause_tables(body))
    columns = {
        _lower_ident(reference.group(1))
        for reference in _RE_TRIGGER_ROW_COLUMN_REFERENCE.finditer(body)
    }
    return tables, columns


def _extract_ops(text: str) -> list[tuple[int, str, tuple]]:
    """Scan already-blanked DDL and return ``(position, kind, data)`` operations
    in source (execution) order."""
    ops: list[tuple[int, str, tuple]] = []
    for m in _RE_CREATE_TABLE.finditer(text):
        body, _ = _balanced_parens(text, m.end() - 1)
        ops.append((m.start(), "create_table", (_lower_ident(m.group(1)), body)))
    for m in _RE_CREATE_INDEX.finditer(text):
        body, after = _balanced_parens(text, m.end() - 1)
        semi = text.find(";", after)
        tail = text[after : semi if semi != -1 else len(text)]
        ops.append(
            (m.start(), "create_index", (_lower_ident(m.group(1)), _lower_ident(m.group(2)), body + " " + tail))
        )
    for m in _RE_CREATE_TRIGGER.finditer(text):
        # group(1) is the ON <table> capture; the trigger name is the first
        # identifier after CREATE [TEMP] TRIGGER [IF NOT EXISTS].
        body_tables, row_columns = _trigger_dependencies(text, m)
        ops.append(
            (
                m.start(),
                "create_trigger",
                (
                    _trigger_name(m.group(0)),
                    _lower_ident(m.group(1)),
                    body_tables,
                    row_columns,
                ),
            )
        )
    for m in _RE_DROP_TABLE.finditer(text):
        ops.append((m.start(), "drop_table", (_lower_ident(m.group(1)),)))
    for m in _RE_DROP_INDEX.finditer(text):
        ops.append((m.start(), "drop_index", (_lower_ident(m.group(1)),)))
    for m in _RE_DROP_TRIGGER.finditer(text):
        ops.append((m.start(), "drop_trigger", (_lower_ident(m.group(1)),)))
    for m in _RE_ALTER.finditer(text):
        ops.append((m.start(), "alter", (_lower_ident(m.group(1)), m.group(2))))
    ops.sort(key=lambda op: op[0])
    return ops


def _trigger_name(header: str) -> str:
    """The trigger name from a matched CREATE TRIGGER header."""
    m = re.match(
        r"\s*CREATE\s+(?:TEMP\s+|TEMPORARY\s+)?TRIGGER\s+(?:IF\s+NOT\s+EXISTS\s+)?("
        + _IDENT
        + r")",
        header,
        re.IGNORECASE,
    )
    return _lower_ident(m.group(1)) if m else header.strip().lower()


class _SchemaModel:
    """A minimal, approximate model of the realized schema — table/column
    existence and the reference edges (index → table/columns, trigger → table,
    table → foreign-key target tables) closure needs. Identifiers are lowercased
    (SQLite compares them case-insensitively)."""

    def __init__(self) -> None:
        self.tables: dict[str, set[str]] = {}
        self.indexes: dict[str, dict] = {}
        self.triggers: dict[str, dict] = {}
        self.fks: dict[str, set[str]] = {}
        self.dropped_tables: set[str] = set()
        self.dropped_columns: dict[str, set[str]] = {}

    def create_table(self, name: str, columns: set[str], fks: set[str]) -> None:
        self.tables[name] = set(columns)
        self.fks[name] = set(fks)
        self.dropped_tables.discard(name)
        self.dropped_columns.pop(name, None)

    def drop_table(self, name: str) -> None:
        self.tables.pop(name, None)
        self.fks.pop(name, None)
        self.dropped_columns.pop(name, None)
        self.dropped_tables.add(name)
        # SQLite drops a table's own indexes and triggers with it.
        for iname in [n for n, idx in self.indexes.items() if idx["table"] == name]:
            del self.indexes[iname]
        for tname in [
            n for n, trigger in self.triggers.items() if trigger["table"] == name
        ]:
            del self.triggers[tname]

    def add_column(self, table: str, column: str) -> None:
        self.tables.setdefault(table, set()).add(column)
        self.dropped_columns.get(table, set()).discard(column)

    def drop_column(self, table: str, column: str) -> None:
        self.tables.get(table, set()).discard(column)
        self.dropped_columns.setdefault(table, set()).add(column)

    def rename_table(self, old: str, new: str) -> None:
        self.tables[new] = self.tables.pop(old, set())
        self.fks[new] = self.fks.pop(old, set())
        self.dropped_columns[new] = self.dropped_columns.pop(old, set())
        self.dropped_tables.discard(new)
        for idx in self.indexes.values():
            if idx["table"] == old:
                idx["table"] = new
        for trigger in self.triggers.values():
            if trigger["table"] == old:
                trigger["table"] = new
            if old in trigger["body_tables"]:
                trigger["body_tables"].discard(old)
                trigger["body_tables"].add(new)
        for targets in self.fks.values():
            if old in targets:
                targets.discard(old)
                targets.add(new)

    def rename_column(self, table: str, old: str, new: str) -> None:
        cols = self.tables.get(table, set())
        if old in cols:
            cols.discard(old)
            cols.add(new)
        dropped = self.dropped_columns.get(table)
        if dropped:
            dropped.discard(old)
        for idx in self.indexes.values():
            if idx["table"] == table and old in idx["columns"]:
                idx["columns"].discard(old)
                idx["columns"].add(new)
        for trigger in self.triggers.values():
            if trigger["table"] == table and old in trigger["row_columns"]:
                trigger["row_columns"].discard(old)
                trigger["row_columns"].add(new)

    def create_index(self, name: str, table: str, columns: set[str]) -> None:
        self.indexes[name] = {"table": table, "columns": set(columns)}

    def drop_index(self, name: str) -> None:
        self.indexes.pop(name, None)

    def create_trigger(
        self, name: str, table: str, body_tables: set[str], row_columns: set[str]
    ) -> None:
        self.triggers[name] = {
            "table": table,
            "body_tables": set(body_tables),
            "row_columns": set(row_columns),
        }

    def drop_trigger(self, name: str) -> None:
        self.triggers.pop(name, None)


def _apply_ops(model: _SchemaModel, ops: list[tuple[int, str, tuple]]) -> None:
    for _, kind, data in ops:
        if kind == "create_table":
            columns, fks = _parse_create_table_body(data[1])
            model.create_table(data[0], columns, fks)
        elif kind == "create_index":
            model.create_index(data[0], data[1], _reference_idents(data[2]))
        elif kind == "create_trigger":
            model.create_trigger(data[0], data[1], data[2], data[3])
        elif kind == "drop_table":
            model.drop_table(data[0])
        elif kind == "drop_index":
            model.drop_index(data[0])
        elif kind == "drop_trigger":
            model.drop_trigger(data[0])
        elif kind == "alter":
            _apply_alter(model, data[0], data[1])


def _apply_alter(model: _SchemaModel, table: str, action: str) -> None:
    action = action.strip()
    m = re.match(r"RENAME\s+TO\s+(" + _IDENT + r")", action, re.IGNORECASE)
    if m:
        model.rename_table(table, _lower_ident(m.group(1)))
        return
    m = re.match(
        r"RENAME\s+(?:COLUMN\s+)?(" + _IDENT + r")\s+TO\s+(" + _IDENT + r")",
        action,
        re.IGNORECASE,
    )
    if m:
        model.rename_column(table, _lower_ident(m.group(1)), _lower_ident(m.group(2)))
        return
    m = re.match(r"DROP\s+(?:COLUMN\s+)?(" + _IDENT + r")", action, re.IGNORECASE)
    if m:
        model.drop_column(table, _lower_ident(m.group(1)))
        return
    m = re.match(r"ADD\s+(?:COLUMN\s+)?(" + _IDENT + r")", action, re.IGNORECASE)
    if m:
        model.add_column(table, _lower_ident(m.group(1)))


def _closure_violations_for(model: _SchemaModel, version: int) -> list[str]:
    """Dangling references after ``version`` applied. Reported objects are
    healed out of the model so a persistent break is reported once, at the
    version that introduced it, not re-reported at every later version."""
    out: list[str] = []
    for iname in sorted(model.indexes):
        idx = model.indexes[iname]
        table = idx["table"]
        if table in model.dropped_tables:
            out.append(
                f"migration {version:03d}: index {iname} references table {table}, which the "
                f"ladder dropped. Drop or rebuild {iname} in the same migration."
            )
            del model.indexes[iname]
            continue
        dangling = sorted(idx["columns"] & model.dropped_columns.get(table, set()))
        if dangling:
            cols = ", ".join(f"{table}.{c}" for c in dangling)
            out.append(
                f"migration {version:03d}: index {iname} still references dropped column(s) "
                f"{cols}. Drop or rebuild {iname} in the same migration."
            )
            del model.indexes[iname]
    for tname in sorted(model.triggers):
        trigger = model.triggers[tname]
        table = trigger["table"]
        if table in model.dropped_tables:
            out.append(
                f"migration {version:03d}: trigger {tname} references table {table}, which the "
                f"ladder dropped. Drop or rebuild {tname} in the same migration."
            )
            del model.triggers[tname]
            continue
        dangling_tables = sorted(trigger["body_tables"] & model.dropped_tables)
        if dangling_tables:
            targets = ", ".join(dangling_tables)
            out.append(
                f"migration {version:03d}: trigger {tname} body references dropped table "
                f"{targets}. Drop or rebuild {tname} in the same migration."
            )
            del model.triggers[tname]
            continue
        dangling_columns = sorted(
            trigger["row_columns"] & model.dropped_columns.get(table, set())
        )
        if dangling_columns:
            columns = ", ".join(f"{table}.{column}" for column in dangling_columns)
            out.append(
                f"migration {version:03d}: trigger {tname} still references dropped column(s) "
                f"{columns} through OLD/NEW. Drop or rebuild {tname} in the same migration."
            )
            del model.triggers[tname]
    for tbl in sorted(model.fks):
        for target in sorted(model.fks[tbl] & model.dropped_tables):
            out.append(
                f"migration {version:03d}: table {tbl} has a foreign key to {target}, which the "
                f"ladder dropped. Rebuild the reference in the same migration."
            )
            model.fks[tbl].discard(target)
    return out


def closure_violations(schema_sql: str, ordered_migrations: list[tuple[int, str]]) -> list[str]:
    """Return ladder-closure violations. ``ordered_migrations`` is a list of
    ``(version, sql_text)`` in ascending version order.

    The baseline is applied first (assumed self-consistent — SQLite would reject
    it otherwise), then each migration in turn; after each, any index / trigger
    / foreign key still referencing an object the ladder dropped is a violation.
    An empty ``ordered_migrations`` drops nothing and returns ``[]``.
    """
    model = _SchemaModel()
    _apply_ops(model, _extract_ops(_prepare_ddl(schema_sql)))
    violations: list[str] = []
    for version, sql_text in ordered_migrations:
        _apply_ops(model, _extract_ops(_prepare_ddl(sql_text)))
        violations.extend(_closure_violations_for(model, version))
    return violations


def ladder_violations(
    lock: dict, schema_sql: str, migration_files: dict[str, str], policy: dict
) -> list[str]:
    """Return ladder-contract violations; an empty list means clean.

    Pure so tests can drive it with fixture locks/files/policies. ``lock`` is
    the parsed canonical ``checksums.lock``; ``schema_sql`` the baseline DDL
    text; ``migration_files`` maps ``NNN_<name>.sql`` file names to contents;
    ``policy`` the parsed ``migration_policy.json``.
    """
    violations: list[str] = []
    launched = bool(policy.get("launched", False))

    if not isinstance(lock, dict) or not lock:
        return ["checksums.lock must be a non-empty JSON object keyed by version."]

    entries: dict[int, dict] = {}
    for key, entry in lock.items():
        if not (isinstance(key, str) and len(key) == 3 and key.isdigit() and int(key) >= 1):
            violations.append(f"lock key {key!r} is not a zero-padded version (e.g. '002').")
            continue
        if not isinstance(entry, dict):
            violations.append(f"lock entry {key} must be an object with name and sha256.")
            continue
        name = entry.get("name")
        sha = entry.get("sha256")
        if not isinstance(name, str) or not isinstance(sha, str) or not re.fullmatch(
            r"[0-9a-f]{64}", sha
        ):
            violations.append(
                f"lock entry {key} must carry a string name and a lowercase 64-hex sha256."
            )
            continue
        entries[int(key)] = {"name": name, "sha256": sha}

    if violations:
        return violations

    max_version = max(entries)
    if 1 not in entries:
        violations.append("the baseline lock entry 001 is missing.")
    for version in range(1, max_version + 1):
        if version not in entries:
            violations.append(
                f"lock versions are not contiguous: entry {version:03d} is missing "
                f"(entries must run 001..{max_version:03d} with no gaps)."
            )
    if violations:
        return violations

    if entries[1]["name"] != "001_schema.sql":
        violations.append(
            f"lock entry 001 must name the baseline '001_schema.sql', got "
            f"{entries[1]['name']!r}."
        )
    baseline_sha = sha256_migration_hex(schema_sql)
    if entries[1]["sha256"] != baseline_sha:
        if launched:
            violations.append(
                "schema/schema.sql does not match the frozen baseline checksum "
                f"(locked {entries[1]['sha256'][:16]}..., actual {baseline_sha[:16]}...). "
                "Post-launch the baseline is immutable: revert the schema.sql edit and "
                "express the change as a new schema/migrations/NNN_<name>.sql migration "
                "(see schema/migrations/README.md)."
            )
        else:
            violations.append(
                "schema/schema.sql does not match lock entry 001 "
                f"(locked {entries[1]['sha256'][:16]}..., actual {baseline_sha[:16]}...). "
                "Pre-launch, regenerate the lock with "
                "`apps/apple/script/verify_migration_ladder.py --seed` (it rewrites "
                "schema/migrations/checksums.lock and the Apple embed byte-identically)."
            )

    if not launched and migration_files:
        listed = ", ".join(sorted(migration_files))
        violations.append(
            f"pre-launch (migration_policy.json launched=false) the canonical ladder must "
            f"be empty, but schema/migrations/ contains: {listed}. Pre-launch schema "
            f"changes edit schema/schema.sql directly; the ladder arms at launch."
        )

    recorded_files: set[str] = set()
    for version in range(2, max_version + 1):
        entry = entries[version]
        match = MIGRATION_NAME_RE.fullmatch(entry["name"])
        if match is None or int(match.group(1)) != version:
            violations.append(
                f"lock entry {version:03d} name {entry['name']!r} must be "
                f"'{version:03d}_<snake_case>.sql'."
            )
            continue
        recorded_files.add(entry["name"])
        text = migration_files.get(entry["name"])
        if text is None:
            violations.append(
                f"lock entry {version:03d} records {entry['name']} but the file is missing "
                f"from schema/migrations/."
            )
            continue
        actual = sha256_migration_hex(text)
        if actual != entry["sha256"]:
            violations.append(
                f"schema/migrations/{entry['name']} does not match its recorded checksum "
                f"(locked {entry['sha256'][:16]}..., actual {actual[:16]}...). A recorded "
                f"migration is frozen — revert the edit and append a new migration instead."
            )

    for name in sorted(set(migration_files) - recorded_files):
        match = MIGRATION_NAME_RE.fullmatch(name)
        if match is None:
            violations.append(
                f"schema/migrations/{name} does not match the NNN_<snake_case>.sql naming "
                f"contract."
            )
        elif int(match.group(1)) <= 1:
            violations.append(
                f"schema/migrations/{name} uses a reserved version ({match.group(1)}): 001 "
                f"is the baseline schema.sql and migrations start at 002."
            )
        else:
            violations.append(
                f"schema/migrations/{name} has no checksums.lock entry; record it (and the "
                f"derived copies) before it can ship."
            )

    if launched:
        frozen = (policy.get("frozen_baseline") or {}).get("checksums_lock") or {}
        for key in sorted(frozen):
            if not (isinstance(key, str) and len(key) == 3 and key.isdigit()):
                violations.append(
                    f"frozen lock key {key!r} is not a zero-padded version."
                )
                continue
            version = int(key)
            frozen_entry = frozen[key]
            if not (
                isinstance(frozen_entry, dict)
                and isinstance(frozen_entry.get("name"), str)
                and isinstance(frozen_entry.get("sha256"), str)
            ):
                violations.append(
                    f"frozen lock entry {key} must contain its released name and sha256."
                )
                continue
            if version not in entries:
                violations.append(
                    f"frozen lock entry {key} was removed from the canonical checksums.lock."
                )
            elif entries[version] != frozen_entry:
                changed = []
                if entries[version]["name"] != frozen_entry["name"]:
                    changed.append(
                        f"name frozen as {frozen_entry['name']!r}, now "
                        f"{entries[version]['name']!r}"
                    )
                if entries[version]["sha256"] != frozen_entry["sha256"]:
                    changed.append(
                        f"sha256 frozen {frozen_entry['sha256'][:16]}..., now "
                        f"{entries[version]['sha256'][:16]}..."
                    )
                violations.append(
                    f"frozen lock entry {key} changed ({'; '.join(changed)}). Released entries are "
                    f"append-only; add a new migration instead."
                )

    # Ladder closure: destructive migrations are allowed, but each must leave no
    # dangling reference to a dropped object. Run only once the lock/file
    # checks above are clean so the analyzed files are the recorded ones; an
    # empty ladder drops nothing and yields no violations.
    if not violations and max_version >= 2:
        ordered = [
            (version, migration_files[entries[version]["name"]])
            for version in range(2, max_version + 1)
        ]
        violations += closure_violations(schema_sql, ordered)

    return violations


def build_lock() -> dict:
    """Compute the canonical ``checksums.lock`` from ``schema/schema.sql``
    (version ``001``) plus every numbered migration in ``schema/migrations/``.

    Apple-owned: reuses this module's ``sha256_migration_hex`` normalization, so
    regenerating the lock needs no Tauri/Node tooling. The Tauri copy is a
    separate, directionally-aligned implementation and is not written here.
    """
    lock: dict = {
        "001": {
            "name": "001_schema.sql",
            "sha256": sha256_migration_hex(SCHEMA_SQL_PATH.read_text(encoding="utf-8")),
        }
    }
    for name, contents in load_migration_files().items():
        match = MIGRATION_NAME_RE.match(name)
        if match is None:
            continue
        lock[match.group(1)] = {"name": name, "sha256": sha256_migration_hex(contents)}
    return lock


def seed() -> int:
    """Regenerate ``schema/migrations/checksums.lock`` and mirror it byte-for-byte
    into the Apple embed. Pre-launch only: once ``launched`` is true the released
    entries are frozen and re-seeding is a data-loss bug (``verify_schema_freeze.py``
    enforces that), so refuse.
    """
    policy = json.loads(POLICY_PATH.read_text(encoding="utf-8"))
    if policy.get("launched"):
        print(
            "refusing to re-seed: launched=true freezes the released checksums.lock — "
            "append a numbered migration instead (see schema/migrations/README.md).",
            file=sys.stderr,
        )
        return 1
    lock = build_lock()
    text = json.dumps(lock, indent=2, sort_keys=True) + "\n"
    LOCK_PATH.write_text(text, encoding="utf-8")
    APPLE_EMBED_LOCK.write_text(text, encoding="utf-8")
    count = len(lock)
    print(
        f"seeded {LOCK_PATH.relative_to(REPO_ROOT)} and mirrored to the Apple embed "
        f"({count} entr{'y' if count == 1 else 'ies'})."
    )
    return 0


def main(argv: list[str]) -> int:
    if "--seed" in argv:
        return seed()
    lock = load_lock()
    schema_sql = SCHEMA_SQL_PATH.read_text(encoding="utf-8")
    migration_files = load_migration_files()
    policy = json.loads(POLICY_PATH.read_text(encoding="utf-8"))

    violations = ladder_violations(lock, schema_sql, migration_files, policy)
    if violations:
        print("migration-ladder verification FAILED:", file=sys.stderr)
        for violation in violations:
            print(f"- {violation}", file=sys.stderr)
        return 1

    regime = "post-launch (armed)" if policy.get("launched") else "pre-launch (ladder empty)"
    print(
        f"migration-ladder verification PASS: {len(lock)} lock entr"
        f"{'y' if len(lock) == 1 else 'ies'}, {len(migration_files)} migration file(s), "
        f"regime {regime}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
