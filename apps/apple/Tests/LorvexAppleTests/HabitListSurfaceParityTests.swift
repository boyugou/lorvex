import Foundation
import Testing

/// Surfaces that draw the same habit or list fact use the same answer: the
/// habit's identity color, the list's fallback icon, the menu wording of Reset
/// Today, and the Inbox's display name.
private func source(_ path: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  return try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

@Test
func commandPaletteHabitRowWearsTheHabitsIdentityColor() throws {
  let row = try source("Sources/LorvexApple/Views/CommandPaletteResultRow.swift")
  #expect(row.contains("LorvexHabitPalette.baseColor(id: habitID, color: colorHex)"))
  #expect(!row.contains(".foregroundStyle(Color(lorvexHex: colorHex) ?? .accentColor)"))
}

@Test
func aListWithoutAnIconIsAFolderInTheSheetAndTheMoveMenuAsEverywhereElse() throws {
  let sheet = try source("Sources/LorvexApple/Views/ListFormFields.swift")
  #expect(sheet.contains("defaultIcon: \"folder\","))
  let icons = try source("Sources/LorvexApple/Views/LorvexListIconView.swift")
  let menu = try #require(icons.range(of: "struct LorvexListMenuLabel: View"))
  #expect(String(icons[menu.lowerBound...]).contains("Label(list.displayName, systemImage: \"folder\")"))
  #expect(!icons.contains("\"list.bullet\""))
}

@Test
func habitCardContextMenuSaysResetTodayInTheMenuCasing() throws {
  let card = try source("Sources/LorvexApple/Views/HabitMomentumCard.swift")
  let menu = try #require(card.range(of: "private var contextMenu: some View"))
  #expect(String(card[menu.lowerBound...].prefix(400)).contains("habits.row.reset_today.title_case"))
}

@Test
func listScopedWidgetHeadlineNamesTheInboxInTheInterfaceLanguage() throws {
  let builder = try source("Sources/LorvexWidgetKitSupport/WidgetRenderModelBuilder.swift")
  #expect(builder.contains("LorvexListNaming.displayName(id: scope.id, name: scope.name)"))
}

@Test
func watchHabitsAreTheSharedHabitTileInTheHabitsIdentityColor() throws {
  let page = try source("Sources/LorvexWatch/LorvexWatchHabitsPage.swift")
  #expect(page.contains("LorvexHabitRingTile("))
  #expect(page.contains("LorvexHabitPalette.baseColor(id: habit.id, color: habit.color)"))
  #expect(!page.contains("LorvexTaskRing("))
}
