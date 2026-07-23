import LorvexCore
import SwiftUI

/// A habit milestone the user just crossed, staged for the celebration overlay.
/// A fresh `id` per crossing lets the overlay re-animate even when the same
/// milestone value recurs (e.g. toggling a day off and on again).
struct HabitMilestoneCelebration: Identifiable, Equatable {
  let id = UUID()
  var habitName: String
  /// The crossed milestone value (streak length or cumulative completion count).
  var milestone: Int
  /// `HabitMilestoneInfo.metric` wire string (`"streak"` / `"count"`).
  var metric: String
  var frequencyType: String
  var tint: Color
}

/// The floating badge shown when a completion crosses a milestone: a laurel-
/// wreathed number beside the metric-labeled habit line, on the app's floating
/// glass. Springs in with a one-shot sparkle, and reads instantly under Reduce
/// Motion (no scale or symbol animation).
struct HabitMilestoneCelebrationCard: View {
  let celebration: HabitMilestoneCelebration
  let reduceMotion: Bool
  /// Render a plain material instead of Liquid Glass. The app always uses glass;
  /// only the `ImageRenderer` snapshot dump sets this, because glass vibrancy
  /// drops dynamic-color text under offscreen rendering.
  var flat = false
  @State private var appeared = false

  private var subtitle: String {
    HabitDisplayText.milestoneReachedSubtitle(
      milestone: celebration.milestone, metric: celebration.metric,
      frequencyType: celebration.frequencyType, habitName: celebration.habitName)
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: LorvexDesign.Radius.m, style: .continuous)
  }

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      badge
      VStack(alignment: .leading, spacing: 2) {
        Text(LocalizedStringResource(
          "habits.milestone.celebration.title", defaultValue: "Milestone reached!",
          table: "Localizable",
          bundle: LorvexL10n.bundle))
          .font(LorvexDesign.Typography.primaryEmphasis)
          .foregroundStyle(.primary)
        Text(subtitle)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, LorvexDesign.Spacing.l)
    .padding(.vertical, LorvexDesign.Spacing.m)
    .modifier(CelebrationChrome(shape: shape, flat: flat))
    .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.92))
    .task {
      guard !reduceMotion else { return }
      withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { appeared = true }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("habit.milestone.celebration")
  }

  private var badge: some View {
    HStack(spacing: 1) {
      Image(systemName: "laurel.leading")
      Text("\(celebration.milestone)")
        .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
      Image(systemName: "laurel.trailing")
    }
    .foregroundStyle(celebration.tint)
    .overlay(alignment: .topTrailing) {
      Image(systemName: "sparkles")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(celebration.tint)
        .offset(x: 7, y: -5)
        .opacity(reduceMotion ? 0 : 1)
        .symbolEffect(.bounce, value: appeared)
    }
  }
}

/// Floating chrome for the celebration badge: Liquid Glass in the app, a plain
/// bordered material for the snapshot dump (`flat`).
private struct CelebrationChrome: ViewModifier {
  let shape: RoundedRectangle
  let flat: Bool

  func body(content: Content) -> some View {
    if flat {
      content
        .background(.regularMaterial, in: shape)
        .overlay { shape.stroke(.separator.opacity(0.55), lineWidth: 1) }
        .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
    } else {
      content.lorvexFloatingGlass(in: shape)
    }
  }
}

struct HabitMilestoneCelebrationOverlay: ViewModifier {
  let celebration: HabitMilestoneCelebration?
  let dismiss: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .top) {
        if let celebration {
          HabitMilestoneCelebrationCard(celebration: celebration, reduceMotion: reduceMotion)
            .padding(.top, LorvexDesign.Spacing.l)
            .transition(
              reduceMotion
                ? .opacity
                : .scale(scale: 0.85).combined(with: .opacity)
                  .combined(with: .move(edge: .top)))
            .onTapGesture(perform: dismiss)
            .task(id: celebration.id) {
              try? await Task.sleep(for: .seconds(2.8))
              dismiss()
            }
        }
      }
      // The overlay never pulls VoiceOver focus, so announce the milestone when a
      // new celebration is staged (mirrors the toast's announcement).
      .onChange(of: celebration?.id) { _, newValue in
        guard newValue != nil, let celebration else { return }
        AccessibilityNotification.Announcement(
          HabitDisplayText.milestoneReachedSubtitle(
            milestone: celebration.milestone, metric: celebration.metric,
            frequencyType: celebration.frequencyType, habitName: celebration.habitName)
        ).post()
      }
  }
}

extension View {
  /// Overlays the transient milestone-celebration badge, driven by an optional
  /// staged celebration. Pass `nil` to hide it; `dismiss` clears the staged value
  /// (tap or auto-dismiss). Insertion / removal animation is supplied by the
  /// caller that sets and clears the value through the Reduce-Motion helpers.
  func lorvexMilestoneCelebration(
    _ celebration: HabitMilestoneCelebration?, dismiss: @escaping () -> Void
  ) -> some View {
    modifier(HabitMilestoneCelebrationOverlay(celebration: celebration, dismiss: dismiss))
  }
}
