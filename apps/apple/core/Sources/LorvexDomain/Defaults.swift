/// Canonical default values shared across the Swift core.
///
/// Values are wire-stable
/// `HH:MM` strings that the focus-schedule planner routes through
/// ``TimeOfDay/parse(_:)`` so the typed value stays the only construction
/// surface.
public enum Defaults {
  public static let workingHoursStart = "09:00"
  public static let workingHoursEnd = "18:00"
}
