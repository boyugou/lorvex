#!/usr/bin/env python3
"""Verify the dynamic-link closure of a built app bundle.

For every executable context in the bundle (the app itself, each app
extension under PlugIns/, each nested app under Watch/ or Contents/Helpers/),
this walks the dyld load graph starting at the context's executable and
asserts that every non-system load command resolves to a Mach-O inside the
bundle, using the same run-path semantics dyld applies:

- `@executable_path` resolves against the context executable's directory.
- `@loader_path` resolves against the directory of the image that declares
  the load (or the LC_RPATH entry).
- `@rpath/...` is tried against the accumulated LC_RPATH stack of the load
  chain (main executable first, then each loader down to the image issuing
  the load), which is how dyld actually searches.

`/System/...` and `/usr/lib/...` loads are trusted as OS-provided, as are
`@rpath/libswift*.dylib` Swift-runtime loads (satisfied by the
`/usr/lib/swift` LC_RPATH Xcode injects; the target OS file set cannot be
stat'ed from the build host).

This exists because a Release .app can link successfully while shipping an
incomplete Frameworks/ directory: Xcode builds SwiftPM library products as
*dynamic* `…PackageProduct` frameworks whenever two targets in one process
link the same product, and linking a wrapper framework does not copy the
wrapper's dynamic package dependencies into the host app. The result passes
every compile/link gate and dies at launch with dyld "Library not loaded".
A missing LD_RUNPATH_SEARCH_PATHS on an executable (the watchOS application
preset drift) is caught the same way: its loads have no run-path to resolve
against and are reported as unresolved.

Exit codes: 0 = closure complete; 1 = unresolved loads (listed on stderr);
2 = usage / bundle not found; 78 = otool unavailable on this host (matching
the verifier soft-skip convention).
"""
from __future__ import annotations

import plistlib
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

SYSTEM_PREFIXES = ("/System/", "/usr/lib/")
LOAD_DYLIB_COMMANDS = {
    "LC_LOAD_DYLIB",
    "LC_LOAD_WEAK_DYLIB",
    "LC_REEXPORT_DYLIB",
    "LC_LAZY_LOAD_DYLIB",
    "LC_LOAD_UPWARD_DYLIB",
}


@dataclass
class MachOInfo:
    """Load commands of one image: dylib load paths and LC_RPATH entries."""

    loads: list[str] = field(default_factory=list)
    rpaths: list[str] = field(default_factory=list)


@dataclass
class ExecutableContext:
    """One process root: a bundle's main executable and its directory."""

    bundle: Path
    executable: Path


@dataclass
class UnresolvedLoad:
    context: ExecutableContext
    image: Path
    load: str
    chain: list[Path]

    def describe(self, root: Path) -> str:
        chain = " -> ".join(str(p.relative_to(root)) for p in self.chain)
        return f"[{self.context.executable.relative_to(root)}] {chain} loads {self.load}"


def parse_load_commands(otool_output: str) -> MachOInfo:
    """Parse `otool -l` output into loads and rpaths (all slices unioned).

    Fat binaries repeat the load commands per architecture; the union is
    correct here because resolution only depends on the path strings.
    """
    info = MachOInfo()
    current_cmd = ""
    for line in otool_output.splitlines():
        stripped = line.strip()
        if stripped.startswith("cmd "):
            current_cmd = stripped.split(None, 1)[1]
        elif stripped.startswith("name ") and current_cmd in LOAD_DYLIB_COMMANDS:
            name = stripped[len("name "):].rsplit(" (offset", 1)[0]
            if name not in info.loads:
                info.loads.append(name)
        elif stripped.startswith("path ") and current_cmd == "LC_RPATH":
            path = stripped[len("path "):].rsplit(" (offset", 1)[0]
            if path not in info.rpaths:
                info.rpaths.append(path)
    return info


def is_system_load(load: str) -> bool:
    if load.startswith(SYSTEM_PREFIXES):
        return True
    # Swift runtime dylibs resolve through the /usr/lib/swift LC_RPATH on
    # the target OS; those files cannot be checked from the build host.
    if load.startswith("@rpath/lib") and load.endswith(".dylib"):
        leaf = load.rsplit("/", 1)[1]
        return leaf.startswith(("libswift", "libXCTestSwiftSupport"))
    return False


def resolve_special_prefix(path: str, executable_dir: Path, loader_dir: Path) -> Path | None:
    """Resolve an @executable_path/@loader_path prefix; None if absolute-system."""
    if path.startswith("@executable_path/"):
        return executable_dir / path[len("@executable_path/"):]
    if path.startswith("@loader_path/"):
        return loader_dir / path[len("@loader_path/"):]
    return None


def resolve_load(
    load: str,
    rpath_stack: list[tuple[str, Path]],
    executable_dir: Path,
    loader_dir: Path,
) -> Path | None:
    """Resolve one load command to an existing file, dyld-style.

    `rpath_stack` carries (rpath, declaring_image_dir) pairs accumulated
    along the load chain, so each entry's @loader_path resolves against the
    image that declared it. Returns the resolved path or None.
    """
    direct = resolve_special_prefix(load, executable_dir, loader_dir)
    if direct is not None:
        resolved = Path(direct).resolve()
        return resolved if resolved.is_file() else None
    if load.startswith("@rpath/"):
        suffix = load[len("@rpath/"):]
        for rpath, rpath_loader_dir in rpath_stack:
            base = resolve_special_prefix(rpath, executable_dir, rpath_loader_dir)
            if base is None:
                # Absolute rpath (e.g. /usr/lib/swift): target-OS territory,
                # not resolvable from the build host; is_system_load() already
                # accepted the loads this can satisfy.
                continue
            candidate = (Path(base) / suffix).resolve()
            if candidate.is_file():
                return candidate
        return None
    # Absolute non-system install path: never valid inside a distributable
    # bundle (verify_macho_distribution.py rejects these too).
    return None


def walk_context(
    context: ExecutableContext,
    macho_info,
    root: Path,
    visited_images: set[Path],
) -> list[UnresolvedLoad]:
    """Check every load reachable from the context executable.

    Each image is checked once per distinct accumulated rpath stack, because
    an image reachable through two chains may resolve under one chain's
    run paths and not the other's.
    """
    failures: list[UnresolvedLoad] = []
    executable_dir = context.executable.parent
    seen: set[tuple[Path, tuple[tuple[str, str], ...]]] = set()
    # One report per (image, load): the same unresolved load is otherwise
    # re-reported for every distinct chain that reaches the image.
    reported: set[tuple[Path, str]] = set()

    def report(image: Path, load: str, chain: list[Path]) -> None:
        if (image, load) not in reported:
            reported.add((image, load))
            failures.append(UnresolvedLoad(context, image, load, chain))

    def visit(image: Path, stack: list[tuple[str, Path]], chain: list[Path]) -> None:
        info = macho_info(image)
        # Deduplicate while appending: the accumulated stack stays bounded by
        # the finite set of (rpath, directory) pairs, so cyclic load graphs
        # terminate (each image is revisited at most once per distinct stack).
        for entry in ((rpath, image.parent) for rpath in info.rpaths):
            if entry not in stack:
                stack = stack + [entry]
        key = (image, tuple((r, str(d)) for r, d in stack))
        if key in seen:
            return
        seen.add(key)
        visited_images.add(image)
        for load in info.loads:
            if is_system_load(load):
                continue
            resolved = resolve_load(load, stack, executable_dir, image.parent)
            if resolved is None:
                report(image, load, chain + [image])
            elif root in resolved.parents:
                visit(resolved, stack, chain + [image])
            else:
                report(image, f"{load} (resolves outside bundle: {resolved})", chain + [image])

    visit(context.executable, [], [])
    return failures


def bundle_executable(bundle: Path) -> Path | None:
    """Locate a bundle's main executable via its Info.plist.

    Supports both layouts: iOS-style (Info.plist and executable at the bundle
    root) and macOS-style (under Contents/).
    """
    for info_plist, executable_dir in (
        (bundle / "Info.plist", bundle),
        (bundle / "Contents" / "Info.plist", bundle / "Contents" / "MacOS"),
    ):
        if not info_plist.is_file():
            continue
        with info_plist.open("rb") as handle:
            plist = plistlib.load(handle)
        name = plist.get("CFBundleExecutable")
        if not name:
            return None
        executable = executable_dir / name
        return executable if executable.is_file() else None
    return None


def discover_contexts(bundle: Path) -> list[ExecutableContext]:
    """The bundle's own executable plus every nested executable bundle.

    Nested contexts are separate processes with their own dyld state:
    app extensions (PlugIns/ and, for App Intents / Focus-filter extensions on
    iOS 16+, Extensions/), the embedded watch app (Watch/) including its own
    extensions, and bundled helper apps (Contents/Helpers/).
    """
    contexts: list[ExecutableContext] = []
    executable = bundle_executable(bundle)
    if executable is not None:
        contexts.append(ExecutableContext(bundle, executable))
    for subdir in ("PlugIns", "Extensions", "Watch", "Contents/PlugIns", "Contents/Helpers"):
        parent = bundle / subdir
        if not parent.is_dir():
            continue
        for nested in sorted(parent.iterdir()):
            if nested.suffix in (".appex", ".app") and nested.is_dir():
                contexts.extend(discover_contexts(nested))
    return contexts


def is_macho(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            magic = handle.read(4)
    except OSError:
        return False
    return magic in (
        b"\xfe\xed\xfa\xce",
        b"\xce\xfa\xed\xfe",
        b"\xfe\xed\xfa\xcf",
        b"\xcf\xfa\xed\xfe",
        b"\xca\xfe\xba\xbe",
        b"\xbe\xba\xfe\xca",
    )


def otool_macho_info(path: Path) -> MachOInfo:
    output = subprocess.check_output(["otool", "-l", str(path)], text=True)
    return parse_load_commands(output)


def verify_bundle(bundle: Path, macho_info=otool_macho_info) -> list[str]:
    """Return a list of human-readable failures; empty means the closure holds."""
    bundle = Path(bundle).resolve()
    contexts = discover_contexts(bundle)
    if not contexts:
        return [f"no executable contexts found in {bundle}"]

    cache: dict[Path, MachOInfo] = {}

    def cached_macho_info(path: Path) -> MachOInfo:
        if path not in cache:
            cache[path] = macho_info(path)
        return cache[path]

    failures: list[str] = []
    visited: set[Path] = set()
    for context in contexts:
        for unresolved in walk_context(context, cached_macho_info, bundle, visited):
            failures.append(unresolved.describe(bundle))

    # Every Mach-O shipped in the bundle must be reachable from some
    # executable, otherwise its own load closure was never verified (and it
    # is dead weight at best).
    for path in sorted(p for p in bundle.rglob("*") if p.is_file()):
        resolved = path.resolve()
        if resolved not in visited and is_macho(path) and path.stat().st_size > 0:
            failures.append(f"{path.relative_to(bundle)} is not reachable from any executable")
    return failures


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: verify_macho_closure.py <Bundle.app> [...]", file=sys.stderr)
        return 2
    if shutil.which("otool") is None:
        print("verify_macho_closure: otool not available on this host.", file=sys.stderr)
        return 78

    status = 0
    for argument in sys.argv[1:]:
        bundle = Path(argument).resolve()
        if not bundle.is_dir():
            print(f"app bundle not found: {bundle}", file=sys.stderr)
            return 2
        failures = verify_bundle(bundle)
        if failures:
            print(f"Mach-O closure verification failed for {bundle.name}:", file=sys.stderr)
            for failure in failures:
                print(f"- {failure}", file=sys.stderr)
            status = 1
        else:
            print(f"Mach-O closure verification passed: {bundle.name}")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
