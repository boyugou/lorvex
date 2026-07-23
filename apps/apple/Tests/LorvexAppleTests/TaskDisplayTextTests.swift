import LorvexApple
import LorvexCore
import LorvexMobile
import Testing

@Test
func taskDisplayTextUsesUserFacingLabels() {
  #expect(TaskDisplayText.priority(.p1) == "Priority 1")
  #expect(TaskDisplayText.compactPriority(.p1) == "P1")
  #expect(TaskDisplayText.status(.completed) == "Completed")
  #expect(TaskDisplayText.priorityAndStatus(priority: .p2, status: .someday) == "Priority 2 · Someday")
  #expect(TaskDisplayText.compactPriorityAndStatus(priority: .p2, status: .someday) == "P2 · Someday")
}

@Test
func mobileTaskDisplayTextUsesUserFacingLabels() {
  #expect(MobileTaskDisplayText.priority(.p3) == "Priority 3")
  #expect(MobileTaskDisplayText.compactPriority(.p3) == "P3")
  #expect(MobileTaskDisplayText.status(.cancelled) == "Cancelled")
  #expect(MobileTaskDisplayText.compactPriorityAndStatus(priority: .p1, status: .open) == "P1 · Open")
}
