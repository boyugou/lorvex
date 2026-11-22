import LorvexCore
import SwiftUI

struct ReviewJournalBrowser: View {
  let store: AppStore
  let query: String
  let opened: () -> Void
  let editorFocus: @MainActor @Sendable (Bool) -> Void

  @State private var matches: [ReviewJournalMatch] = []
  @State private var nextThrough: String?
  @State private var through: String?
  @State private var loading = true
  @State private var failed = false
  @State private var retry = 0
  @State private var dayRequest: String?
  @State private var reading = false

  static var searchPrompt: String {
    String(localized: "review.journal.search", defaultValue: "Search Journal", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  private static var resultsTitle: String {
    String(localized: "review.journal.results", defaultValue: "Search Results", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  var body: some View {
    ZStack {
      results
        .opacity(reading ? 0 : 1)
        .accessibilityHidden(reading)
        .disabled(reading || dayRequest != nil)
      if reading {
        VStack(alignment: .leading, spacing: 0) {
          Button {
            Task { await returnToResults() }
          } label: {
            Label(Self.resultsTitle, systemImage: "chevron.backward")
          }
          .buttonStyle(.link)
          .keyboardShortcut("[", modifiers: .command)
          .accessibilityIdentifier("review.search.back")
          .padding(.horizontal, LorvexDesign.Spacing.xl)
          .padding(.vertical, LorvexDesign.Spacing.s)
          Divider()
          DailyReviewForm(store: store, date: store.selectedReviewDate,
            isReadOnly: !store.selectedReviewDayIsEditable, onEditorFocusChange: editorFocus)
            .id(store.selectedReviewDate)
        }
      }
    }
    .task(id: "\(through ?? "")|\(retry)") { await load() }
    .task(id: dayRequest) {
      guard let dayRequest else { return }
      if await store.selectReviewDay(dayRequest), !Task.isCancelled {
        opened()
        reading = true
      }
      if self.dayRequest == dayRequest { self.dayRequest = nil }
    }
  }

  private var results: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Label(Self.resultsTitle, systemImage: "text.magnifyingglass")
          .font(LorvexDesign.Typography.primaryEmphasis)
          .foregroundStyle(.secondary)
        Text(verbatim: query)
          .font(.system(.largeTitle, design: .serif).weight(.semibold))
          .textSelection(.enabled)
          .padding(.top, LorvexDesign.Spacing.xs)
          .padding(.bottom, LorvexDesign.Spacing.l)
        Divider()
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(matches) { match in
            Button { dayRequest = match.date } label: {
              VStack(alignment: .leading, spacing: LorvexDesign.Spacing.sm) {
                let day = LorvexDateFormatters.ymdUTC.date(from: match.date)
                ViewThatFits(in: .horizontal) {
                  HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.m) {
                    dateLabel(day, fallback: match.date)
                    fieldLabel(match.field)
                  }
                  VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
                    dateLabel(day, fallback: match.date)
                    fieldLabel(match.field)
                  }
                }
                Text(match.excerpt)
                  .font(LorvexDesign.Typography.primaryText)
                  .lineLimit(3)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, LorvexDesign.Spacing.m)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("review.search.day.\(match.date)")
            Divider()
          }
          if loading {
            ProgressView().controlSize(.small).padding(.vertical)
          } else if failed {
            Button(String(localized: "common.try_again", defaultValue: "Try Again", table: "Localizable",
              bundle: LorvexL10n.bundle)) { retry += 1 }.padding(.vertical)
          } else if let nextThrough {
            Button(String(localized: "tasks.results.load_more", defaultValue: "Load More", table: "Localizable",
              bundle: LorvexL10n.bundle)) { through = nextThrough }.padding(.vertical)
          } else if matches.isEmpty {
            LorvexEmptyStatePanel(
              title: String(localized: "command_palette.empty.no_results", defaultValue: "No results",
                table: "Localizable", bundle: LorvexL10n.bundle),
              message: String(localized: "calendar.search.empty_message",
                defaultValue: "Check the spelling or try a different search.",
                table: "Localizable", bundle: LorvexL10n.bundle),
              systemImage: "magnifyingglass", tint: .secondary, style: .inline
            ) { EmptyView() }
          }
        }
      }
      .frame(maxWidth: 660, alignment: .leading)
      .padding(LorvexDesign.Spacing.xl)
      .frame(maxWidth: .infinity)
    }
    .accessibilityIdentifier("review.search.results")
  }

  private func dateLabel(_ day: Date?, fallback: String) -> some View {
    Text(verbatim: day.map {
      $0.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: .gmt))
    } ?? fallback)
    .font(LorvexDesign.Typography.detailTitle)
  }

  private func fieldLabel(_ field: ReviewJournalMatch.Field) -> some View {
    Text(fieldTitle(field)).font(LorvexDesign.Typography.secondaryText).foregroundStyle(.secondary)
  }

  private func returnToResults() async {
    await store.flushDailyReviewDraftIfNeeded()
    guard store.dailyReviewDraftMatchesLoaded else { return }
    if let index = matches.firstIndex(where: { $0.date == store.selectedReviewDate }) {
      if let entry = store.dailyReview, let revised = ReviewJournalMatch.find(query, in: entry) {
        matches[index] = revised
      } else {
        matches.remove(at: index)
      }
    }
    editorFocus(false)
    reading = false
  }

  private func load() async {
    loading = true
    failed = false
    if through == nil {
      guard await LorvexSearchDebounce.shouldSearch(query) else { return }
      await store.flushDailyReviewDraftIfNeeded()
      guard !Task.isCancelled else { return }
      guard store.dailyReviewDraftMatchesLoaded else { failed = true; loading = false; return }
    }
    do {
      let page = try await store.core.searchReviewJournal(query, through: through ?? store.logicalTodayDateString)
      guard !Task.isCancelled else { return }
      if let through {
        matches.removeAll { $0.date <= through }
      } else {
        matches.removeAll()
      }
      matches.append(contentsOf: page.matches)
      nextThrough = page.nextThrough
    } catch {
      guard !Task.isCancelled else { return }
      failed = true
      await store.presentUserFacingError(error)
    }
    loading = false
  }

  private func fieldTitle(_ field: ReviewJournalMatch.Field) -> String {
    switch field {
    case .note: ReviewCalmCopy.noteLabel
    case .wins: ReviewCalmCopy.winsLabel
    case .blockers: ReviewCalmCopy.blockersLabel
    case .learnings: ReviewCalmCopy.learningsLabel
    }
  }
}

private struct DetachedReviewFindKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var findInDetachedReview: (() -> Void)? {
    get { self[DetachedReviewFindKey.self] }
    set { self[DetachedReviewFindKey.self] = newValue }
  }
}

struct DetachedReviewWorkspace: View {
  let store: AppStore
  @State private var query = ""
  @FocusState private var searchFocused: Bool

  var body: some View {
    ReviewsWorkspaceView(store: store, windowQuery: query)
      .searchable(text: $query, placement: .toolbar, prompt: Text(ReviewJournalBrowser.searchPrompt))
      .searchFocused($searchFocused)
      .focusedSceneValue(\.findInDetachedReview, { searchFocused = true })
  }
}
