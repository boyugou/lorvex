extension LorvexSampleText {
  /// The sample datasets in Italian. People are Marco (Sam), Luca (Alex), and
  /// Giulia (Maya) in every dataset; product names (Zoom, Swift, GRPO, Apple)
  /// and Q3 stay as written. The car chore is the bollo auto, the annual
  /// vehicle tax Italians keep on a to-do list.
  static let italian: [String: String] = [
    // Tags.
    "work": "lavoro",
    "planning": "pianificazione",
    "weekly": "settimanale",
    "home": "casa",
    "urgent": "urgente",
    "engineering": "sviluppo",
    "research": "ricerca",
    "someday": "futuro",

    // Lists.
    "Apple Native": "Ecosistema Apple",
    "Apple ecosystem apps and gear to try": "App e dispositivi dell’ecosistema Apple da provare",
    "Work": "Lavoro",
    "Day job & deep work": "Routine e lavoro profondo",
    "Personal": "Personale",
    "Reading": "Letture",
    "Papers & books": "Articoli e libri",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "Preparare il programma del ritiro del team",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "Fissa le sessioni, scegli un intervento principale e lascia spazio ai lavori di gruppo.",
    "Confirm session topics with the leads":
      "Confermare gli argomenti delle sessioni con i responsabili",
    "Share the draft agenda for feedback":
      "Condividere la bozza del programma e raccogliere feedback",
    "Book the offsite venue": "Prenotare la location del ritiro",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "Confronta le due location in lista e prenota quella più adatta al gruppo.",
    "Send the weekly status update": "Inviare l’aggiornamento settimanale sullo stato",
    "Summarize progress, blockers, and next steps for the team.":
      "Riassumi avanzamento, ostacoli e prossimi passi per il team.",
    "Look into a standing-desk setup": "Valutare una scrivania regolabile in altezza",
    "Keep this as a someday idea until the home office is sorted.":
      "Tienila come idea per prima o poi, finché la postazione di lavoro a casa non è pronta.",
    "Pick the offsite dates": "Scegliere le date del ritiro",
    "Cross-check the team calendar and lock the week.":
      "Controlla il calendario del team e blocca la settimana.",
    "Order a second monitor": "Ordinare un secondo monitor",
    "Dropped in favour of using the laptop display on the desk.":
      "Scartato: userò lo schermo del portatile sulla scrivania.",
    "Renew the car registration": "Pagare il bollo auto",
    "Reply to Maya about the catering quote": "Rispondere a Giulia sul preventivo del catering",
    "Review the Q3 budget draft": "Rivedere la bozza del budget del Q3",
    "Outline the board deck": "Abbozzare la presentazione per il CdA",
    "Draft the hiring plan": "Stilare il piano di assunzioni",
    "Reply to the investor update email":
      "Rispondere all’email di aggiornamento per gli investitori",
    "Review the Q3 planning doc": "Rivedere il documento di pianificazione del Q3",
    "Refactor the sync layer": "Fare refactoring del livello di sincronizzazione",
    "Buy groceries for the week": "Fare la spesa per la settimana",
    "Read the GRPO paper": "Leggere l’articolo su GRPO",
    "Renew passport": "Rinnovare il passaporto",
    "Plan the spring offsite": "Organizzare il ritiro di primavera",
    "Submit the weekly timesheet": "Inviare il timesheet settimanale",
    "Book the dentist appointment": "Prenotare la visita dal dentista",
    "Review the launch checklist": "Controllare la checklist di lancio",

    // Deferral notes.
    "The agenda comes first": "Prima il programma",
    "Groceries can wait for the evening": "La spesa può aspettare fino a stasera",

    // Habits and their cues.
    "Daily Review": "Revisione giornaliera",
    "End of day": "A fine giornata",
    "Evening walk": "Passeggiata serale",
    "After dinner": "Dopo cena",
    "Morning run": "Corsa del mattino",
    "After waking up": "Al risveglio",
    "Read 30 minutes": "Leggere 30 minuti",
    "Read 30 min": "Leggere 30 min",
    "Before bed": "Prima di dormire",
    "Meditate": "Meditare",
    "Mid-morning": "A metà mattina",
    "Review the day": "Rivedere la giornata",
    "Evening": "La sera",
    "Evening journal": "Diario serale",

    // Calendar events and locations.
    "Swift migration review": "Revisione della migrazione a Swift",
    "Conference Room B": "Sala riunioni B",
    "Team standup": "Daily del team",
    "1:1 with Sam": "1:1 con Marco",
    "Design review": "Revisione del design",
    "Studio": "Studio",
    "Sprint planning": "Pianificazione dello sprint",
    "Lunch with Sam": "Pranzo con Marco",
    "1:1 with Alex": "1:1 con Luca",
    "Customer call": "Chiamata con il cliente",
    "Dentist": "Dentista",
    "Roadmap sync": "Allineamento sulla roadmap",
    "Morning gym": "Palestra al mattino",
    "Demo day": "Giornata demo",
    "Team offsite": "Ritiro del team",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "Prima il programma del ritiro: finché non è definito non si può prenotare la location, quindi ho spostato la prenotazione a domani. Oggi pomeriggio due riunioni.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "Prima la revisione della pianificazione, finché il documento è fresco; il refactoring della sincronizzazione occupa il blocco lungo prima di pranzo.",
    "The launch checklist first; the status update after the design review.":
      "Prima la checklist di lancio; l’aggiornamento di stato dopo la revisione del design.",

    // Memory.
    "notes_for_ai": "Note per l’IA",
    "new_laptop": "Nuovo portatile",
    "work_rhythm": "Ritmo di lavoro",
    "working_hours": "Orario di lavoro",
    "manager": "Responsabile",
    "writing_style": "Stile di scrittura",
    "current_focus": "Focus attuale",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "L’utente sta valutando un paio di framework UI per un progetto personale: mantieni i consigli tecnici neutrali rispetto ai framework.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "Prima di cambiare portatile, esporta il database e la libreria foto per non perdere nulla nel passaggio.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "Svolge il lavoro profondo prima di pranzo e lascia i pomeriggi a riunioni ed email.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "Si concentra meglio dalle 9 alle 12; proteggi le mattine per il lavoro profondo.",
    "Reports to Alex; weekly 1:1 on Mondays.": "Fa capo a Luca; 1:1 settimanale il lunedì.",
    "Prefers concise, direct updates — no filler.":
      "Preferisce aggiornamenti concisi e diretti, senza giri di parole.",
    "Shipping the Apple-native rewrite this quarter.":
      "Questo trimestre rilascia la riscrittura nativa per Apple.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "Ho fatto il punto sulla settimana e preparato l’organizzazione del ritiro per la prossima.",
    "Cleared the inbox and locked in the offsite dates.":
      "Casella In arrivo svuotata e date del ritiro fissate.",
    "Still waiting on venue quotes before booking.":
      "Aspetto ancora i preventivi delle location prima di prenotare.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "Raggruppare le commissioni in un pomeriggio ha liberato il resto della settimana.",
    "Solid morning of deep work; shipped the planning review.":
      "Ottima mattinata di lavoro profondo; revisione della pianificazione completata.",
    "Unblocked the sync layer; cleared the investor email.":
      "Livello di sincronizzazione sbloccato; email degli investitori evasa.",
    "Waiting on design sign-off for the calendar grid.":
      "In attesa dell’approvazione del design per la griglia del calendario.",
    "Batching reviews before noon keeps the afternoon open.":
      "Raggruppare le revisioni prima di mezzogiorno lascia libero il pomeriggio.",
    "Steady progress across tasks.": "Progressi costanti su tutte le attività.",
    "Closed a few items.": "Chiuse alcune attività.",
  ]
}
