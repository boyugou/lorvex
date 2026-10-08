#!/usr/bin/env python3
"""Digest the Mac accessibility dump that `ui_tour_macos.sh` writes into its log.

Run the tour with the dump on, then read the log it leaves in the output directory:

    LORVEX_TOUR_EXTRA_ARGS="-uiPreviewDumpAX" script/ui_tour_macos.sh light <outdir>
    uv run python script/mac_ax_report.py <outdir>/tour-light.log stops
    uv run python script/mac_ax_report.py <outdir>/tour-light.log flags
    uv run python script/mac_ax_report.py <outdir>/tour-light.log transcript calendar today

Commands:

  stops       one line per stop and window: element count and nameless interactive count
  flags       findings across all stops, de-duplicated by kind, role, name and identifier:
              nameless controls, symbol names read aloud, labelled images, and a parent whose
              label repeats the text of a child (VoiceOver would read it twice)
  transcript  the named elements of the given stops in the tree's reading order, indented by depth

The log holds, for each stop, `AXDUMP STOP <name>`, one `AXDUMP WINDOW` line per window, one
`AXDUMP E <depth> [x,y wxh] role=<role>[/<subrole>][ selected][ disabled] label='…' title='…'
value='…' valueDesc='…' help='…' id='…' placeholder='…' titleUI='…' actions='…'` line per element
(frames in points from the window's top-left corner), and `AXDUMP END <name>`.
"""
import re
import sys
from collections import OrderedDict, defaultdict
from pathlib import Path

LINE = re.compile(
    r"^AXDUMP E (\d+) \[(-?\d+),(-?\d+) (\d+)x(\d+)\] role=(\S+)((?: selected| disabled)*) "
    r"label='(.*?)' title='(.*?)' value='(.*?)'(?: valueDesc='(.*?)')? help='(.*?)' id='(.*?)'"
    r"(?: placeholder='(.*?)')?(?: titleUI='(.*?)')?(?: actions='(.*?)')?$"
)
INTERACTIVE = {
    "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXTextField",
    "AXTextArea", "AXComboBox", "AXSlider", "AXIncrementor", "AXDisclosureTriangle", "AXLink",
    "AXSegmentedControl", "AXDateField", "AXColorWell",
}
CONTAINERS = {
    "AXGroup", "AXScrollArea", "AXSplitGroup", "AXOutline", "AXTable", "AXList", "AXRow",
    "AXCell", "AXColumn", "AXSplitter", "AXToolbar", "AXWindow", "AXLayoutArea",
}
SYMBOL_NAME = re.compile(r"^[a-z][a-z0-9]*(\.[a-z0-9]+)+$")


class Element:
    """One `AXDUMP E` line."""

    def __init__(self, match, stop, window):
        groups = match.groups()
        self.depth = int(groups[0])
        self.x, self.y, self.w, self.h = (int(value) for value in groups[1:5])
        role = groups[5]
        self.role = role.split("/")[0]
        self.subrole = role.split("/")[1] if "/" in role else ""
        self.flags = groups[6].strip()
        self.label, self.title, self.value = groups[7], groups[8], groups[9]
        self.value_desc = groups[10] or ""
        self.help, self.id = groups[11], groups[12]
        self.placeholder = groups[13] or ""
        self.title_ui = groups[14] or ""
        self.actions = groups[15] or ""
        self.stop, self.window = stop, window

    @property
    def name(self):
        """What VoiceOver speaks for the element. A control's value is state, never its name."""
        if self.role in INTERACTIVE:
            return self.label or self.title or self.title_ui or self.placeholder
        return self.label or self.title or self.value or self.value_desc or self.placeholder

    def show(self):
        bits = [self.role + ("/" + self.subrole if self.subrole else "")]
        if self.flags:
            bits.append(self.flags)
        for key in ("label", "title", "value", "value_desc", "placeholder", "title_ui", "help"):
            text = getattr(self, key)
            if text:
                bits.append(f"{key}={text[:110]!r}")
        if self.id:
            bits.append(f"id={self.id}")
        if self.actions:
            bits.append(f"actions={self.actions}")
        return " ".join(bits)


def parse(path):
    """The log's elements as {stop: {window: [Element]}}, in log order."""
    stops = OrderedDict()
    stop = window = None
    for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("AXDUMP STOP "):
            stop = line[len("AXDUMP STOP "):]
            stops[stop] = OrderedDict()
        elif line.startswith("AXDUMP END "):
            stop = window = None
        elif line.startswith("AXDUMP WINDOW ") and stop:
            window = line[len("AXDUMP WINDOW "):]
            stops[stop][window] = []
        elif line.startswith("AXDUMP SKIPPED"):
            print(line)
        elif line.startswith("AXDUMP E ") and stop and window is not None:
            match = LINE.match(line)
            if match:
                stops[stop][window].append(Element(match, stop, window))
            else:
                print("UNPARSED:", line[:160])
    return stops


def command_stops(stops):
    for name, windows in stops.items():
        for window, elements in windows.items():
            unnamed = sum(1 for e in elements if e.role in INTERACTIVE and not e.name)
            print(f"{name:34s} {window[:48]:48s} elements={len(elements):4d} unnamed={unnamed}")


def command_flags(stops):
    found = OrderedDict()

    def add(kind, element, note=""):
        key = (kind, element.role, element.name[:60], element.id)
        if key not in found:
            found[key] = [element, note, []]
        found[key][2].append(element.stop)

    for windows in stops.values():
        for elements in windows.values():
            for index, e in enumerate(elements):
                if e.role in INTERACTIVE and not e.name and "Hosting" not in e.subrole:
                    add("NAMELESS", e)
                for text in (e.label, e.title):
                    if text and SYMBOL_NAME.match(text):
                        add("SYMBOL-NAME", e)
                if e.role == "AXImage" and e.label:
                    add("IMAGE-LABEL", e)
                if e.role == "AXStaticText" and e.value and SYMBOL_NAME.match(e.value):
                    add("SYMBOL-TEXT", e)
                if e.label:
                    for child in elements[index + 1:]:
                        if child.depth <= e.depth:
                            break
                        if child.role == "AXStaticText" and child.value == e.label:
                            add("PARENT-CHILD-DUPLICATE", e, f"child text {child.value[:60]!r}")
                            break
    by_kind = defaultdict(list)
    for key, (element, note, seen) in found.items():
        by_kind[key[0]].append((element, note, seen))
    for kind, rows in by_kind.items():
        print(f"\n== {kind} ({len(rows)})")
        for element, note, seen in rows:
            distinct = sorted(set(seen))
            where = ",".join(distinct[:4]) + (f"+{len(distinct) - 4}" if len(distinct) > 4 else "")
            print(f"  [{where}] {element.show()} {note}")


def command_transcript(stops, names):
    for name in names:
        windows = stops.get(name)
        if not windows:
            print(f"(no stop {name})")
            continue
        for window, elements in windows.items():
            print(f"\n##### {name}  {window}")
            for e in elements:
                if e.role in CONTAINERS and not e.name and e.role != "AXOutline" and not e.id:
                    continue
                if e.role == "AXGroup" and not e.name and "Hosting" in e.subrole:
                    continue
                print("  " * min(e.depth, 14) + f"[{e.x},{e.y} {e.w}x{e.h}] " + e.show())


def main(argv):
    if len(argv) < 3 or argv[2] not in ("stops", "flags", "transcript"):
        sys.exit(__doc__)
    stops = parse(argv[1])
    if argv[2] == "stops":
        command_stops(stops)
    elif argv[2] == "flags":
        command_flags(stops)
    else:
        command_transcript(stops, argv[3:])


if __name__ == "__main__":
    main(sys.argv)
