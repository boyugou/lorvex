import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

// The lists and the habits on iPhone and iPad move one place up or down from
// a row's menu; the new order is the core's order.

@MainActor
private func makeStore() async throws -> (store: MobileStore, core: any LorvexCoreServicing) {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()
  return (store, core)
}

@Test("A move swaps a row with its neighbour and refuses past either end")
func mobileReorderDirectionSwapsWithTheNeighbour() {
  let order = ["a", "b", "c"]
  #expect(MobileReorderDirection.moved("b", in: order, .up) == ["b", "a", "c"])
  #expect(MobileReorderDirection.moved("b", in: order, .down) == ["a", "c", "b"])
  #expect(MobileReorderDirection.moved("a", in: order, .up) == nil)
  #expect(MobileReorderDirection.moved("c", in: order, .down) == nil)
  #expect(MobileReorderDirection.moved("x", in: order, .up) == nil)
  #expect(MobileReorderDirection.moved("a", in: ["a"], .down) == nil)
}

@MainActor
@Test("Moving a list down saves the order the core then reports")
func mobileMovingAListSavesTheOrder() async throws {
  let (store, core) = try await makeStore()
  let personal = try await core.createList(name: "Personal", description: nil)
  await store.refresh()
  let before = try #require(store.lists).lists.map(\.id)
  let first = try #require(before.first)
  #expect(before.count >= 3)

  #expect(await store.moveList(first, .down))

  let after = try #require(store.lists).lists.map(\.id)
  #expect(after == MobileReorderDirection.moved(first, in: before, .down))
  #expect(try await core.loadLists().lists.map(\.id) == after)
  #expect(after.contains(personal.id))
  #expect(store.errorMessage == nil)
}

@MainActor
@Test("A list at either end of the order stays put")
func mobileMovingAListPastAnEndChangesNothing() async throws {
  let (store, core) = try await makeStore()
  let order = try #require(store.lists).lists.map(\.id)

  #expect(await store.moveList(try #require(order.first), .up) == false)
  #expect(await store.moveList(try #require(order.last), .down) == false)
  #expect(await store.moveList("no-such-list", .up) == false)

  #expect(try await core.loadLists().lists.map(\.id) == order)
}

@MainActor
@Test("Moving a habit saves the order the core then reports")
func mobileMovingAHabitSavesTheOrder() async throws {
  let (store, core) = try await makeStore()
  let before = try #require(store.habits).habits.filter { !$0.archived }.map(\.id)
  let first = try #require(before.first)
  #expect(before.count >= 2)

  #expect(await store.moveHabit(first, .down))

  let after = try #require(store.habits).habits.filter { !$0.archived }.map(\.id)
  #expect(after == MobileReorderDirection.moved(first, in: before, .down))
  let saved = try await core.loadHabits(date: "2026-05-23").habits.filter { !$0.archived }
  #expect(saved.map(\.id) == after)
  #expect(await store.moveHabit(first, .up))
  #expect(try #require(store.habits).habits.filter { !$0.archived }.map(\.id) == before)
  #expect(await store.moveHabit(try #require(before.first), .up) == false)
}

@Test("The lists and habits rows offer the moves in their menus and to VoiceOver")
func mobileRowsOfferTheMoves() throws {
  let sources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Sources/LorvexMobile")
  let lists = try String(
    contentsOf: sources.appending(path: "MobileStoreTasksHomeView.swift"), encoding: .utf8)
  #expect(lists.contains("MobileReorderMenuItems("))
  #expect(lists.contains(".mobileReorderActions("))
  #expect(lists.contains("store.moveList(list.id, direction)"))

  let habits = try String(
    contentsOf: sources.appending(path: "MobileStoreHabitsView.swift"), encoding: .utf8)
  #expect(habits.contains("MobileReorderMenuItems("))
  #expect(habits.contains(".mobileReorderActions("))
  #expect(habits.contains("store.moveHabit(habit.id, direction)"))
  // A search hides habits between the rows shown, so the moves are withheld.
  #expect(habits.contains("!isFilteringHabits\n      && MobileReorderDirection.moved("))
  #expect(habits.contains("if !isFilteringHabits {"))
}

@Test("The compact Habits list on iPhone offers the moves too, and withholds them during a search")
func mobileCompactHabitRowsOfferTheMoves() throws {
  let sources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Sources/LorvexMobile")
  let section = try String(
    contentsOf: sources.appending(path: "MobileStoreHabitSection.swift"), encoding: .utf8)
  #expect(section.contains("MobileReorderMenuItems("))
  #expect(section.contains(".mobileReorderActions("))
  #expect(section.contains("let isFiltering = LorvexCatalogSearch.isFiltering(searchQuery)"))
  #expect(section.contains("moves: isFiltering\n              ? nil"))
  let habits = try String(
    contentsOf: sources.appending(path: "MobileStoreHabitsView.swift"), encoding: .utf8)
  let compact = try #require(habits.range(of: "MobileStoreHabitsSection("))
  #expect(habits[compact.lowerBound...].prefix(1200).contains("move: move,"))
}

@Test("Only a query with something besides whitespace narrows a catalog")
func catalogSearchFilteringIgnoresWhitespace() {
  #expect(!LorvexCatalogSearch.isFiltering(""))
  #expect(!LorvexCatalogSearch.isFiltering("  \n\t "))
  #expect(LorvexCatalogSearch.isFiltering("run"))
  #expect(LorvexCatalogSearch.isFiltering("  run "))
}
