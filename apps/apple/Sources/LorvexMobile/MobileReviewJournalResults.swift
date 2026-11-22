import LorvexCore
import SwiftUI

struct MobileReviewJournalResults: View {
  let store: MobileStore
  let phrase: String
  let editDay: (String) async -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var matches: [ReviewJournalMatch] = []
  @State private var nextThrough: String?
  @State private var through: String?
  @State private var attempt = 0
  @State private var loading = true
  @State private var failed = false
  @State private var reading: ReviewJournalMatch?

  var body: some View {
    List {
      ForEach(matches) { match in
        Button { reading = match } label: {
          HStack(spacing: LorvexDesign.Spacing.s) {
            VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
              ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) { heading(match) }
                VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) { heading(match) }
              }
              Text(match.excerpt).font(.body).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.footnote).foregroundStyle(.tertiary)
              .accessibilityHidden(true)
          }
          .padding(.vertical, LorvexDesign.Spacing.xs)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("review.search.day.\(match.date)")
      }
      if loading {
        ProgressView().listRowSeparator(.hidden)
      } else if failed {
        Button(String(localized: "common.try_again", defaultValue: "Try Again",
          table: "Localizable", bundle: MobileL10n.bundle)) { attempt += 1 }
      } else if let nextThrough {
        Button(String(localized: "tasks.results.load_more", defaultValue: "Load More",
          table: "Localizable", bundle: MobileL10n.bundle)) { through = nextThrough }
        .accessibilityIdentifier("review.search.more")
      } else if matches.isEmpty {
        MobileEmptyState.search(text: phrase).listRowSeparator(.hidden)
      }
    }
    .listStyle(.plain)
    .mobileReadableWidth()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.background)
    .scrollDismissesKeyboard(.interactively)
    .task(id: "\(through ?? "")|\(attempt)") { await loadPage() }
    .sheet(item: $reading) { match in
      MobileJournalReader(store: store, date: match.date, editDay: editDay)
    }
  }

  private func loadPage() async {
    loading = true
    failed = false
    if through == nil {
      guard await LorvexSearchDebounce.shouldSearch(phrase) else { return }
      let saved = await store.flushDailyReviewDraftIfNeeded()
      guard !Task.isCancelled else { return }
      guard saved && store.dailyReviewDraftMatchesLoaded else { failed = true; loading = false; return }
    }
    do {
      let page = try await store.core.searchReviewJournal(phrase, through: through ?? store.logicalTodayString)
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

  @ViewBuilder private func heading(_ match: ReviewJournalMatch) -> some View {
    Text(verbatim: journalDate(match.date)).font(.headline)
    Text(fieldTitle(match.field)).font(.subheadline).foregroundStyle(.secondary)
  }

  private func fieldTitle(_ field: ReviewJournalMatch.Field) -> String {
    switch field {
    case .note: MobileReviewCalmCopy.noteLabel
    case .wins: MobileReviewCalmCopy.winsLabel
    case .blockers: MobileReviewCalmCopy.blockersLabel
    case .learnings: MobileReviewCalmCopy.learningsLabel
    }
  }
}

private func journalDate(_ date: String) -> String {
  LorvexDateFormatters.ymdUTC.date(from: date)?.formatted(
    Date.FormatStyle(date: .long, time: .omitted, timeZone: .gmt)) ?? date
}

/// Reading an entry leaves the original Day or Week in place. Only Edit changes
/// the selected day in the workspace's editor.
private struct MobileJournalReader: View {
  let store: MobileStore
  let date: String
  let editDay: (String) async -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var entry: DailyReviewEntry?
  @State private var loading = true
  @State private var failed = false
  @State private var attempt = 0

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
          Text(journalDate(date), serifVoice: .pageSentence)
            .accessibilityAddTraits(.isHeader)
          if let entry {
            LorvexJournalEntryBody(review: entry, feeling: MobileReviewCalmCopy.feelWord,
              energy: MobileReviewCalmCopy.energyWord)
          } else if loading {
            ProgressView()
          } else if failed {
            Button(String(localized: "common.try_again", defaultValue: "Try Again",
              table: "Localizable", bundle: MobileL10n.bundle)) { attempt += 1 }
          } else {
            Text(String(localized: "reviews.daily.readonly_empty", defaultValue: "No review was written on this day.",
              table: "Localizable", bundle: MobileL10n.bundle))
          }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .padding(LorvexDesign.Spacing.l)
        .frame(maxWidth: .infinity)
      }
      .mobileSheetTitle(MobileTab.review.title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: "common.done", defaultValue: "Done", table: "Localizable",
            bundle: MobileL10n.bundle)) { dismiss() }
          .accessibilityIdentifier("review.search.done")
        }
        if entry != nil, DailyReviewEntry.canEdit(on: date, today: store.logicalTodayString) {
          ToolbarItem(placement: .primaryAction) {
            Button(String(localized: "common.edit", defaultValue: "Edit", table: "Localizable",
              bundle: MobileL10n.bundle)) { Task { await editDay(date) } }
            .accessibilityIdentifier("review.search.edit")
          }
        }
      }
    }
    .task(id: "\(store.reviewReadRevision)|\(attempt)") {
      loading = true
      failed = false
      do {
        let loaded = try await store.core.loadDailyReview(date: date)
        guard !Task.isCancelled else { return }
        entry = loaded
      } catch {
        guard !Task.isCancelled else { return }
        failed = true
        await store.presentUserFacingError(error)
      }
      loading = false
    }
  }
}
