#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["python-dateutil>=2.9"]
# ///
"""Generate recurrence-engine test vectors from an independent RFC 5545 oracle.

python-dateutil's ``rrule`` is the oracle. For a rule and a start date (``base``)
it yields the occurrences, and each vector records what the engine under test
must return:

* ``first`` vectors: the first occurrence on or after a ``target`` date (never
  before ``base``), or ``null`` when the series has ended.
* ``successors`` vectors: the next occurrences after ``base`` in order, found one
  after another the way a completed recurring task finds its successor.

Where the Lorvex engine deliberately differs from the RFC the generator stays
inside the region where they agree:

* A MONTHLY or YEARLY rule with no BYMONTHDAY, BYDAY, or BYSETPOS uses the start
  date's day of the month. The engine clamps it to the end of a short month and
  the RFC skips the month, so these rules only start on a day from 1 to 28.
* A YEARLY rule with BYMONTHDAY and no BYMONTH or BYDAY repeats in the month of
  its start date in the engine, so the oracle receives that month as BYMONTH.

Usage:
  uv run apps/apple/script/recurrence_oracle.py --fixture spec/fixtures/recurrence/oracle-cases.json
  uv run apps/apple/script/recurrence_oracle.py --cases 40000 --seed 7 /tmp/wide.json

``--fixture`` writes the small deterministic set the core test suite loads. The
wide form writes a randomly weighted corpus for exploration; run it against the
engine with

  LORVEX_RECURRENCE_ORACLE_CASES=/tmp/wide.json \\
    swift test -j 4 --filter CalendarRecurrenceOracleTests

from ``apps/apple/core``. The oracle's per-case time limit uses ``SIGALRM``, so
the script runs on macOS and Linux only.
"""

import argparse
import json
import random
import signal
import sys
from datetime import date, datetime, timedelta

from dateutil import rrule as rr
from dateutil.rrule import DAILY, MONTHLY, WEEKLY, YEARLY, rrule

CODES = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
WEEKDAYS = [rr.MO, rr.TU, rr.WE, rr.TH, rr.FR, rr.SA, rr.SU]
FREQ = {"DAILY": DAILY, "WEEKLY": WEEKLY, "MONTHLY": MONTHLY, "YEARLY": YEARLY}
SUCCESSOR_COUNT = 6
FIXTURE_SEED = 5545
FIXTURE_TRIPLES_PER_CATEGORY = 12
FIXTURE_CHAINS_PER_CATEGORY = 4


class OracleTimeout(Exception):
    """The oracle spent too long on a rule that has no nearby occurrence."""


def _on_alarm(signum, frame):
    raise OracleTimeout()


signal.signal(signal.SIGALRM, _on_alarm)


def build_rrule(rule, base):
    """The dateutil rule that stands for `rule` started on `base`."""
    kwargs = {"dtstart": datetime(base.year, base.month, base.day), "interval": rule.get("INTERVAL", 1)}
    if "BYDAY" in rule:
        kwargs["byweekday"] = [
            WEEKDAYS[CODES.index(token[-2:])](int(token[:-2])) if token[:-2] else WEEKDAYS[CODES.index(token[-2:])]
            for token in rule["BYDAY"]
        ]
    if "BYMONTH" in rule:
        kwargs["bymonth"] = rule["BYMONTH"]
    elif rule["FREQ"] == "YEARLY" and "BYMONTHDAY" in rule and "BYDAY" not in rule:
        kwargs["bymonth"] = [base.month]
    if "BYMONTHDAY" in rule:
        kwargs["bymonthday"] = rule["BYMONTHDAY"]
    if "BYSETPOS" in rule:
        kwargs["bysetpos"] = rule["BYSETPOS"]
    if "WKST" in rule:
        kwargs["wkst"] = CODES.index(rule["WKST"])
    if "UNTIL" in rule:
        year, month, day = map(int, rule["UNTIL"].split("-"))
        kwargs["until"] = datetime(year, month, day)
    return rrule(FREQ[rule["FREQ"]], **kwargs)


def _after(oracle, moment, inclusive):
    signal.setitimer(signal.ITIMER_REAL, 0.4)
    try:
        return oracle.after(moment, inc=inclusive)
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)


def first_on_or_after(rule, base, target):
    """ISO date of the first occurrence on or after max(target, base); None if the series ended."""
    floor = max(target, base)
    found = _after(build_rrule(rule, base), datetime(floor.year, floor.month, floor.day), True)
    return None if found is None else found.date().isoformat()


def successors(rule, base):
    """The next occurrences after `base`, each found from the one before."""
    oracle = build_rrule(rule, base)
    cursor = datetime(base.year, base.month, base.day)
    found = []
    for _ in range(SUCCESSOR_COUNT):
        following = _after(oracle, cursor, False)
        if following is None:
            break
        found.append(following.date().isoformat())
        cursor = following
    return found


def pick_base(rng, category):
    if rng.random() < 0.35:
        year = rng.randint(2020, 2031)
        month, day = rng.choice(
            [(1, 29), (1, 30), (1, 31), (2, 28), (2, 29), (3, 31), (4, 30), (5, 31), (8, 31), (12, 31), (1, 1), (12, 1)]
        )
        try:
            base = date(year, month, day)
        except ValueError:
            base = date(year, 2, 28)
    else:
        base = date(2020, 1, 1) + timedelta(days=rng.randint(0, 12 * 365))
    if category in IMPLICIT_DAY and base.day > 28:
        base = base.replace(day=rng.randint(1, 28))
    return base


def pick_target(rng, base):
    roll = rng.random()
    if roll < 0.1:
        return base - timedelta(days=rng.randint(1, 40))
    if roll < 0.2:
        return base
    if roll < 0.7:
        return base + timedelta(days=rng.randint(1, 400))
    if roll < 0.95:
        return base + timedelta(days=rng.randint(400, 1500))
    return base + timedelta(days=rng.randint(1500, 4000))


def month_days(rng, count=None):
    count = count or rng.choice([1, 1, 1, 2, 3])
    pool = list(range(1, 32)) + list(range(-31, 0))
    weights = [3 if d in (1, 15, 28, 29, 30, 31, -1, -2, -29, -30, -31) else 1 for d in pool]
    return sorted(set(rng.choices(pool, weights=weights, k=count)))


def months(rng, count=None):
    return sorted(rng.sample(range(1, 13), count or rng.choice([1, 1, 2, 3, 4])))


def plain_days(rng):
    return rng.sample(CODES, rng.choice([1, 1, 2, 3, 5, 7]))


def ordinal_days(rng, limit):
    tokens = set()
    for _ in range(rng.choice([1, 1, 2, 3])):
        ordinal = rng.randint(1, limit) * (-1 if rng.random() < 0.4 else 1)
        tokens.add(f"{ordinal}{rng.choice(CODES)}")
    return sorted(tokens)


def set_positions(rng, size):
    return sorted(set(rng.choices([1, 2, 3, -1, -2, -3, size, -size], k=rng.choice([1, 1, 2]))))


INTERVALS = {
    "DAILY": [1, 1, 2, 3, 7, 10, 14, 30, 45, 100, 366, 400],
    "WEEKLY": [1, 1, 1, 2, 2, 3, 4, 5, 8, 26, 52],
    "MONTHLY": [1, 1, 1, 2, 3, 4, 6, 12, 13, 24],
    "YEARLY": [1, 1, 1, 2, 3, 4, 5, 10],
}

# Category name -> (random-mode weight, rule builder). The builder receives the
# random source and the rule so far ({"FREQ", "INTERVAL"}) and adds the keys.
def _weekly(rng, rule):
    if rng.random() < 0.8:
        rule["BYDAY"] = plain_days(rng)
    if rng.random() < 0.6:
        rule["WKST"] = rng.choice(CODES)
    if rng.random() < 0.15:
        rule["BYMONTH"] = months(rng)


def _monthly_ordinal_bymonth(rng, rule):
    rule["BYMONTH"] = months(rng, rng.choice([2, 3, 6]))
    rule["BYDAY"] = ordinal_days(rng, 4)


def _monthly_bymonthday_bymonth(rng, rule):
    rule["BYMONTH"] = months(rng, rng.choice([2, 3, 6]))
    rule["BYMONTHDAY"] = month_days(rng)


def _monthly_bymonth_setpos(rng, rule):
    rule["BYMONTH"] = months(rng, rng.choice([2, 4, 6]))
    rule["BYDAY"] = plain_days(rng)
    rule["BYSETPOS"] = set_positions(rng, 4)


CATEGORIES = {
    "daily": (4, lambda rng, rule: None),
    "weekly": (10, _weekly),
    "monthly_bymonthday": (12, lambda rng, rule: rule.update(BYMONTHDAY=month_days(rng))),
    "monthly_ordinal": (10, lambda rng, rule: rule.update(BYDAY=ordinal_days(rng, rng.choice([1, 2, 3, 4, 4, 5, 6])))),
    "monthly_plain_setpos": (
        7,
        lambda rng, rule: rule.update(BYDAY=plain_days(rng), BYSETPOS=set_positions(rng, rng.choice([4, 5]))),
    ),
    "monthly_plain": (3, lambda rng, rule: rule.update(BYDAY=plain_days(rng))),
    "monthly_bymonthday_byday": (4, lambda rng, rule: rule.update(BYMONTHDAY=month_days(rng), BYDAY=plain_days(rng))),
    "monthly_bymonthday_setpos": (
        3,
        lambda rng, rule: rule.update(BYMONTHDAY=month_days(rng, rng.choice([2, 3])), BYSETPOS=set_positions(rng, 3)),
    ),
    "monthly_implicit_day": (3, lambda rng, rule: None),
    "monthly_bymonthday_bymonth": (3, _monthly_bymonthday_bymonth),
    "monthly_ordinal_bymonth": (3, _monthly_ordinal_bymonth),
    "monthly_bymonth_setpos": (3, _monthly_bymonth_setpos),
    "yearly_bymonth_bymonthday": (
        8,
        lambda rng, rule: rule.update(BYMONTH=months(rng), BYMONTHDAY=month_days(rng)),
    ),
    "yearly_bymonth_ordinal": (
        7,
        lambda rng, rule: rule.update(BYMONTH=months(rng), BYDAY=ordinal_days(rng, rng.choice([1, 2, 3, 4, 5]))),
    ),
    "yearly_year_ordinal": (
        8,
        lambda rng, rule: rule.update(BYDAY=ordinal_days(rng, rng.choice([1, 2, 4, 5, 10, 20, 30, 40, 53]))),
    ),
    "yearly_year_plain": (3, lambda rng, rule: rule.update(BYDAY=plain_days(rng))),
    "yearly_bymonth_setpos": (
        4,
        lambda rng, rule: rule.update(BYMONTH=months(rng), BYDAY=plain_days(rng), BYSETPOS=set_positions(rng, 5)),
    ),
    "yearly_bymonth_bymonthday_byday": (
        4,
        lambda rng, rule: rule.update(
            BYMONTH=months(rng), BYMONTHDAY=month_days(rng, rng.choice([1, 2, 5])), BYDAY=plain_days(rng)
        ),
    ),
    "yearly_bymonth_bymonthday_setpos": (
        3,
        lambda rng, rule: rule.update(
            BYMONTH=months(rng, rng.choice([2, 3])),
            BYMONTHDAY=month_days(rng, rng.choice([2, 3])),
            BYSETPOS=set_positions(rng, 3),
        ),
    ),
    "yearly_implicit_day": (2, lambda rng, rule: None),
    "yearly_bymonth_only": (2, lambda rng, rule: rule.update(BYMONTH=months(rng))),
    "yearly_bymonthday_in_start_month": (2, lambda rng, rule: rule.update(BYMONTHDAY=month_days(rng))),
}
IMPLICIT_DAY = {"monthly_implicit_day", "yearly_implicit_day", "yearly_bymonth_only"}

# Rules that earlier engine defects mishandled, kept as fixed vectors so every
# fixture contains them whatever the random draw.
SPECIAL = [
    ({"FREQ": "YEARLY", "INTERVAL": 1, "BYDAY": ["20MO"]}, "2026-01-01"),
    ({"FREQ": "YEARLY", "INTERVAL": 1, "BYDAY": ["-20MO"]}, "2026-01-01"),
    ({"FREQ": "YEARLY", "INTERVAL": 1, "BYDAY": ["37TU"]}, "2026-01-01"),
    ({"FREQ": "YEARLY", "INTERVAL": 1, "BYDAY": ["53MO"]}, "2026-01-01"),
    ({"FREQ": "YEARLY", "INTERVAL": 3, "BYDAY": ["-5TU", "1FR"]}, "2023-04-30"),
    ({"FREQ": "YEARLY", "INTERVAL": 1, "BYMONTH": [3], "BYDAY": ["5MO"]}, "2026-01-01"),
    ({"FREQ": "MONTHLY", "INTERVAL": 1, "BYMONTHDAY": [-31]}, "2026-01-01"),
    ({"FREQ": "MONTHLY", "INTERVAL": 1, "BYMONTHDAY": [-30]}, "2026-01-01"),
    ({"FREQ": "MONTHLY", "INTERVAL": 1, "BYMONTHDAY": [-29]}, "2027-01-01"),
    ({"FREQ": "MONTHLY", "INTERVAL": 1, "BYMONTHDAY": [-29]}, "2028-01-01"),
    ({"FREQ": "MONTHLY", "INTERVAL": 1, "BYMONTHDAY": [-1]}, "2026-01-31"),
    ({"FREQ": "YEARLY", "INTERVAL": 1, "BYMONTH": [2], "BYMONTHDAY": [-30]}, "2026-01-01"),
    ({"FREQ": "YEARLY", "INTERVAL": 1, "BYMONTH": [2], "BYMONTHDAY": [-29]}, "2026-01-01"),
    ({"FREQ": "YEARLY", "INTERVAL": 4, "BYMONTH": [2], "BYMONTHDAY": [29]}, "2024-02-29"),
    ({"FREQ": "MONTHLY", "INTERVAL": 1, "BYDAY": ["MO", "TU", "WE", "TH", "FR"], "BYSETPOS": [-1]}, "2026-01-15"),
    ({"FREQ": "WEEKLY", "INTERVAL": 2, "BYDAY": ["SU", "MO"], "WKST": "SU"}, "2026-01-07"),
]


def vectors_for(rng, category, rule, base, with_successors):
    """One random target, its two boundary probes, and optionally the successor chain."""
    out = []
    target = pick_target(rng, base)
    try:
        expected = first_on_or_after(rule, base, target)
    except OracleTimeout:
        return out
    text = {"category": category, "rule": rule, "base": base.isoformat()}
    out.append({**text, "target": target.isoformat(), "expected": expected})
    if expected is not None:
        hit = date.fromisoformat(expected)
        for probe in (hit, hit + timedelta(days=1)):
            try:
                out.append({**text, "target": probe.isoformat(), "expected": first_on_or_after(rule, base, probe)})
            except OracleTimeout:
                continue
    if with_successors:
        try:
            out.append({**text, "successors": successors(rule, base)})
        except OracleTimeout:
            pass
    return out


def make_rule(rng, category):
    freq = category.split("_")[0].upper()
    rule = {"FREQ": freq, "INTERVAL": rng.choice(INTERVALS[freq])}
    CATEGORIES[category][1](rng, rule)
    return rule


def special_vectors(rng):
    out = []
    for rule, base_text in SPECIAL:
        base = date.fromisoformat(base_text)
        for offset in (0, 60, 400, 1200):
            target = base + timedelta(days=offset)
            out.append(
                {
                    "category": "special",
                    "rule": rule,
                    "base": base_text,
                    "target": target.isoformat(),
                    "expected": first_on_or_after(rule, base, target),
                }
            )
        out.append({"category": "special", "rule": rule, "base": base_text, "successors": successors(rule, base)})
    return out


def fixture_vectors():
    rng = random.Random(FIXTURE_SEED)
    out = special_vectors(rng)
    for category in CATEGORIES:
        for index in range(FIXTURE_TRIPLES_PER_CATEGORY):
            rule = make_rule(rng, category)
            base = pick_base(rng, category)
            if index < FIXTURE_CHAINS_PER_CATEGORY:
                rule_vectors = vectors_for(rng, category, rule, base, True)
            else:
                rule_vectors = vectors_for(rng, category, rule, base, False)
            out.extend(rule_vectors)
    return out


def random_vectors(count, seed):
    rng = random.Random(seed)
    names = list(CATEGORIES)
    weights = [CATEGORIES[name][0] for name in names]
    out = []
    while len(out) < count:
        category = rng.choices(names, weights=weights)[0]
        rule = make_rule(rng, category)
        base = pick_base(rng, category)
        if rng.random() < 0.15:
            until = base + timedelta(days=rng.randint(0, 900))
            rule["UNTIL"] = until.isoformat()
        out.extend(vectors_for(rng, category, rule, base, rng.random() < 0.35))
    return out


def write(path, vectors, description):
    with open(path, "w") as handle:
        handle.write('{\n  "description": ' + json.dumps(description) + ',\n  "oracle": "python-dateutil rrule",\n')
        handle.write('  "vectors": [\n')
        handle.write(",\n".join("    " + json.dumps(v, separators=(",", ":")) for v in vectors))
        handle.write("\n  ]\n}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--fixture", metavar="PATH", help="write the deterministic fixture to PATH")
    mode.add_argument("--cases", type=int, metavar="N", help="write about N random vectors to OUT")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("out", nargs="?", help="output path for --cases")
    args = parser.parse_args()
    if args.fixture:
        vectors = fixture_vectors()
        write(
            args.fixture,
            vectors,
            "Recurrence vectors from python-dateutil's rrule: the first occurrence on or after a target date "
            "('expected', null when the series ended) and the successors of a start date, one after another "
            "('successors'). Generated by apps/apple/script/recurrence_oracle.py --fixture.",
        )
        print(f"wrote {len(vectors)} vectors to {args.fixture}")
        return 0
    if not args.out:
        parser.error("--cases needs an output path")
    vectors = random_vectors(args.cases, args.seed)
    write(args.out, vectors, f"Random recurrence vectors, seed {args.seed}.")
    print(f"wrote {len(vectors)} vectors to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
