import LorvexCore

extension InboundApplyReport {
  /// Accumulate independently committed inbound work into one cycle report.
  /// Counts are additive because each source batch is applied exactly once;
  /// changed entity kinds form a set because surface reload routing only needs
  /// to know which canonical domains changed during the whole cycle.
  mutating func accumulate(_ report: InboundApplyReport) {
    applied += report.applied
    skipped += report.skipped
    deferred += report.deferred
    remapped += report.remapped
    drainReplayed += report.drainReplayed
    undecodable += report.undecodable
    deferredUnknownType += report.deferredUnknownType
    appliedEntityTypes.formUnion(report.appliedEntityTypes)
  }
}
