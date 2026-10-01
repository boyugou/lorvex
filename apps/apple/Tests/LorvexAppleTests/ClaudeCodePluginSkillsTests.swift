import Foundation
import Testing

/// The Claude Code plugin's skills (`plugins/lorvex/skills`) are playbooks that
/// name Lorvex tools, parameters, and enum values. They ship from the repository
/// while the tools ship inside the app, so these tests hold the two together.
@Suite("Claude Code plugin skills")
struct ClaudeCodePluginSkillsTests {
  private static let skillsRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // LorvexAppleTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // apps/apple
    .deletingLastPathComponent()  // apps
    .deletingLastPathComponent()  // repository root
    .appendingPathComponent("plugins/lorvex/skills")

  private static func skills() throws -> [(name: String, text: String)] {
    let names = try FileManager.default.contentsOfDirectory(atPath: skillsRoot.path)
      .filter { !$0.hasPrefix(".") }
      .sorted()
    return try names.map { name in
      let file = skillsRoot.appendingPathComponent(name).appendingPathComponent("SKILL.md")
      return (name, try String(contentsOf: file, encoding: .utf8))
    }
  }

  @Test("every identifier a skill mentions exists in the tool surface")
  func mentionedIdentifiersExist() throws {
    let known = MCPToolVocabulary.identifiers()
    let skills = try Self.skills()
    #expect(skills.count >= 4)
    for skill in skills {
      let unknown = MCPToolVocabulary.snakeCaseIdentifiers(in: skill.text).subtracting(known)
      #expect(unknown.isEmpty, "\(skill.name) names unknown identifiers: \(unknown.sorted())")
    }
  }

  @Test("each skill's frontmatter names its directory and describes when to use it")
  func frontmatterIsComplete() throws {
    for skill in try Self.skills() {
      let lines = skill.text.components(separatedBy: "\n")
      let end = try #require(
        lines.dropFirst().firstIndex(of: "---"), "\(skill.name) has no closing frontmatter fence")
      #expect(lines.first == "---", "\(skill.name) does not open with frontmatter")
      let frontmatter = lines[1..<end]
      #expect(frontmatter.contains("name: \(skill.name)"), "\(skill.name) frontmatter name")
      let description = frontmatter.first { $0.hasPrefix("description: ") }
      #expect(
        (description?.count ?? 0) > 60,
        "\(skill.name) needs a description that says when the skill applies")
    }
  }
}
