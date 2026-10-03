extension LorvexSampleText {
  /// The sample datasets in Brazilian Portuguese. People are Rafael (Sam),
  /// Bruno (Alex), and Camila (Maya) in every dataset; product names (Zoom,
  /// Swift, GRPO, Apple) stay as written, and Q3 is written 3T. The car chore
  /// is the licenciamento, the annual vehicle registration renewal.
  static let brazilianPortuguese: [String: String] = [
    // Tags.
    "work": "trabalho",
    "planning": "planejamento",
    "weekly": "semanal",
    "home": "casa",
    "urgent": "urgente",
    "engineering": "dev",
    "research": "pesquisa",
    "someday": "futuro",

    // Lists.
    "Apple Native": "Ecossistema Apple",
    "Apple ecosystem apps and gear to try": "Apps e dispositivos do ecossistema Apple para testar",
    "Work": "Trabalho",
    "Day job & deep work": "Dia a dia e trabalho focado",
    "Personal": "Pessoal",
    "Reading": "Leitura",
    "Papers & books": "Artigos e livros",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "Montar a pauta do encontro da equipe",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "Reserve os blocos das sessões, escolha uma palestra principal e deixe tempo para os grupos menores.",
    "Confirm session topics with the leads": "Confirmar os temas das sessões com os líderes",
    "Share the draft agenda for feedback": "Compartilhar o rascunho da pauta para receber feedback",
    "Book the offsite venue": "Reservar o local do encontro",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "Compare os dois locais pré-selecionados e reserve o que melhor atende ao grupo.",
    "Send the weekly status update": "Enviar o status semanal",
    "Summarize progress, blockers, and next steps for the team.":
      "Resuma o andamento, os bloqueios e os próximos passos para a equipe.",
    "Look into a standing-desk setup": "Pesquisar mesas ajustáveis para trabalhar em pé",
    "Keep this as a someday idea until the home office is sorted.":
      "Deixe como ideia para algum dia, até o home office ficar pronto.",
    "Pick the offsite dates": "Definir as datas do encontro",
    "Cross-check the team calendar and lock the week.":
      "Confira o calendário da equipe e feche a semana.",
    "Order a second monitor": "Comprar um segundo monitor",
    "Dropped in favour of using the laptop display on the desk.":
      "Descartado: vou usar a tela do notebook em cima da mesa.",
    "Renew the car registration": "Renovar o licenciamento do carro",
    "Reply to Maya about the catering quote": "Responder à Camila sobre o orçamento do buffet",
    "Review the Q3 budget draft": "Revisar o rascunho do orçamento do 3T",
    "Outline the board deck": "Esboçar a apresentação para o conselho",
    "Draft the hiring plan": "Redigir o plano de contratações",
    "Reply to the investor update email": "Responder ao e-mail de atualização dos investidores",
    "Review the Q3 planning doc": "Revisar o documento de planejamento do 3T",
    "Refactor the sync layer": "Refatorar a camada de sincronização",
    "Buy groceries for the week": "Fazer as compras da semana",
    "Read the GRPO paper": "Ler o artigo sobre GRPO",
    "Renew passport": "Renovar o passaporte",
    "Plan the spring offsite": "Planejar o encontro de primavera",
    "Submit the weekly timesheet": "Lançar as horas da semana",
    "Book the dentist appointment": "Marcar consulta no dentista",
    "Review the launch checklist": "Revisar o checklist de lançamento",

    // Deferral notes.
    "The agenda comes first": "A pauta vem primeiro",
    "Groceries can wait for the evening": "As compras podem esperar até a noite",

    // Habits and their cues.
    "Daily Review": "Revisão diária",
    "End of day": "No fim do dia",
    "Evening walk": "Caminhada noturna",
    "After dinner": "Depois do jantar",
    "Morning run": "Corrida matinal",
    "After waking up": "Ao acordar",
    "Read 30 minutes": "Ler 30 minutos",
    "Read 30 min": "Ler 30 min",
    "Before bed": "Antes de dormir",
    "Meditate": "Meditar",
    "Mid-morning": "No meio da manhã",
    "Review the day": "Revisar o dia",
    "Evening": "À noite",
    "Evening journal": "Diário da noite",

    // Calendar events and locations.
    "Swift migration review": "Revisão da migração para Swift",
    "Conference Room B": "Sala de reuniões B",
    "Team standup": "Daily da equipe",
    "1:1 with Sam": "1:1 com Rafael",
    "Design review": "Revisão de design",
    "Studio": "Estúdio",
    "Sprint planning": "Planejamento da sprint",
    "Lunch with Sam": "Almoço com Rafael",
    "1:1 with Alex": "1:1 com Bruno",
    "Customer call": "Ligação com cliente",
    "Dentist": "Dentista",
    "Roadmap sync": "Alinhamento do roadmap",
    "Morning gym": "Academia de manhã",
    "Demo day": "Dia de demos",
    "Team offsite": "Encontro da equipe",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "A pauta do encontro vem primeiro: sem ela não dá para reservar o local, então passei a reserva para amanhã. Hoje à tarde há duas reuniões.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "Primeiro a revisão de planejamento, enquanto o documento está fresco; a refatoração da sincronização fica com o bloco longo antes do almoço.",
    "The launch checklist first; the status update after the design review.":
      "Primeiro o checklist de lançamento; o status depois da revisão de design.",

    // Memory.
    "notes_for_ai": "Notas para a IA",
    "new_laptop": "Notebook novo",
    "work_rhythm": "Ritmo de trabalho",
    "working_hours": "Horário de trabalho",
    "manager": "Gestor",
    "writing_style": "Estilo de escrita",
    "current_focus": "Foco atual",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "O usuário está avaliando alguns frameworks de UI para um projeto pessoal; mantenha as sugestões técnicas neutras em relação a frameworks.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "Antes de trocar de notebook, exporte o banco de dados e a biblioteca de fotos para não perder nada na mudança.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "Faz o trabalho focado antes do almoço e reserva as tardes para reuniões e e-mails.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "Tem mais foco das 9h às 12h; proteja as manhãs para o trabalho focado.",
    "Reports to Alex; weekly 1:1 on Mondays.": "Reporta-se ao Bruno; 1:1 semanal às segundas.",
    "Prefers concise, direct updates — no filler.":
      "Prefere atualizações objetivas e diretas, sem enrolação.",
    "Shipping the Apple-native rewrite this quarter.":
      "Neste trimestre, lança a reescrita nativa para Apple.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "Revisei a semana e deixei organizada a preparação do encontro para a próxima.",
    "Cleared the inbox and locked in the offsite dates.":
      "Zerei a caixa de entrada e fechei as datas do encontro.",
    "Still waiting on venue quotes before booking.":
      "Ainda aguardando os orçamentos dos locais para reservar.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "Juntar as pendências em uma tarde liberou o resto da semana.",
    "Solid morning of deep work; shipped the planning review.":
      "Manhã produtiva de trabalho focado; entreguei a revisão de planejamento.",
    "Unblocked the sync layer; cleared the investor email.":
      "Destravei a camada de sincronização; respondi ao e-mail dos investidores.",
    "Waiting on design sign-off for the calendar grid.":
      "Aguardando a aprovação do design para a grade do calendário.",
    "Batching reviews before noon keeps the afternoon open.":
      "Agrupar as revisões antes do meio-dia deixa a tarde livre.",
    "Steady progress across tasks.": "Progresso constante nas tarefas.",
    "Closed a few items.": "Fechei alguns itens.",
  ]
}
