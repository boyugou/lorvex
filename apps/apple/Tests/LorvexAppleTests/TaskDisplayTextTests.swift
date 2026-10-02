import LorvexCore
import Testing

/// Every surface names a priority and a status with the same Core words; the
/// storage codes (P1, `in_progress`) never reach the screen.
@Test
func taskVocabularyUsesUserFacingNames() {
  #expect(LorvexTask.Priority.p1.localizedPhrase == "High priority")
  #expect(LorvexTask.Priority.p1.localizedName == "High")
  #expect(LorvexTask.Priority.p3.localizedName == "Low")
  #expect(LorvexTask.Status.completed.localizedName == "Completed")
  #expect(LorvexTask.Status.inProgress.localizedName == "In Progress")
  #expect(LorvexTask.Status.cancelled.localizedName == "Cancelled")
}
