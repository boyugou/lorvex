import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// The inline quick-add row clears its field the moment Return is pressed, so a
// create that fails has to give the line back: the store reports whether the
// task was created, and the row restores the line only into an empty field.

@Suite("Inline quick add keeps a line that was not created")
struct QuickAddRowRestoreTests {
  @MainActor
  @Test("the store reports a failed create, then a successful retry")
  func inlineCreateReportsWhetherTheTaskWasCreated() async throws {
    let core = StubCoreService(preview: try await makeSeededInMemoryCore())
    let store = AppStore(core: core)
    await store.refresh()
    core.createTaskError = .validation(field: "title", message: "Injected capture failure.")

    let failed = await store.createInlineTask("Pay the invoice", destination: .inbox)

    #expect(!failed)
    let open = try await core.preview.listTasks(
      status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
    #expect(!open.tasks.contains { $0.title == "Pay the invoice" })
    #expect(store.errorMessage != nil)

    core.createTaskError = nil
    let created = await store.createInlineTask("Pay the invoice", destination: .inbox)

    #expect(created)
    let after = try await core.preview.listTasks(
      status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
    #expect(after.tasks.contains { $0.title == "Pay the invoice" })
  }

  @MainActor
  @Test("a blank line is not a created task")
  func aBlankInlineLineIsNotCreated() async throws {
    let store = AppStore(core: try await makeSeededInMemoryCore())
    await store.refresh()

    let created = await store.createInlineTask("   ", destination: .inbox)

    #expect(!created)
    #expect(store.errorMessage == nil)
  }

  @Test("a failed create puts the line back into an empty field")
  func aFailedCreateRestoresTheLineIntoAnEmptyField() {
    #expect(
      QuickAddRow.restoredTitle(submitted: "Call the caterer", created: false, current: "")
        == "Call the caterer")
  }

  @Test("a failed create never overwrites the next line already being typed")
  func aFailedCreateLeavesTheNextLineAlone() {
    #expect(
      QuickAddRow.restoredTitle(submitted: "Call the caterer", created: false, current: "Book")
        == nil)
    #expect(
      QuickAddRow.restoredTitle(submitted: "Call the caterer", created: false, current: " ")
        == nil)
  }

  @Test("a created task leaves the field as it is")
  func aCreatedTaskRestoresNothing() {
    #expect(QuickAddRow.restoredTitle(submitted: "Call the caterer", created: true, current: "") == nil)
    #expect(
      QuickAddRow.restoredTitle(submitted: "Call the caterer", created: true, current: "Book")
        == nil)
  }
}
