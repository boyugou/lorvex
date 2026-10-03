extension LorvexSampleText {
  /// The sample datasets in Polish. People are Michał (Sam), Marcin (Alex),
  /// and Kasia (Maya) in every dataset, in the case each sentence needs;
  /// product names (Zoom, Swift, GRPO, Apple) and Q3 stay as written. The car
  /// chore is the przegląd techniczny, the periodic vehicle inspection. The
  /// briefings and reviews avoid first-person past-tense verbs, which Polish
  /// inflects for the speaker's gender.
  static let polish: [String: String] = [
    // Tags.
    "work": "praca",
    "planning": "planowanie",
    "weekly": "cotygodniowe",
    "home": "dom",
    "urgent": "pilne",
    "engineering": "dev",
    "research": "badania",
    "someday": "kiedyś",

    // Lists.
    "Apple Native": "Ekosystem Apple",
    "Apple ecosystem apps and gear to try": "Aplikacje i sprzęt z ekosystemu Apple do wypróbowania",
    "Work": "Praca",
    "Day job & deep work": "Etat i praca głęboka",
    "Personal": "Prywatne",
    "Reading": "Lektury",
    "Papers & books": "Artykuły i książki",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "Ułożyć program wyjazdu zespołu",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "Rozpisz sesje, wybierz wystąpienie główne i zostaw czas na pracę w grupach.",
    "Confirm session topics with the leads": "Potwierdzić tematy sesji z liderami",
    "Share the draft agenda for feedback": "Udostępnić wstępny program i zebrać uwagi",
    "Book the offsite venue": "Zarezerwować lokalizację wyjazdu",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "Porównaj dwie wybrane lokalizacje i zarezerwuj tę, która pasuje do grupy.",
    "Send the weekly status update": "Wysłać cotygodniowy raport z postępów",
    "Summarize progress, blockers, and next steps for the team.":
      "Podsumuj dla zespołu postępy, przeszkody i kolejne kroki.",
    "Look into a standing-desk setup": "Rozejrzeć się za biurkiem do pracy na stojąco",
    "Keep this as a someday idea until the home office is sorted.":
      "Zostaw jako pomysł na kiedyś, aż domowe biuro będzie gotowe.",
    "Pick the offsite dates": "Ustalić termin wyjazdu",
    "Cross-check the team calendar and lock the week.":
      "Sprawdź kalendarz zespołu i zablokuj tydzień.",
    "Order a second monitor": "Zamówić drugi monitor",
    "Dropped in favour of using the laptop display on the desk.":
      "Odpuszczone: wystarczy ekran laptopa na biurku.",
    "Renew the car registration": "Zrobić przegląd techniczny auta",
    "Reply to Maya about the catering quote": "Odpisać Kasi w sprawie wyceny cateringu",
    "Review the Q3 budget draft": "Przejrzeć projekt budżetu na Q3",
    "Outline the board deck": "Rozpisać strukturę prezentacji dla zarządu",
    "Draft the hiring plan": "Opracować plan rekrutacji",
    "Reply to the investor update email": "Odpowiedzieć na e-mail z aktualizacją dla inwestorów",
    "Review the Q3 planning doc": "Przejrzeć dokument planistyczny na Q3",
    "Refactor the sync layer": "Zrefaktoryzować warstwę synchronizacji",
    "Buy groceries for the week": "Zrobić zakupy na cały tydzień",
    "Read the GRPO paper": "Przeczytać artykuł o GRPO",
    "Renew passport": "Wyrobić nowy paszport",
    "Plan the spring offsite": "Zaplanować wiosenny wyjazd zespołu",
    "Submit the weekly timesheet": "Wysłać tygodniowe rozliczenie godzin",
    "Book the dentist appointment": "Umówić wizytę u dentysty",
    "Review the launch checklist": "Sprawdzić listę kontrolną przed startem",

    // Deferral notes.
    "The agenda comes first": "Najpierw program",
    "Groceries can wait for the evening": "Zakupy mogą poczekać do wieczora",

    // Habits and their cues.
    "Daily Review": "Codzienne podsumowanie",
    "End of day": "Na koniec dnia",
    "Evening walk": "Wieczorny spacer",
    "After dinner": "Po kolacji",
    "Morning run": "Poranny bieg",
    "After waking up": "Po przebudzeniu",
    "Read 30 minutes": "Czytanie przez 30 minut",
    "Read 30 min": "Czytanie 30 min",
    "Before bed": "Przed snem",
    "Meditate": "Medytacja",
    "Mid-morning": "Przed południem",
    "Review the day": "Przegląd dnia",
    "Evening": "Wieczorem",
    "Evening journal": "Wieczorny dziennik",

    // Calendar events and locations.
    "Swift migration review": "Przegląd migracji na Swift",
    "Conference Room B": "Sala konferencyjna B",
    "Team standup": "Daily zespołu",
    "1:1 with Sam": "1:1 z Michałem",
    "Design review": "Przegląd designu",
    "Studio": "Studio",
    "Sprint planning": "Planowanie sprintu",
    "Lunch with Sam": "Obiad z Michałem",
    "1:1 with Alex": "1:1 z Marcinem",
    "Customer call": "Rozmowa z klientem",
    "Dentist": "Dentysta",
    "Roadmap sync": "Omówienie roadmapy",
    "Morning gym": "Siłownia rano",
    "Demo day": "Dzień demo",
    "Team offsite": "Wyjazd zespołu",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "Najpierw program wyjazdu: dopóki go nie ma, nie da się zarezerwować lokalizacji, więc rezerwacja przesunięta na jutro. Dziś po południu dwa spotkania.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "Najpierw przegląd planowania, póki wszystko jest świeże w pamięci; refaktoryzacja synchronizacji zajmie długi blok przed lunchem.",
    "The launch checklist first; the status update after the design review.":
      "Najpierw lista kontrolna przed startem; raport z postępów po przeglądzie designu.",

    // Memory.
    "notes_for_ai": "Notatki dla AI",
    "new_laptop": "Nowy laptop",
    "work_rhythm": "Rytm pracy",
    "working_hours": "Godziny pracy",
    "manager": "Przełożony",
    "writing_style": "Styl pisania",
    "current_focus": "Bieżący priorytet",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "Użytkownik rozważa kilka frameworków UI do prywatnego projektu — sugestie techniczne powinny być neutralne wobec frameworków.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "Przed zmianą laptopa wyeksportuj bazę danych i bibliotekę zdjęć, żeby nic nie zginęło przy przenosinach.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "Pracę głęboką wykonuje przed lunchem, a popołudnia zostawia na spotkania i pocztę.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "Najlepiej skupia się w godzinach 9:00–12:00; chroń poranki dla pracy głębokiej.",
    "Reports to Alex; weekly 1:1 on Mondays.":
      "Podlega Marcinowi; cotygodniowe 1:1 w poniedziałki.",
    "Prefers concise, direct updates — no filler.":
      "Woli zwięzłe, bezpośrednie aktualizacje — bez lania wody.",
    "Shipping the Apple-native rewrite this quarter.":
      "W tym kwartale wypuszcza przepisaną, natywną dla Apple wersję.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "Podsumowanie tygodnia i rozplanowanie przygotowań do wyjazdu na przyszły tydzień.",
    "Cleared the inbox and locked in the offsite dates.":
      "Skrzynka opróżniona, daty wyjazdu ustalone.",
    "Still waiting on venue quotes before booking.":
      "Wciąż czekam na wyceny lokalizacji przed rezerwacją.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "Załatwienie spraw w jedno popołudnie uwolniło resztę tygodnia.",
    "Solid morning of deep work; shipped the planning review.":
      "Produktywny poranek głębokiej pracy; przegląd planowania zamknięty.",
    "Unblocked the sync layer; cleared the investor email.":
      "Warstwa synchronizacji odblokowana; e-mail do inwestorów obsłużony.",
    "Waiting on design sign-off for the calendar grid.":
      "Czekam na akceptację designu siatki kalendarza.",
    "Batching reviews before noon keeps the afternoon open.":
      "Przeglądy zebrane przed południem zostawiają wolne popołudnie.",
    "Steady progress across tasks.": "Stały postęp we wszystkich zadaniach.",
    "Closed a few items.": "Zamknięto kilka pozycji.",
  ]
}
