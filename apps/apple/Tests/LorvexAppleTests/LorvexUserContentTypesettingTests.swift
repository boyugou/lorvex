import Foundation
import Testing

@testable import LorvexCore

/// Which language text written by the user or the assistant is typeset in.
/// Japanese line breaking splits Latin text between a letter and a digit
/// ("Review the Q" / "3 planning doc"), so under a Japanese interface such
/// text without CJK characters is typeset as English.
struct LorvexUserContentTypesettingTests {

  @Test("Under a Japanese interface, text without CJK characters is typeset as English")
  func japaneseInterfaceTypesetsLatinTextAsEnglish() {
    let english = Locale.Language(identifier: "en")
    for content in [
      "Review the Q3 planning doc", "Ship v2 of the H1 roadmap", "Revisión del plan Q3",
      "Отчёт за Q3", "مراجعة خطة الربع 3", "",
    ] {
      #expect(
        LorvexUserContentTypesetting.language(for: content, interfaceIsJapanese: true) == english,
        "\(content)")
    }
  }

  @Test("Text with CJK characters keeps the interface's typesetting")
  func cjkTextKeepsTheInterfaceTypesetting() {
    for content in [
      "Q3の計画を見直す", "計画", "カタカナ", "ｶﾀｶﾅ", "회의 준비", "【draft】Q3 review", "整理一下 Q3 计划",
    ] {
      #expect(
        LorvexUserContentTypesetting.language(for: content, interfaceIsJapanese: true) == nil,
        "\(content)")
    }
  }

  @Test("Other interfaces keep their typesetting for every text")
  func otherInterfacesKeepTheirTypesetting() {
    for content in ["Review the Q3 planning doc", "Q3の計画を見直す"] {
      #expect(
        LorvexUserContentTypesetting.language(for: content, interfaceIsJapanese: false) == nil,
        "\(content)")
    }
  }

  @Test("The interface is Japanese only for a Japanese localization")
  func japaneseLocalizationDetection() {
    #expect(LorvexUserContentTypesetting.isJapanese("ja"))
    #expect(LorvexUserContentTypesetting.isJapanese("ja-JP"))
    for identifier in ["en", "zh-Hans", "zh-Hant", "ko", "fr", nil] as [String?] {
      #expect(!LorvexUserContentTypesetting.isJapanese(identifier), "\(identifier ?? "nil")")
    }
  }
}
