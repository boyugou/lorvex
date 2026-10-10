import SwiftUI
import Testing

@testable import LorvexMobile

/// Every row of a list can carry a delete confirmation over one shared
/// optional: a row's dialog shows while the optional holds that row's item, and
/// a row closing its own dialog never clears another row's request.
@MainActor
@Suite("Delete confirmation item binding")
struct MobileDeleteConfirmationTests {
  private struct Item: Identifiable, Sendable {
    let id: Int
    var name: String
  }

  /// An optional source with a plain `Binding` over it, the shape of a
  /// `@State` pending-deletion property.
  private final class Pending: @unchecked Sendable {
    var item: Item?

    init(_ item: Item? = nil) { self.item = item }

    var binding: Binding<Item?> {
      Binding(get: { self.item }, set: { self.item = $0 })
    }
  }

  private let first = Item(id: 1, name: "First")
  private let second = Item(id: 2, name: "Second")

  @Test("The flag is off while nothing is pending")
  func offWhileNothingPending() {
    let pending = Pending()
    #expect(!pending.binding.isHolding(first).wrappedValue)
  }

  @Test("The flag is on only for the pending item")
  func onOnlyForThePendingItem() {
    let pending = Pending(first)
    #expect(pending.binding.isHolding(first).wrappedValue)
    #expect(!pending.binding.isHolding(second).wrappedValue)
  }

  @Test("Turning the flag on stores the item")
  func turningOnStoresTheItem() {
    let pending = Pending()
    pending.binding.isHolding(second).wrappedValue = true
    #expect(pending.item?.id == second.id)
  }

  @Test("Turning the flag off clears the item it holds")
  func turningOffClearsTheHeldItem() {
    let pending = Pending(first)
    pending.binding.isHolding(first).wrappedValue = false
    #expect(pending.item == nil)
  }

  @Test("Turning the flag off leaves another row's request alone")
  func turningOffLeavesAnotherRowsRequest() {
    let pending = Pending(second)
    pending.binding.isHolding(first).wrappedValue = false
    #expect(pending.item?.id == second.id)
  }

  @Test("The flag follows the item's identity, not its other fields")
  func followsIdentity() {
    let pending = Pending(first)
    var renamed = first
    renamed.name = "Renamed"
    #expect(pending.binding.isHolding(renamed).wrappedValue)
  }
}
