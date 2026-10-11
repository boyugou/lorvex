import Foundation
import Testing

private func source(_ path: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

@Test
func returnInTheIconSearchChoosesTheFirstMatchAndLeavesAnEmptySearchAlone() throws {
  let picker = try source("Sources/LorvexApple/Views/LorvexAppearancePicker.swift")
  #expect(picker.contains(".onSubmit(chooseFirstMatch)"))

  let choose = try #require(picker.range(of: "private func chooseFirstMatch()"))
  let body = picker[choose.upperBound...].prefix(240)
  #expect(body.contains("guard !iconQuery.trimmingCharacters(in: .whitespaces).isEmpty"))
  #expect(body.contains("let first = filteredIcons.first"))
  #expect(body.contains("icon = first"))
}

@Test
func returnInTheTimeZoneSearchChoosesTheOnlyMatch() throws {
  let row = try source("Sources/LorvexApple/Views/SettingsTimeZoneRow.swift")
  let submit = try #require(row.range(of: ".onSubmit {"))
  let body = row[submit.upperBound...].prefix(200)
  #expect(body.contains("LorvexTimeZoneChoice.onlyMatch(in: choices, for: query)"))
  #expect(body.contains("choose(only.identifier)"))
}
