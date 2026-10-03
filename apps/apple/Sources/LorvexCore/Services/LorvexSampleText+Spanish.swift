extension LorvexSampleText {
  /// The sample datasets in Spanish. People are Javier (Sam), Andrés (Alex),
  /// and Lucía (Maya) in every dataset; product names (Zoom, Swift, GRPO,
  /// Apple) stay as written, and Q3 is written T3. The car chore is the ITV,
  /// the periodic vehicle inspection.
  static let spanish: [String: String] = [
    // Tags.
    "work": "trabajo",
    "planning": "planificación",
    "weekly": "semanal",
    "home": "casa",
    "urgent": "urgente",
    "engineering": "desarrollo",
    "research": "investigación",
    "someday": "futuro",

    // Lists.
    "Apple Native": "Ecosistema Apple",
    "Apple ecosystem apps and gear to try": "Apps y dispositivos del ecosistema Apple para probar",
    "Work": "Trabajo",
    "Day job & deep work": "Día a día y trabajo profundo",
    "Personal": "Personal",
    "Reading": "Lectura",
    "Papers & books": "Artículos y libros",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "Redactar la agenda del retiro del equipo",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "Organiza las sesiones, elige una charla principal y deja tiempo para los grupos de trabajo.",
    "Confirm session topics with the leads":
      "Confirmar los temas de las sesiones con los responsables",
    "Share the draft agenda for feedback":
      "Compartir el borrador de la agenda para recibir comentarios",
    "Book the offsite venue": "Reservar el lugar del retiro",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "Compara los dos lugares preseleccionados y reserva el que mejor se ajuste al grupo.",
    "Send the weekly status update": "Enviar el informe semanal de avances",
    "Summarize progress, blockers, and next steps for the team.":
      "Resume avances, bloqueos y próximos pasos para el equipo.",
    "Look into a standing-desk setup": "Investigar escritorios para trabajar de pie",
    "Keep this as a someday idea until the home office is sorted.":
      "Déjalo como idea para algún día hasta que el espacio de trabajo en casa esté listo.",
    "Pick the offsite dates": "Elegir las fechas del retiro",
    "Cross-check the team calendar and lock the week.":
      "Revisa el calendario del equipo y fija la semana.",
    "Order a second monitor": "Pedir un segundo monitor",
    "Dropped in favour of using the laptop display on the desk.":
      "Descartado: usaré la pantalla del portátil en el escritorio.",
    "Renew the car registration": "Pasar la ITV del coche",
    "Reply to Maya about the catering quote": "Responder a Lucía sobre el presupuesto del catering",
    "Review the Q3 budget draft": "Revisar el borrador del presupuesto del T3",
    "Outline the board deck": "Esbozar la presentación para el consejo",
    "Draft the hiring plan": "Redactar el plan de contratación",
    "Reply to the investor update email": "Responder al correo de novedades para inversores",
    "Review the Q3 planning doc": "Revisar el documento de planificación del T3",
    "Refactor the sync layer": "Refactorizar la capa de sincronización",
    "Buy groceries for the week": "Hacer las compras de la semana",
    "Read the GRPO paper": "Leer el artículo sobre GRPO",
    "Renew passport": "Renovar el pasaporte",
    "Plan the spring offsite": "Planificar el retiro de primavera",
    "Submit the weekly timesheet": "Enviar el registro de horas de la semana",
    "Book the dentist appointment": "Pedir cita con el dentista",
    "Review the launch checklist": "Repasar la checklist de lanzamiento",

    // Deferral notes.
    "The agenda comes first": "Primero la agenda",
    "Groceries can wait for the evening": "Las compras pueden esperar a la noche",

    // Habits and their cues.
    "Daily Review": "Revisión diaria",
    "End of day": "Al final del día",
    "Evening walk": "Paseo nocturno",
    "After dinner": "Después de cenar",
    "Morning run": "Correr por la mañana",
    "After waking up": "Al despertar",
    "Read 30 minutes": "Leer 30 minutos",
    "Read 30 min": "Leer 30 min",
    "Before bed": "Antes de dormir",
    "Meditate": "Meditar",
    "Mid-morning": "A media mañana",
    "Review the day": "Repasar el día",
    "Evening": "Por la noche",
    "Evening journal": "Diario nocturno",

    // Calendar events and locations.
    "Swift migration review": "Revisión de la migración a Swift",
    "Conference Room B": "Sala de reuniones B",
    "Team standup": "Daily del equipo",
    "1:1 with Sam": "1:1 con Javier",
    "Design review": "Revisión de diseño",
    "Studio": "Estudio",
    "Sprint planning": "Planificación del sprint",
    "Lunch with Sam": "Comida con Javier",
    "1:1 with Alex": "1:1 con Andrés",
    "Customer call": "Llamada con cliente",
    "Dentist": "Dentista",
    "Roadmap sync": "Reunión de la hoja de ruta",
    "Morning gym": "Gimnasio por la mañana",
    "Demo day": "Día de demos",
    "Team offsite": "Retiro de equipo",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "Primero la agenda del retiro: hasta que esté cerrada no se puede reservar el lugar, así que la reserva pasa a mañana. Esta tarde hay dos reuniones.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "Primero la revisión de planificación, con el documento aún fresco; el refactor de la sincronización ocupa el bloque largo antes de comer.",
    "The launch checklist first; the status update after the design review.":
      "Primero la checklist de lanzamiento; el informe de avances, después de la revisión de diseño.",

    // Memory.
    "notes_for_ai": "Notas para la IA",
    "new_laptop": "Portátil nuevo",
    "work_rhythm": "Ritmo de trabajo",
    "working_hours": "Horario de trabajo",
    "manager": "Responsable",
    "writing_style": "Estilo de escritura",
    "current_focus": "Enfoque actual",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "El usuario está sopesando un par de frameworks de UI para un proyecto personal; mantén las sugerencias técnicas neutrales respecto a los frameworks.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "Antes de cambiar de portátil, exporta la base de datos y la biblioteca de fotos para no perder nada en el traspaso.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "Hace el trabajo profundo antes de comer y deja las tardes para reuniones y correo.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "Se concentra mejor de 9:00 a 12:00; protege las mañanas para el trabajo profundo.",
    "Reports to Alex; weekly 1:1 on Mondays.": "Reporta a Andrés; 1:1 semanal los lunes.",
    "Prefers concise, direct updates — no filler.":
      "Prefiere actualizaciones breves y directas, sin rodeos.",
    "Shipping the Apple-native rewrite this quarter.":
      "Este trimestre lanza la reescritura nativa para Apple.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "Repasé la semana y dejé organizada la preparación del retiro para la próxima.",
    "Cleared the inbox and locked in the offsite dates.":
      "Vacié la bandeja de entrada y cerré las fechas del retiro.",
    "Still waiting on venue quotes before booking.":
      "Aún espero los presupuestos de los lugares antes de reservar.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "Agrupar las gestiones en una tarde liberó el resto de la semana.",
    "Solid morning of deep work; shipped the planning review.":
      "Buena mañana de trabajo profundo; entregué la revisión de planificación.",
    "Unblocked the sync layer; cleared the investor email.":
      "Desbloqueé la capa de sincronización; respondí el correo de los inversores.",
    "Waiting on design sign-off for the calendar grid.":
      "A la espera de la aprobación de diseño para la cuadrícula del calendario.",
    "Batching reviews before noon keeps the afternoon open.":
      "Agrupar las revisiones antes del mediodía deja la tarde libre.",
    "Steady progress across tasks.": "Avance constante en todas las tareas.",
    "Closed a few items.": "Cerré algunos pendientes.",
  ]
}
