import Foundation
import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(
    text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// A line per language that spells a task's length with digits, as that
/// language's own suite does ("1.5 hours", "1h30", "30 minutes").
private let lengthLines: [(languages: [String], line: String)] = [
  (["en"], "Write the review for 1.5h"), (["en"], "Write the report 2 hours 30 min"),
  (["en"], "Read 90 min"), (["ar"], "قراءة 1.5 ساعة"), (["ar"], "قراءة 20 دقيقة"),
  (["bn"], "রিপোর্ট লেখা 1 ঘণ্টা 30 মিনিট"), (["bn"], "রিপোর্ট লেখা 1.5 ঘণ্টা"),
  (["nl"], "Rapport 1 uur 30 min"), (["nl"], "Rapport 1,5u"), (["nl"], "Rapport 9 uur"),
  (["fr"], "Lire durant 1h30"), (["fr"], "Footing 1h30min"), (["fr"], "Lire pendant 2h"),
  (["de"], "Lesen 1 Stunde 30 Minuten"), (["de"], "Lesen 1h30"), (["de"], "Lesen 2h"),
  (["el"], "Αναφορά 1,5 ώρα"), (["he"], "דוח 1h30m"), (["he"], "ריצה של 30 דקות"),
  (["hi"], "रिपोर्ट लिखें 1 घंटा 30 मिनट"), (["hi"], "रिपोर्ट लिखें 1.5 घंटे"),
  (["id"], "Rapat 1,5 jam"), (["it"], "Correre 1h30min"), (["it"], "Leggere per 2 ore"),
  (["ja"], "1時間30分 会議"), (["ja"], "2時間 勉強"), (["ja"], "資料作成30分"),
  (["ko"], "1시간 30분 회의"), (["ko"], "공부 2시간"), (["ms"], "Mesyuarat 1,5 jam"),
  (["mr", "hi"], "रिपोर्ट लिहा 1 तास 30 मिनिटे"), (["pl"], "Czytać 1,5 godziny"),
  (["pl"], "Czytać 30 minut"), (["pt"], "Ler durante 1h30"), (["pt"], "Corrida 1h30min"),
  (["ro"], "Ședință 2 ore 30 min"), (["ro"], "Ședință 2 ore și 30 de minute"),
  (["ru"], "Читать 1,5 часа"), (["ru"], "Читать 30 минут"), (["es"], "Correr 1h30min"),
  (["es"], "Leer durante 2 horas"), (["ta"], "அறிக்கை எழுது 1.5 மணி நேரம்"),
  (["ta"], "5 மணி நேரம் 30 நிமிடங்கள் கூட்டம்"), (["te"], "రిపోర్ట్ రాయండి 1.5 గంటలు"),
  (["te"], "5 గంటల 30 నిమిషాలు మీటింగ్"), (["th"], "อ่านหนังสือ 1.5 ชั่วโมง"),
  (["tr"], "Rapor 1,5 saat"), (["tr"], "Rapor 30 dakika"), (["uk"], "Читати 1 година 30 хвилин"),
  (["uk"], "Читати 1,5 години"), (["ur"], "رپورٹ لکھنا 1 گھنٹہ 30 منٹ"),
  (["ur"], "رپورٹ لکھنا 1.5 گھنٹے"), (["vi"], "Họp 1,5 giờ"), (["vi"], "Họp 2 tiếng rưỡi"),
]

/// The numbers a quick-add line reads feed hour and minute arithmetic, so a
/// number of any size must read as no length instead of overflowing.
@Suite("Capture parser huge numbers")
struct CaptureParserHugeNumberTests {
  @Test("A number of any size in a length reads as no length or as a valid one, and never traps")
  func hugeNumbersInLengths() {
    let digitRun = /[0-9]+(?:[.,][0-9]+)?/
    let replacements = [
      String(repeating: "9", count: 40), "9223372036854775807", "9223372036854775808",
      String(repeating: "9", count: 25) + ".5", "1000001", "0",
    ]
    for (languages, line) in lengthLines {
      let runs = line.ranges(of: digitRun)
      #expect(!runs.isEmpty, "\(line): the line has a number")
      #expect(parse(line, languages: languages).estimatedMinutes != nil, "\(line): the line names a length")
      for replacement in replacements {
        let targets: [[Range<String.Index>]] = [[runs[0]], [runs[runs.count - 1]], runs]
        for target in targets {
          var mutated = line
          for run in target.reversed() { mutated.replaceSubrange(run, with: replacement) }
          if let minutes = parse(mutated, languages: languages).estimatedMinutes {
            #expect((1...1440).contains(minutes), "\(mutated): \(minutes) minutes is no task length")
          }
        }
      }
    }
  }

  @Test("A number beyond the ceiling is no hour, day, or length, wherever the line reads it")
  func numbersBeyondTheCeilingReadAsNothing() {
    let huge = String(repeating: "9", count: 40)
    for line in [
      "Call mom in \(huge) days", "Call mom at \(huge):30", "Call mom on \(huge) May",
      "Call mom every \(huge) days", "Call mom for \(huge) minutes", "Call mom in 1000001 days",
    ] {
      let read = parse(line, languages: ["en"])
      #expect(read.plannedDayOffset == nil, "\(line)")
      #expect(read.startMinutes == nil, "\(line)")
      #expect(read.estimatedMinutes == nil, "\(line)")
    }
  }
}
