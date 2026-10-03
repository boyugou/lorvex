extension LorvexSampleText {
  /// The sample datasets in French. People are Julien (Sam), Nicolas (Alex),
  /// and Camille (Maya) in every dataset; product names (Zoom, Swift, GRPO,
  /// Apple) stay as written. Q3 is written T3, and the car chore is the
  /// contrôle technique, the recurring vehicle obligation French speakers
  /// keep on a to-do list.
  static let french: [String: String] = [
    // Tags.
    "work": "travail",
    "planning": "planification",
    "weekly": "hebdo",
    "home": "maison",
    "urgent": "urgent",
    "engineering": "dev",
    "research": "recherche",
    "someday": "futur",

    // Lists.
    "Apple Native": "Écosystème Apple",
    "Apple ecosystem apps and gear to try": "Apps et appareils de l’écosystème Apple à essayer",
    "Work": "Travail",
    "Day job & deep work": "Quotidien et travail de fond",
    "Personal": "Perso",
    "Reading": "Lecture",
    "Papers & books": "Articles et livres",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "Rédiger le programme du séminaire d’équipe",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "Caler les sessions, choisir une keynote et garder du temps pour les ateliers.",
    "Confirm session topics with the leads":
      "Valider les sujets des sessions avec les responsables",
    "Share the draft agenda for feedback":
      "Partager le brouillon du programme pour avoir des retours",
    "Book the offsite venue": "Réserver le lieu du séminaire",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "Comparer les deux lieux présélectionnés et réserver celui qui convient au groupe.",
    "Send the weekly status update": "Envoyer le point d’avancement de la semaine",
    "Summarize progress, blockers, and next steps for the team.":
      "Résumer pour l’équipe les avancées, les blocages et les prochaines étapes.",
    "Look into a standing-desk setup": "Se renseigner sur un bureau assis-debout",
    "Keep this as a someday idea until the home office is sorted.":
      "À garder comme idée pour plus tard, jusqu’à ce que le bureau à la maison soit aménagé.",
    "Pick the offsite dates": "Choisir les dates du séminaire",
    "Cross-check the team calendar and lock the week.":
      "Recouper avec le calendrier de l’équipe et bloquer la semaine.",
    "Order a second monitor": "Commander un deuxième écran",
    "Dropped in favour of using the laptop display on the desk.":
      "Abandonné au profit de l’écran du portable sur le bureau.",
    "Renew the car registration": "Passer le contrôle technique",
    "Reply to Maya about the catering quote": "Répondre à Camille au sujet du devis traiteur",
    "Review the Q3 budget draft": "Relire le projet de budget du T3",
    "Outline the board deck": "Ébaucher la présentation du conseil",
    "Draft the hiring plan": "Rédiger le plan de recrutement",
    "Reply to the investor update email": "Répondre à l’e-mail d’information des investisseurs",
    "Review the Q3 planning doc": "Relire le document de planification du T3",
    "Refactor the sync layer": "Refactoriser la couche de synchronisation",
    "Buy groceries for the week": "Faire les courses de la semaine",
    "Read the GRPO paper": "Lire l’article sur GRPO",
    "Renew passport": "Renouveler le passeport",
    "Plan the spring offsite": "Organiser le séminaire de printemps",
    "Submit the weekly timesheet": "Envoyer le relevé d’heures de la semaine",
    "Book the dentist appointment": "Prendre rendez-vous chez le dentiste",
    "Review the launch checklist": "Passer en revue la checklist de lancement",

    // Deferral notes.
    "The agenda comes first": "D’abord le programme",
    "Groceries can wait for the evening": "Les courses peuvent attendre jusqu’à ce soir",

    // Habits and their cues.
    "Daily Review": "Bilan quotidien",
    "End of day": "En fin de journée",
    "Evening walk": "Promenade du soir",
    "After dinner": "Après le dîner",
    "Morning run": "Footing du matin",
    "After waking up": "Au réveil",
    "Read 30 minutes": "Lire 30 minutes",
    "Read 30 min": "Lire 30 min",
    "Before bed": "Avant de dormir",
    "Meditate": "Méditer",
    "Mid-morning": "En milieu de matinée",
    "Review the day": "Faire le point sur la journée",
    "Evening": "Le soir",
    "Evening journal": "Journal du soir",

    // Calendar events and locations.
    "Swift migration review": "Revue de la migration vers Swift",
    "Conference Room B": "Salle de réunion B",
    "Team standup": "Point d’équipe",
    "1:1 with Sam": "1:1 avec Julien",
    "Design review": "Revue de design",
    "Studio": "Studio",
    "Sprint planning": "Planification du sprint",
    "Lunch with Sam": "Déjeuner avec Julien",
    "1:1 with Alex": "1:1 avec Nicolas",
    "Customer call": "Appel client",
    "Dentist": "Dentiste",
    "Roadmap sync": "Point roadmap",
    "Morning gym": "Sport du matin",
    "Demo day": "Journée démo",
    "Team offsite": "Séminaire d’équipe",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "Le programme du séminaire d’abord\u{00A0}: impossible de réserver le lieu tant qu’il n’est pas arrêté, j’ai donc décalé la réservation à demain. Deux réunions cet après-midi.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "D’abord la revue de planification, tant que le document est frais\u{00A0}; le refactoring de la synchro prend le long créneau d’avant le déjeuner.",
    "The launch checklist first; the status update after the design review.":
      "D’abord la checklist de lancement\u{00A0}; le point d’avancement après la revue de design.",

    // Memory.
    "notes_for_ai": "Notes pour l’IA",
    "new_laptop": "Nouvel ordinateur portable",
    "work_rhythm": "Rythme de travail",
    "working_hours": "Heures de travail",
    "manager": "Responsable",
    "writing_style": "Style d’écriture",
    "current_focus": "Priorité du moment",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "L’utilisateur compare quelques frameworks d’UI pour un projet perso\u{00A0}; garder les suggestions techniques neutres vis-à-vis des frameworks.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "Avant de changer d’ordinateur portable, exporter la base de données et la photothèque pour ne rien perdre pendant le transfert.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "Fait son travail de fond avant le déjeuner et garde les après-midi pour les réunions et les e-mails.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "Se concentre mieux de 9\u{00A0}h à 12\u{00A0}h\u{00A0}; protéger les matinées pour le travail de fond.",
    "Reports to Alex; weekly 1:1 on Mondays.":
      "Manager\u{00A0}: Nicolas\u{00A0}; 1:1 hebdomadaire le lundi.",
    "Prefers concise, direct updates — no filler.":
      "Préfère les points d’étape concis et directs, sans fioritures.",
    "Shipping the Apple-native rewrite this quarter.":
      "Livre ce trimestre la réécriture native pour Apple.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "J’ai fait le point sur la semaine et préparé l’organisation du séminaire de la semaine prochaine.",
    "Cleared the inbox and locked in the offsite dates.":
      "Boîte de réception vidée, dates du séminaire arrêtées.",
    "Still waiting on venue quotes before booking.":
      "J’attends encore les devis des lieux avant de réserver.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "Regrouper les démarches sur un après-midi a libéré le reste de la semaine.",
    "Solid morning of deep work; shipped the planning review.":
      "Belle matinée de travail de fond\u{00A0}; revue de planification bouclée.",
    "Unblocked the sync layer; cleared the investor email.":
      "Couche de synchro débloquée\u{00A0}; e-mail des investisseurs traité.",
    "Waiting on design sign-off for the calendar grid.":
      "En attente de la validation du design pour la grille du calendrier.",
    "Batching reviews before noon keeps the afternoon open.":
      "Regrouper les relectures avant midi laisse l’après-midi libre.",
    "Steady progress across tasks.": "Avancée régulière sur toutes les tâches.",
    "Closed a few items.": "Quelques tâches bouclées.",
  ]
}
