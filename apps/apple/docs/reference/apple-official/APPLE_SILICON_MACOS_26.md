# Apple Silicon and macOS 26 Compatibility

Source: [How to upgrade to macOS Tahoe 26](https://support.apple.com/en-ie/122727)

Last verified: 2026-07-10

## Apple Compatibility

Apple lists every Apple-silicon Mac family from the original 2020 M1 models
onward as compatible with macOS Tahoe 26. The compatibility list also contains
a small number of Intel Macs; OS compatibility therefore does not itself imply
an Apple-silicon binary.

## Lorvex Mapping

- A future macOS 26 minimum would not remove an Apple-silicon hardware
  generation, but it would remove users who have not upgraded their OS.
- An arm64-only artifact is the direct expression of an Apple-silicon-first
  distribution strategy.
- Deployment target, SDK version, and Mach-O architecture must remain separate
  release-manifest fields and test gates.

The current practical direction is arm64 as the primary/default artifact with
an optional universal artifact allowed as a secondary path. Supporting that
secondary artifact must not reintroduce Intel-specific product constraints into
the primary release gate.

