import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["fr-FR"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// French capture lines, read for a user whose languages include French.
@Suite("Capture parser French")
struct CaptureParserFrenchTests {
  @Test("Days, typed with or without accents")
  func days() {
    let line = parse("Appeler Paul demain")
    #expect(line.plannedDayOffset == 1)
    #expect(line.title == "Appeler Paul")
    #expect(line.phrases.map(\.text) == ["demain"])

    #expect(parse("Dentiste aujourd'hui").plannedDayOffset == 0)
    #expect(parse("Dentiste aujourd’hui").title == "Dentiste")
    #expect(parse("Rendre le livre après-demain").plannedDayOffset == 2)
    #expect(parse("Rendre le livre apres demain").plannedDayOffset == 2)
    #expect(parse("Rendre le livre après-demain").title == "Rendre le livre")
    #expect(parse("Ménage ce week-end").plannedDayOffset == 4)
    #expect(parse("Ménage le weekend prochain").plannedDayOffset == 11)
    #expect(parse("Bilan la semaine prochaine").plannedDayOffset == 7)
    #expect(parse("Bilan la semaine prochaine").title == "Bilan")
    #expect(parse("Rappeler dans 3 jours").plannedDayOffset == 3)
    #expect(parse("Rappeler dans une semaine").plannedDayOffset == 7)
    #expect(parse("Rappeler dans une semaine").title == "Rappeler")
    #expect(parse("La réunion de demain").title == "La réunion")
    #expect(parse("Envoyer le devis dès demain").plannedDayOffset == 1)
  }

  @Test("Weekdays: the next one, this week's, and next week's")
  func weekdays() {
    #expect(parse("Piscine vendredi").plannedDayOffset == 3)
    #expect(parse("Piscine vendredi").title == "Piscine")
    // Today is Tuesday, so Tuesday alone is a week ahead and "ce mardi" today.
    #expect(parse("Marché mardi").plannedDayOffset == 7)
    #expect(parse("Marché ce mardi").plannedDayOffset == 0)
    #expect(parse("Piscine ce vendredi").plannedDayOffset == 3)
    #expect(parse("Piscine vendredi prochain").plannedDayOffset == 10)
    #expect(parse("Point lundi prochain").plannedDayOffset == 6)
    #expect(parse("Point lundi prochain").title == "Point")
    #expect(parse("Courses le jeudi").plannedDayOffset == 2)
    #expect(parse("Courses le jeudi").title == "Courses")
  }

  @Test("Evenings put a bare clock time at night")
  func evenings() {
    let line = parse("Dîner ce soir 8h")
    #expect(line.plannedDayOffset == 0)
    #expect(line.startMinutes == 20 * 60)
    #expect(line.title == "Dîner")
    #expect(parse("Film demain soir 21h").plannedDayOffset == 1)
    #expect(parse("Film demain soir 21h").startMinutes == 21 * 60)
    let afternoon = parse("Réunion cet après-midi")
    #expect(afternoon.plannedDayOffset == 0)
    #expect(afternoon.startMinutes == nil)
    #expect(afternoon.title == "Réunion")
  }

  @Test("Dates written out, with or without their weekday")
  func dates() {
    let line = parse("Fête le 5 octobre")
    #expect(line.plannedDayOffset == 13)
    #expect(line.title == "Fête")
    #expect(parse("Fête lundi 5 octobre").plannedDayOffset == 13)
    #expect(parse("Fête lundi 5 octobre").title == "Fête")
    #expect(parse("Facture 1er novembre").plannedDayOffset == 40)
    #expect(parse("Voyage 5 oct.").plannedDayOffset == 13)
    // A date already passed this year is next year's.
    #expect(parse("Bilan 5 février").plannedDayOffset == 136)
    #expect(parse("Bilan 5 fevrier").plannedDayOffset == 136)
    // A date in digits depends on the region, so it stays in the title.
    #expect(parse("Fête 5/10").plannedDayOffset == nil)
    #expect(
      LorvexCaptureParser.parse("Fête le 5 octobre", lists: [], todayWeekday: 3, languages: ["fr"]).plannedDayOffset
        == nil)
  }

  @Test("Due days")
  func dueDays() {
    let line = parse("Rapport pour vendredi")
    #expect(line.dueDayOffset == 3)
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Rapport")
    #expect(parse("Rapport d'ici demain").dueDayOffset == 1)
    #expect(parse("Payer le loyer jusqu'au 5 octobre").dueDayOffset == 13)
    #expect(parse("Payer le loyer jusqu’au 5 octobre").title == "Payer le loyer")
    #expect(parse("Rapport vendredi au plus tard").dueDayOffset == 3)
    #expect(parse("Rapport vendredi au plus tard").title == "Rapport")
    #expect(parse("Déclaration avant le 5 octobre").dueDayOffset == 13)
  }

  @Test("Clock times written with h are times")
  func times() {
    let line = parse("Appeler Paul à 15h demain")
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == nil)
    #expect(line.plannedDayOffset == 1)
    #expect(line.title == "Appeler Paul")
    #expect(line.phrases.map(\.text) == ["à 15h", "demain"])

    #expect(parse("Dentiste 9h30").startMinutes == 9 * 60 + 30)
    #expect(parse("Dentiste 9h30").title == "Dentiste")
    #expect(parse("Dentiste 15 h 30").startMinutes == 15 * 60 + 30)
    // From 1 to 6 o'clock a bare time is the afternoon, unless it has a zero.
    #expect(parse("Réunion 3h").startMinutes == 15 * 60)
    #expect(parse("Train 06h10").startMinutes == 6 * 60 + 10)
    #expect(parse("Appel vers 18h").startMinutes == 18 * 60)
    #expect(parse("Appel vers 18h").title == "Appel")
    #expect(parse("Disponible à partir de 14h").startMinutes == 14 * 60)
    #expect(parse("Disponible à partir de 14h").title == "Disponible")
    #expect(parse("Appel à 3 heures").startMinutes == 15 * 60)
    #expect(parse("Appel à 3 heures").estimatedMinutes == nil)
    // An hour that no clock shows stays in the title.
    #expect(parse("Livraison 48h").startMinutes == nil)
    #expect(parse("Livraison 48h").title == "Livraison 48h")
  }

  @Test("Parts of the day, noon, and midnight")
  func partsOfTheDay() {
    #expect(parse("Cours 9h du matin").startMinutes == 9 * 60)
    #expect(parse("Café 3h de l'après-midi").startMinutes == 15 * 60)
    #expect(parse("Café 3h de l'après-midi").title == "Café")
    #expect(parse("Dîner 8h du soir").startMinutes == 20 * 60)
    #expect(parse("Déjeuner midi").startMinutes == 12 * 60)
    #expect(parse("Déjeuner à midi").title == "Déjeuner")
    let midnight = parse("Feux d'artifice à minuit")
    #expect(midnight.startMinutes == 0)
    #expect(midnight.plannedDayOffset == 1)
    #expect(midnight.title == "Feux d'artifice")
  }

  @Test("An hour that may be a time or a length, or a deadline, stays in the title")
  func ambiguousHours() {
    let train = parse("Le train de 9h")
    #expect(train.startMinutes == nil)
    #expect(train.estimatedMinutes == nil)
    #expect(train.title == "Le train de 9h")
    #expect(parse("Réunion de 2h").estimatedMinutes == nil)
    #expect(parse("Réunion de 2h").title == "Réunion de 2h")
    let deadline = parse("Rendre le dossier avant 18h")
    #expect(deadline.startMinutes == nil)
    #expect(deadline.title == "Rendre le dossier avant 18h")
    #expect(parse("Finir d'ici 18h").startMinutes == nil)
  }

  @Test("Time ranges plan the start and the length")
  func ranges() {
    let line = parse("Réunion de 14h à 16h")
    #expect(line.startMinutes == 14 * 60)
    #expect(line.estimatedMinutes == 120)
    #expect(line.title == "Réunion")
    #expect(parse("Atelier 14h-16h30").estimatedMinutes == 150)
    #expect(parse("Cours de 2 à 4h").startMinutes == 14 * 60)
    #expect(parse("Cours de 2 à 4h").estimatedMinutes == 120)
    #expect(parse("Permanence entre 14h et 16h").estimatedMinutes == 120)
    #expect(parse("Permanence entre 14h et 16h").title == "Permanence")
    #expect(parse("Permanence de 9h à midi").startMinutes == 9 * 60)
    #expect(parse("Permanence de 9h à midi").estimatedMinutes == 180)
    // "Et" names two times unless entre opens the range; the first counts.
    let twoTimes = parse("Appeler à 14h et 16h")
    #expect(twoTimes.startMinutes == 14 * 60)
    #expect(twoTimes.estimatedMinutes == nil)
  }

  @Test("Lengths")
  func lengths() {
    let line = parse("Lire pendant 2h")
    #expect(line.estimatedMinutes == 120)
    #expect(line.startMinutes == nil)
    #expect(line.title == "Lire")
    #expect(parse("Lire durant 1h30").estimatedMinutes == 90)
    #expect(parse("Footing 1h30min").estimatedMinutes == 90)
    #expect(parse("Footing 1h30min").startMinutes == nil)
    #expect(parse("Footing 1,5 h").estimatedMinutes == 90)
    #expect(parse("Pause 30 min").estimatedMinutes == 30)
    #expect(parse("Pause 30 minutes").title == "Pause")
    #expect(parse("Révision 2 heures").estimatedMinutes == 120)
    #expect(parse("Révision 2 heures et demie").estimatedMinutes == 150)
    #expect(parse("Révision 1 heure 30").estimatedMinutes == 90)
    #expect(parse("Sieste une demi-heure").estimatedMinutes == 30)
    #expect(parse("Sieste une heure et demie").estimatedMinutes == 90)
    #expect(parse("Méditer un quart d'heure").estimatedMinutes == 15)
    #expect(parse("Méditer un quart d'heure").title == "Méditer")
  }

  @Test("Repeats")
  func repeats() {
    let line = parse("Arroser les plantes tous les jours")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(line.title == "Arroser les plantes")
    #expect(parse("Sport chaque lundi").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO"]))
    #expect(
      parse("Cours tous les lundis et jeudis").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TH"]))
    #expect(parse("Cours tous les lundis et les jeudis").title == "Cours")
    #expect(
      parse("Réunion un lundi sur deux").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO"]))
    // French counts a fortnight as fifteen days.
    #expect(parse("Bilan tous les 15 jours").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))
    #expect(parse("Bilan tous les quinze jours").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))
    #expect(parse("Médicament tous les 3 jours").recurrence == TaskRecurrenceRule(freq: .daily, interval: 3))
    #expect(parse("Facture tous les trois mois").recurrence == TaskRecurrenceRule(freq: .monthly, interval: 3))
    // A weekday in the plural recurs.
    #expect(parse("Sport les lundis").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO"]))
    #expect(parse("Sport les lundis").title == "Sport")
    #expect(
      parse("Cours les mardis et les jeudis").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU", "TH"]))
    #expect(parse("Loyer le 5 de chaque mois").recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [5]))
    #expect(parse("Loyer le 5 de chaque mois").title == "Loyer")
    #expect(parse("Poubelles une semaine sur deux").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))
    #expect(parse("Anniversaire chaque année").recurrence == TaskRecurrenceRule(freq: .yearly))
    let workdays = TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"])
    #expect(parse("Point d'équipe en semaine").recurrence == workdays)
    #expect(parse("Point d'équipe tous les jours ouvrés").recurrence == workdays)
    #expect(parse("Point d'équipe tous les jours ouvrés").title == "Point d'équipe")
  }

  @Test("A cadence adverb repeats at the end of the line; an adjective stays in the title")
  func cadenceWords() {
    let line = parse("Faire le point hebdomadairement")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .weekly))
    #expect(line.title == "Faire le point")
    let report = parse("Rapport hebdomadaire")
    #expect(report.recurrence == nil)
    #expect(report.title == "Rapport hebdomadaire")
  }

  @Test("Priorities")
  func priorities() {
    let line = parse("Appeler la banque priorité haute")
    #expect(line.priority == .p1)
    #expect(line.title == "Appeler la banque")
    #expect(parse("Ranger le garage basse priorité").priority == .p3)
    #expect(parse("Trier les mails priorité moyenne").priority == .p2)
    #expect(parse("Facture urgente").priority == .p1)
    #expect(parse("Facture urgente").title == "Facture")
    #expect(parse("Urgent : appeler le plombier").priority == .p1)
    #expect(parse("Urgent : appeler le plombier").title == "appeler le plombier")
  }

  @Test("Beside French, English leaves an hour written with h to French")
  func hoursBesideEnglish() {
    // English alone reads "2h" as two hours.
    let english = parse("Write the report 2h", languages: ["en"])
    #expect(english.estimatedMinutes == 120)
    #expect(english.startMinutes == nil)
    // With French it is 2 o'clock, read as the afternoon.
    let both = parse("Write the report 2h", languages: ["en", "fr"])
    #expect(both.startMinutes == 14 * 60)
    #expect(both.estimatedMinutes == nil)
    // Other English lengths still read.
    #expect(parse("Review 20 min", languages: ["en", "fr"]).estimatedMinutes == 20)
    #expect(parse("Review 1.5h", languages: ["en", "fr"]).estimatedMinutes == 90)
  }

  @Test("French words are read only for a user who reads French")
  func languageGate() {
    let line = parse("Appeler Paul demain", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Appeler Paul demain")
    #expect(parse("Appeler Paul demain", languages: ["fr-CA"]).plannedDayOffset == 1)
  }
}
