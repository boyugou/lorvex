#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum RemoteApplyMode {
    BestEffort,
    StrictAtomic,
}
