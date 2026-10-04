extension LorvexSampleText {
  /// The sample datasets in Romanian. People are Andrei (Sam), Mihai (Alex),
  /// and Ioana (Maya) in every dataset, in the case each sentence needs;
  /// product names (Zoom, Swift, GRPO, Apple) and Q3 stay as written. The car
  /// chore is the ITP, the periodic vehicle inspection. Task titles are
  /// informal singular imperatives, the way a person writes them to
  /// themselves, and habit names are verbal nouns.
  static let romanian: [String: String] = [
    // Tags.
    "work": "serviciu",
    "planning": "planificare",
    "weekly": "săptămânal",
    "home": "acasă",
    "urgent": "urgent",
    "engineering": "dezvoltare",
    "research": "cercetare",
    "someday": "cândva",

    // Lists.
    "Apple Native": "Ecosistemul Apple",
    "Apple ecosystem apps and gear to try":
      "Aplicații și dispozitive din ecosistemul Apple de încercat",
    "Work": "Serviciu",
    "Day job & deep work": "Munca zilnică și munca aprofundată",
    "Personal": "Personal",
    "Reading": "Lectură",
    "Papers & books": "Articole și cărți",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "Redactează agenda seminarului echipei",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "Programează sesiunile, alege prezentarea principală și lasă timp pentru ateliere.",
    "Confirm session topics with the leads": "Confirmă subiectele sesiunilor cu liderii de echipă",
    "Share the draft agenda for feedback": "Trimite proiectul de agendă pentru feedback",
    "Book the offsite venue": "Rezervă locația pentru seminarul echipei",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "Compară cele două locații preselectate și rezervă-o pe cea potrivită pentru grup.",
    "Send the weekly status update": "Trimite actualizarea săptămânală de stare",
    "Summarize progress, blockers, and next steps for the team.":
      "Rezumă progresul, blocajele și pașii următori pentru echipă.",
    "Look into a standing-desk setup": "Caută informații despre un birou reglabil pe înălțime",
    "Keep this as a someday idea until the home office is sorted.":
      "Păstrează ca idee pentru cândva, până când biroul de acasă este amenajat.",
    "Pick the offsite dates": "Alege datele pentru seminarul echipei",
    "Cross-check the team calendar and lock the week.":
      "Verifică calendarul echipei și blochează săptămâna.",
    "Order a second monitor": "Comandă un al doilea monitor",
    "Dropped in favour of using the laptop display on the desk.":
      "Abandonat în favoarea ecranului laptopului de pe birou.",
    "Renew the car registration": "Fă ITP-ul mașinii",
    "Reply to Maya about the catering quote": "Răspunde-i Ioanei în legătură cu oferta de catering",
    "Review the Q3 budget draft": "Verifică proiectul de buget pentru Q3",
    "Outline the board deck": "Schițează prezentarea pentru consiliul de administrație",
    "Draft the hiring plan": "Redactează planul de recrutare",
    "Reply to the investor update email": "Răspunde la e-mailul cu actualizarea pentru investitori",
    "Review the Q3 planning doc": "Parcurge planul pentru Q3",
    "Refactor the sync layer": "Refactorizează sincronizarea",
    "Buy groceries for the week": "Fă cumpărăturile pentru săptămână",
    "Read the GRPO paper": "Citește articolul despre GRPO",
    "Renew passport": "Reînnoiește pașaportul",
    "Plan the spring offsite": "Planifică seminarul echipei din primăvară",
    "Submit the weekly timesheet": "Trimite pontajul săptămânal",
    "Book the dentist appointment": "Fă o programare la stomatolog",
    "Review the launch checklist": "Parcurge lista de control pentru lansare",

    // Deferral notes.
    "The agenda comes first": "Mai întâi agenda",
    "Groceries can wait for the evening": "Cumpărăturile pot aștepta până seara",

    // Habits and their cues.
    "Daily Review": "Recapitulare zilnică",
    "End of day": "La sfârșitul zilei",
    "Evening walk": "Plimbare de seară",
    "After dinner": "După cină",
    "Morning run": "Alergare de dimineață",
    "After waking up": "După trezire",
    "Read 30 minutes": "Citit 30 de minute",
    "Read 30 min": "Citit 30 min.",
    "Before bed": "Înainte de culcare",
    "Meditate": "Meditație",
    "Mid-morning": "La mijlocul dimineții",
    "Review the day": "Recapitularea zilei",
    "Evening": "Seara",
    "Evening journal": "Jurnal de seară",

    // Calendar events and locations.
    "Swift migration review": "Revizuirea migrării la Swift",
    "Conference Room B": "Sala de conferințe B",
    "Team standup": "Ședința zilnică a echipei",
    "1:1 with Sam": "1:1 cu Andrei",
    "Design review": "Revizuire de design",
    "Studio": "Studio",
    "Sprint planning": "Planificarea sprintului",
    "Lunch with Sam": "Prânz cu Andrei",
    "1:1 with Alex": "1:1 cu Mihai",
    "Customer call": "Apel cu clientul",
    "Dentist": "Stomatolog",
    "Roadmap sync": "Aliniere pe roadmap",
    "Morning gym": "Sală de sport dimineața",
    "Demo day": "Ziua demo",
    "Team offsite": "Seminarul echipei",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "Mai întâi agenda seminarului echipei: locația nu poate fi rezervată până nu este stabilită agenda, așa că am mutat rezervarea pe mâine. Azi după-amiază sunt două ședințe.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "Mai întâi parcurgerea planului pentru Q3, cât timp este încă proaspăt; refactorizarea sincronizării primește intervalul lung dinainte de prânz.",
    "The launch checklist first; the status update after the design review.":
      "Mai întâi lista de control pentru lansare; actualizarea de stare după revizuirea designului.",

    // Memory.
    "notes_for_ai": "Note pentru AI",
    "new_laptop": "Laptop nou",
    "work_rhythm": "Ritm de lucru",
    "working_hours": "Program de lucru",
    "manager": "Șef direct",
    "writing_style": "Stil de scriere",
    "current_focus": "Prioritatea actuală",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "Utilizatorul compară câteva framework-uri UI pentru un proiect personal secundar – păstrează sugestiile tehnice neutre față de framework.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "Înainte de a schimba laptopul, exportă baza de date și biblioteca foto, ca să nu se piardă nimic la mutare.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "Lucrează concentrat înainte de prânz și păstrează după-amiezile pentru ședințe și e-mailuri.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "Se concentrează cel mai bine între orele 9 și 12; protejează diminețile pentru munca aprofundată.",
    "Reports to Alex; weekly 1:1 on Mondays.": "Raportează lui Mihai; 1:1 săptămânal, lunea.",
    "Prefers concise, direct updates — no filler.":
      "Preferă actualizări concise și directe – fără umplutură.",
    "Shipping the Apple-native rewrite this quarter.":
      "Livrează în acest trimestru rescrierea nativă pentru Apple.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "Am recapitulat săptămâna și am pregătit planificarea seminarului din săptămâna următoare.",
    "Cleared the inbox and locked in the offsite dates.":
      "Am golit lista Primite și am stabilit datele seminarului.",
    "Still waiting on venue quotes before booking.":
      "Aștept încă ofertele locațiilor înainte de a rezerva.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "Gruparea treburilor într-o singură după-amiază a eliberat restul săptămânii.",
    "Solid morning of deep work; shipped the planning review.":
      "O dimineață solidă de muncă aprofundată; verificarea documentului de planificare este încheiată.",
    "Unblocked the sync layer; cleared the investor email.":
      "Am deblocat stratul de sincronizare și am rezolvat e-mailul către investitori.",
    "Waiting on design sign-off for the calendar grid.":
      "Aștept aprobarea designului pentru grila calendarului.",
    "Batching reviews before noon keeps the afternoon open.":
      "Gruparea verificărilor înainte de prânz lasă după-amiaza liberă.",
    "Steady progress across tasks.": "Progres constant la toate sarcinile.",
    "Closed a few items.": "Am încheiat câteva sarcini.",
  ]
}
