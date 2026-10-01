import LorvexApple
import LorvexCore
import LorvexMobile
import Testing

@Test
func taskDisplayTextUsesUserFacingLabels() {
  #expect(TaskDisplayText.priority(.p1) == "High priority")
  #expect(TaskDisplayText.compactPriority(.p1) == "High")
  #expect(TaskDisplayText.status(.completed) == "Completed")
}

@Test
func mobileTaskDisplayTextUsesUserFacingLabels() {
  #expect(MobileTaskDisplayText.priority(.p3) == "Low")
  #expect(MobileTaskDisplayText.status(.cancelled) == "Cancelled")
}
