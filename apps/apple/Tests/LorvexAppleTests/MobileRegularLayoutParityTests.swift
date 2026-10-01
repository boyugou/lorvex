import Foundation
import Testing

/// Source-level guards for the decisions that keep the iPad layout in step with
/// the phone and legible in dark mode: one Today structure, Habits and Memory
/// reached from the Tasks home, destructive Settings buttons tinted whole, and
/// scheme-aware alpha on tinted progress tracks.
@Suite("Mobile regular-width parity")
struct MobileRegularLayoutParityTests {
  private var packageRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func mobileSource(_ path: String) throws -> String {
    try String(
      contentsOf: packageRoot.appending(path: "Sources/LorvexMobile/\(path)"), encoding: .utf8)
  }

  private func coreSource(_ path: String) throws -> String {
    try String(
      contentsOf: packageRoot.appending(path: "Sources/LorvexCore/\(path)"), encoding: .utf8)
  }

  @Test("The regular Today is the task list beside a standing schedule pane")
  func regularTodayIsTheTaskListBesideTheSchedule() throws {
    let today = try mobileSource("MobileStoreTodayView.swift")
    #expect(today.contains("todayList(openSchedule: nil)"))
    #expect(
      today.contains(
        "MobileTodayScheduleList(\n          store: store,\n          openTask:"))
    #expect(today.contains("today.schedulePane"))
    #expect(!today.contains("MobileStoreTodayRegularView"))

    let sheet = try mobileSource("MobileTodayScheduleSheet.swift")
    #expect(sheet.contains("struct MobileTodayScheduleList: View"))
    #expect(sheet.contains("MobileTodayScheduleList(\n        store: store"))

    #expect(!today.contains("static func todayTasks(from snapshot:"))

    let habitSection = try mobileSource("MobileStoreHabitSection.swift")
    #expect(habitSection.contains("\nstruct MobileHabitRow: View {"))
    #expect(!habitSection.contains("private struct MobileHabitRow"))
  }

  @Test("Today's date is drawn once")
  func todayDateIsDrawnOnce() throws {
    // Today opens with its own date line, so the bar draws no date subtitle.
    let root = try mobileSource("LorvexMobileStoreRootView.swift")
    let page = try mobileSource("MobileTodayPage.swift")
    #expect(!root.contains(".navigationSubtitle(MobileTodayHeader.dateText())"))
    #expect(page.contains("MobileTodayCalmCopy.dateLine(logicalDay: store.logicalTodayString)"))

    let header = try mobileSource("MobileTodayHeader.swift")
    #expect(header.contains("enum MobileTodayHeader"))
    #expect(!header.contains(": View"))
  }

  @Test("The first-load skeleton is shaped like Today: a header, then one untitled list")
  func firstLoadSkeletonMirrorsToday() throws {
    let source = try mobileSource("MobileSkeletonLoading.swift")
    let start = try #require(source.range(of: "struct MobileInitialWorkspaceSkeleton"))
    let rest = source[start.upperBound...]
    let skeleton = rest[..<(rest.range(of: "\nprivate struct ")?.lowerBound ?? rest.endIndex)]
    #expect(!skeleton.contains("today.section."))
    #expect(!skeleton.contains("Section(String("))
    #expect(skeleton.contains("MobileSkeletonRows(count: 4)"))
  }

  @Test("The Tasks home reaches Habits and Memory, which have no tab")
  func tasksHomeReachesHabitsAndMemory() throws {
    let home = try mobileSource("MobileStoreTasksHomeView.swift")
    #expect(home.contains("mobileTasks.habits"))
    #expect(home.contains("mobileTasks.memory"))
  }

  @Test("List action rows colour their icon and title together")
  func listActionRowsCarryTheSharedStyles() throws {
    // SwiftUI colours a row button's title from state it never applies to the
    // Label's icon: the destructive role reddens the title alone, and disabling
    // drops the title to the default text color while the icon stays accent. A
    // row that skips the shared style therefore renders in two colours.
    let style = try mobileSource("MobileListRowActionStyles.swift")
    #expect(style.contains("func mobileDestructiveRowStyle() -> some View"))
    #expect(style.contains("foregroundStyle(LorvexDesign.Palette.destructive)"))
    #expect(style.contains("func mobileAccentRowStyle() -> some View"))
    #expect(style.contains("foregroundStyle(LorvexDesign.Palette.accent)"))

    for file in [
      "MobileStoreLocalDataResetSection.swift", "MobileSettingsSections.swift",
      "MobileStoreEditCalendarEventSheet.swift",
    ] {
      #expect(try mobileSource(file).contains(".mobileDestructiveRowStyle()"), "\(file)")
    }

    // The task action tiles colour icon and name with one tint, and dim as a
    // whole when disabled, so a tile never renders in two colours.
    let actions = try mobileSource("MobileTaskActionViews.swift")
    #expect(actions.contains(".foregroundStyle(tint)"))
    #expect(actions.contains(".opacity(isEnabled ? 1 : 0.45)"))
    #expect(actions.contains("tint: LorvexDesign.Palette.destructive"))

    // The busy spinner is an overlay on the row, never a replacement label:
    // swapping the label out would resize the row mid-flight.
    let reset = try mobileSource("MobileStoreLocalDataResetSection.swift")
    #expect(reset.contains("if resetInProgress { ProgressView() }"))
    let cloud = try mobileSource("MobileSettingsSections.swift")
    #expect(cloud.contains("if deleteCloudInProgress { ProgressView() }"))
  }

  @Test("Tinted tracks and muted glyphs follow the color scheme")
  func tintedTracksFollowTheColorScheme() throws {
    let palette = try coreSource("Support/LorvexDesignSystem.swift")
    #expect(palette.contains("func trackOpacity(for colorScheme: ColorScheme) -> Double"))

    for file in [
      "MobileHabitVisualizationSection.swift", "MobileHabitMilestoneProgressView.swift",
    ] {
      let source = try mobileSource(file)
      #expect(source.contains("LorvexDesign.Palette.trackOpacity(for: colorScheme)"), "\(file)")
      #expect(!source.contains("tint.opacity(0.18)"), "\(file)")
      #expect(!source.contains("tint.opacity(0.16)"), "\(file)")
    }

    // The check-in ring's track is the whole control until something is logged,
    // so it is neutral: a tinted wash vanishes for deep hues on a dark card and
    // for every hue on a light one.
    let ring = try mobileSource("MobileProgressRing.swift")
    #expect(ring.contains(".stroke(.tertiary, lineWidth: lineWidth)"))
    #expect(!ring.contains("tint.opacity("))

    // A rating dot that is not chosen is a hollow ring in the secondary style:
    // never the accent at a reduced alpha, which reads as half-chosen, and
    // never a pale fill, which reads as disabled.
    let rating = try coreSource("Support/LorvexReviewCalm.swift")
    #expect(rating.contains("Circle().strokeBorder(.secondary, lineWidth: 1.5)"))
    #expect(!rating.contains("accent.opacity("))
    #expect(!rating.contains("insetFill"))
  }

  @Test("The compact milestone line drops parts instead of truncating")
  func milestoneLineNeverTruncatesItsLabels() throws {
    let milestone = try mobileSource("MobileHabitMilestoneProgressView.swift")
    #expect(milestone.contains("ViewThatFits(in: .horizontal)"))
    // The bar belongs to the detail style alone. Sizing one from the width the
    // compact row's text left over showed it on some catalog rows and not the
    // next, which reads as a glitch rather than as a difference in the data.
    #expect(milestone.components(separatedBy: "MobileMilestoneBar(").count == 2)
  }
}
