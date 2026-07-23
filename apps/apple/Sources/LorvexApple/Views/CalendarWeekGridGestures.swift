import LorvexCore
import SwiftUI

/// Drag-to-move / resize / create gesture builders for `CalendarWeekGridView`,
/// plus the minute-of-day and date construction math they share with the grid
/// body. Kept as an extension on the view so the gestures read and write the
/// view's `@State` drag-preview drafts directly without threading bindings.
extension CalendarWeekGridView {
  /// Maps a Y-coordinate in the day column to a minute-of-day, clamped to
  /// `[0, 24*60-1]`.
  func minuteOfDay(forY y: CGFloat) -> Int {
    let clampedY = max(0, min(CGFloat(24) * hourHeight - 1, y))
    return Int(clampedY / hourHeight * 60)
  }

  /// Maps a Y-coordinate to a minute-of-day, snapped to the nearest `snapTo`
  /// minutes. When `roundingUp` is true (used for end-of-drag), rounds
  /// upward so a small drag still yields a non-zero block.
  func snappedMinute(
    forY y: CGFloat, snapTo: Int, roundingUp: Bool = false
  ) -> Int {
    let raw = minuteOfDay(forY: y)
    if roundingUp {
      return ((raw + snapTo - 1) / snapTo) * snapTo
    }
    return (raw / snapTo) * snapTo
  }

  /// Formats a minute-of-day (`0–1439`) as `"HH:mm"` for the in-flight
  /// drag-to-create preview's time-range label.
  static func hmLabel(minuteOfDay: Int) -> String {
    let m = max(0, min(24 * 60 - 1, minuteOfDay))
    return String(format: "%02d:%02d", m / 60, m % 60)
  }

  /// Drag-to-create gesture: press-and-drag on empty space sketches a
  /// translucent block; release commits a new event whose start is the
  /// earlier Y (snapped to 15 min) and duration is the drag span (snapped,
  /// minimum 15 min).
  func createGesture(for day: CalendarGridDay, dayIndex: Int) -> some Gesture {
    DragGesture(minimumDistance: Self.dragMinimumDistance)
      .onChanged { value in
        createDraft = CreateDraft(
          dayIndex: dayIndex,
          startY: value.startLocation.y,
          currentY: value.location.y)
      }
      .onEnded { value in
        defer { createDraft = nil }
        let topY = min(value.startLocation.y, value.location.y)
        let bottomY = max(value.startLocation.y, value.location.y)
        // Require a real vertical sweep (≥ one snap row) before committing a
        // drag-created event. A 6 pt twitch on what the user intended as a
        // tap-to-create would otherwise silently make a 15-min event at the
        // wrong duration; below the threshold we fall through to the
        // tap-to-create handler's behavior (60-min default at the hour).
        let dragHeight = bottomY - topY
        let snapRowHeight = hourHeight * CGFloat(Self.snapMinutes) / 60
        guard dragHeight >= snapRowHeight else {
          let minutes = minuteOfDay(forY: topY)
          createAt(day.date, (minutes / 60) * 60, 60)
          return
        }
        let rawStart = minuteOfDay(forY: topY)
        let rawEnd = minuteOfDay(forY: bottomY)
        let snap = Self.snapMinutes
        let snappedStart = (rawStart / snap) * snap
        // Round duration UP so a drag-end at 10:14 still yields a 15-min slot
        // (rather than collapsing to 0).
        let rawDuration = max(snap, rawEnd - snappedStart)
        let snappedDuration = ((rawDuration + snap - 1) / snap) * snap
        let clampedStart = max(0, min(24 * 60 - snappedDuration, snappedStart))
        createAt(day.date, clampedStart, snappedDuration)
      }
  }

  /// Move gesture: vertical drag shifts the start time; horizontal drag spans
  /// adjacent day columns. Visual preview updates `rescheduleDraft` while the
  /// finger is down; release commits via `store.rescheduleCalendarEvent`.
  func moveGesture(
    for block: CalendarGridTimedBlock,
    dayIndex: Int,
    totalDays: Int,
    columnWidth: CGFloat
  ) -> some Gesture {
    DragGesture(minimumDistance: Self.dragMinimumDistance)
      .onChanged { value in
        rescheduleDraft = RescheduleDraft(
          eventID: block.event.id,
          kind: .move,
          translation: value.translation,
          columnWidth: columnWidth)
      }
      .onEnded { value in
        let snap = Self.snapMinutes
        let totalMinutes = block.endMin - block.startMin
        let rawDeltaMin = Int((value.translation.height / hourHeight * 60).rounded())
        let snapped = (rawDeltaMin / snap) * snap
        let clampedStart = max(0, min(24 * 60 - totalMinutes, block.startMin + snapped))
        let deltaDays = columnWidth > 0
          ? Int((value.translation.width / columnWidth).rounded()) : 0
        let newDayIndex = max(0, min(totalDays - 1, dayIndex + deltaDays))
        let dayShift = newDayIndex - dayIndex
        clearRescheduleDraft()

        // Build the new start / end Dates from the displayed date + minute-of-day.
        let originalDayDate = calendar.date(
          byAdding: .day, value: dayIndex, to: weekStart) ?? weekStart
        let targetDayDate = calendar.date(
          byAdding: .day, value: dayShift, to: originalDayDate) ?? originalDayDate
        let startDate = dateAtMinute(of: targetDayDate, minute: clampedStart)
        let endDate = dateAtMinute(of: targetDayDate, minute: clampedStart + totalMinutes)
        // Drop a zero-movement drop so an accidental nudge doesn't fire a write.
        guard snapped != 0 || dayShift != 0 else { return }
        Task { @MainActor in
          await store.rescheduleCalendarEvent(block.event, newStart: startDate, newEnd: endDate)
        }
      }
  }

  /// The drag preview's release: whether the drop commits (a real move/resize)
  /// or the drop is rejected by the store's editable/all-day/recurring/multi-day
  /// guard, the preview always snaps back to the block's live layout at drop
  /// time — the store call is async and has no synchronous reject signal to
  /// react to differently. Animating this clear keeps that snap-back a settle
  /// rather than an abrupt disappearance, matching the rest of the app's
  /// motion bar for every other cleared draft state.
  private func clearRescheduleDraft() {
    lorvexAnimated(.snappy(duration: 0.18)) {
      rescheduleDraft = nil
    }
  }

  /// Resize gesture: vertical-only drag at the bottom edge of a block,
  /// preserving the start time and adjusting the end time. Snap + minimum
  /// duration are applied on commit.
  func resizeGesture(for block: CalendarGridTimedBlock) -> some Gesture {
    DragGesture(minimumDistance: Self.dragMinimumDistance)
      .onChanged { value in
        rescheduleDraft = RescheduleDraft(
          eventID: block.event.id,
          kind: .resize,
          translation: CGSize(width: 0, height: value.translation.height),
          columnWidth: 0)
      }
      .onEnded { value in
        let snap = Self.snapMinutes
        let rawDeltaMin = Int((value.translation.height / hourHeight * 60).rounded())
        let snapped = (rawDeltaMin / snap) * snap
        let newEndMin = max(
          block.startMin + Self.minimumBlockMinutes,
          min(24 * 60, block.endMin + snapped))
        clearRescheduleDraft()
        guard newEndMin != block.endMin else { return }
        let dayDate = calendar.date(byAdding: .day, value: 0, to: weekStart) ?? weekStart
        // Resize handles are disabled for multi-day clipped blocks; for
        // editable single-day blocks the event's own startDate remains the
        // authoritative day.
        let parsedDay = AppStore.ymdFormatter.date(from: block.event.startDate) ?? dayDate
        let startDate = dateAtMinute(of: parsedDay, minute: block.startMin)
        let endDate = dateAtMinute(of: parsedDay, minute: newEndMin)
        Task { @MainActor in
          await store.rescheduleCalendarEvent(block.event, newStart: startDate, newEnd: endDate)
        }
      }
  }

  /// Top-edge resize: vertical-only drag at the block's top edge. Adjusts
  /// `startTime` (earlier when dragging up, later when dragging down) and
  /// keeps `endTime` fixed. Snap + minimum 15-min duration are applied on
  /// commit; a drag that would invert start/end clamps at 15 min before the
  /// existing end.
  func resizeTopGesture(for block: CalendarGridTimedBlock) -> some Gesture {
    DragGesture(minimumDistance: Self.dragMinimumDistance)
      .onChanged { value in
        rescheduleDraft = RescheduleDraft(
          eventID: block.event.id,
          kind: .resizeTop,
          translation: CGSize(width: 0, height: value.translation.height),
          columnWidth: 0)
      }
      .onEnded { value in
        let snap = Self.snapMinutes
        let rawDeltaMin = Int((value.translation.height / hourHeight * 60).rounded())
        let snapped = (rawDeltaMin / snap) * snap
        // Negative drag (up) → earlier start; positive drag (down) → later start.
        let newStartMin = max(
          0,
          min(
            block.endMin - Self.minimumBlockMinutes,
            block.startMin + snapped))
        clearRescheduleDraft()
        guard newStartMin != block.startMin else { return }
        let parsedDay =
          AppStore.ymdFormatter.date(from: block.event.startDate) ?? weekStart
        let startDate = dateAtMinute(of: parsedDay, minute: newStartMin)
        let endDate = dateAtMinute(of: parsedDay, minute: block.endMin)
        Task { @MainActor in
          await store.rescheduleCalendarEvent(block.event, newStart: startDate, newEnd: endDate)
        }
      }
  }

  /// Combines a calendar day with a minute-of-day into an absolute `Date`.
  ///
  /// `minute == 1440` is the legitimate "end of this day / midnight on the
  /// next day" sentinel — the drag-to-resize bottom edge can produce it for
  /// a 23:00 → 24:00 expansion. Clamping the components to `hour ≤ 23` then
  /// would collapse the end to 23:00 on the same day, silently producing a
  /// zero-length event the export layer expands to a 5-minute one. Roll
  /// over to next-day midnight via `byAdding: .minute` instead.
  func dateAtMinute(of day: Date, minute: Int) -> Date {
    let clamped = max(0, min(24 * 60, minute))
    let dayStart = calendar.startOfDay(for: day)
    return calendar.date(byAdding: .minute, value: clamped, to: dayStart) ?? day
  }
}
