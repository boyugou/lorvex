extension LorvexSampleText {
  /// The sample datasets in Russian. People are Дима (Sam), Алексей (Alex),
  /// and Катя (Maya) in every dataset, in the case each sentence needs;
  /// product names (Zoom, Swift, GRPO, Apple) and Q3 stay as written. The car
  /// chore is the техосмотр, the vehicle inspection. The briefings and reviews
  /// avoid first-person past-tense verbs, which Russian inflects for the
  /// speaker's gender.
  static let russian: [String: String] = [
    // Tags.
    "work": "работа",
    "planning": "планирование",
    "weekly": "еженедельно",
    "home": "дом",
    "urgent": "срочно",
    "engineering": "разработка",
    "research": "исследования",
    "someday": "когда-нибудь",

    // Lists.
    "Apple Native": "Экосистема Apple",
    "Apple ecosystem apps and gear to try": "Приложения и гаджеты Apple, которые хочу попробовать",
    "Work": "Работа",
    "Day job & deep work": "Основная работа и глубокий фокус",
    "Personal": "Личное",
    "Reading": "Чтение",
    "Papers & books": "Статьи и книги",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "Составить программу выезда команды",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "Распределить сессии по времени, выбрать главный доклад и оставить время на работу в группах.",
    "Confirm session topics with the leads": "Согласовать темы сессий с руководителями",
    "Share the draft agenda for feedback": "Разослать черновик программы и собрать отзывы",
    "Book the offsite venue": "Забронировать площадку для выезда",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "Сравнить две отобранные площадки и забронировать ту, что подойдёт группе.",
    "Send the weekly status update": "Отправить еженедельный статус",
    "Summarize progress, blockers, and next steps for the team.":
      "Описать для команды прогресс, блокеры и следующие шаги.",
    "Look into a standing-desk setup": "Присмотреть стол для работы стоя",
    "Keep this as a someday idea until the home office is sorted.":
      "Оставить как идею «когда-нибудь», пока не обустроен домашний кабинет.",
    "Pick the offsite dates": "Выбрать даты выезда",
    "Cross-check the team calendar and lock the week.":
      "Сверить с календарём команды и зафиксировать неделю.",
    "Order a second monitor": "Заказать второй монитор",
    "Dropped in favour of using the laptop display on the desk.":
      "Отменено: хватит экрана ноутбука на столе.",
    "Renew the car registration": "Пройти техосмотр",
    "Reply to Maya about the catering quote": "Ответить Кате насчёт сметы на кейтеринг",
    "Review the Q3 budget draft": "Проверить черновик бюджета на Q3",
    "Outline the board deck": "Набросать структуру презентации для совета директоров",
    "Draft the hiring plan": "Составить план найма",
    "Reply to the investor update email": "Ответить на письмо с обновлением для инвесторов",
    "Review the Q3 planning doc": "Просмотреть документ по планированию на Q3",
    "Refactor the sync layer": "Отрефакторить слой синхронизации",
    "Buy groceries for the week": "Купить продукты на неделю",
    "Read the GRPO paper": "Прочитать статью про GRPO",
    "Renew passport": "Заменить загранпаспорт",
    "Plan the spring offsite": "Спланировать весенний выезд",
    "Submit the weekly timesheet": "Сдать табель за неделю",
    "Book the dentist appointment": "Записаться к стоматологу",
    "Review the launch checklist": "Пройтись по чек-листу запуска",

    // Deferral notes.
    "The agenda comes first": "Сначала программа",
    "Groceries can wait for the evening": "Продукты подождут до вечера",

    // Habits and their cues.
    "Daily Review": "Ежедневные итоги",
    "End of day": "В конце дня",
    "Evening walk": "Вечерняя прогулка",
    "After dinner": "После ужина",
    "Morning run": "Утренняя пробежка",
    "After waking up": "После пробуждения",
    "Read 30 minutes": "Читать 30 минут",
    "Read 30 min": "Читать 30 мин",
    "Before bed": "Перед сном",
    "Meditate": "Медитация",
    "Mid-morning": "Ближе к полудню",
    "Review the day": "Подвести итоги дня",
    "Evening": "Вечером",
    "Evening journal": "Вечерний дневник",

    // Calendar events and locations.
    "Swift migration review": "Ревью миграции на Swift",
    "Conference Room B": "Переговорная B",
    "Team standup": "Стендап команды",
    "1:1 with Sam": "1:1 с Димой",
    "Design review": "Дизайн-ревью",
    "Studio": "Студия",
    "Sprint planning": "Планирование спринта",
    "Lunch with Sam": "Обед с Димой",
    "1:1 with Alex": "1:1 с Алексеем",
    "Customer call": "Созвон с клиентом",
    "Dentist": "Стоматолог",
    "Roadmap sync": "Встреча по роадмапу",
    "Morning gym": "Утренняя тренировка",
    "Demo day": "Демо-день",
    "Team offsite": "Выезд команды",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "Сначала программа выезда: пока её нет, площадку не забронировать, поэтому бронирование перенесено на завтра. Сегодня после обеда две встречи.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "Сначала ревью планирования, пока всё свежо в памяти; рефакторинг синхронизации займёт длинный блок до обеда.",
    "The launch checklist first; the status update after the design review.":
      "Сначала чек-лист запуска; статус — после дизайн-ревью.",

    // Memory.
    "notes_for_ai": "Заметки для ИИ",
    "new_laptop": "Новый ноутбук",
    "work_rhythm": "Ритм работы",
    "working_hours": "Рабочие часы",
    "manager": "Руководитель",
    "writing_style": "Стиль письма",
    "current_focus": "Текущий фокус",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "Пользователь выбирает между несколькими фреймворками для UI в личном проекте — технические советы должны быть нейтральными.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "Перед сменой ноутбука экспортируй базу данных и библиотеку фото, чтобы ничего не потерять при переезде.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "Глубокой работой занимается до обеда, а вторую половину дня оставляет для встреч и почты.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "Лучше всего концентрируется с 9 до 12; утро стоит беречь для глубокой работы.",
    "Reports to Alex; weekly 1:1 on Mondays.":
      "Подчиняется Алексею; еженедельный 1:1 по понедельникам.",
    "Prefers concise, direct updates — no filler.": "Любит краткие и прямые апдейты — без воды.",
    "Shipping the Apple-native rewrite this quarter.":
      "В этом квартале выпускает переписанную нативную версию для Apple.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "Итоги недели подведены, подготовка выезда на следующую неделю запланирована.",
    "Cleared the inbox and locked in the offsite dates.":
      "Входящие разобраны, даты выезда утверждены.",
    "Still waiting on venue quotes before booking.":
      "Жду расценки площадок, прежде чем бронировать.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "Все мелкие дела за один день — и остаток недели свободен.",
    "Solid morning of deep work; shipped the planning review.":
      "Продуктивное утро глубокой работы; ревью планирования готово.",
    "Unblocked the sync layer; cleared the investor email.":
      "Слой синхронизации разблокирован; письмо инвесторам обработано.",
    "Waiting on design sign-off for the calendar grid.":
      "Жду согласования дизайна сетки календаря.",
    "Batching reviews before noon keeps the afternoon open.":
      "Если собрать ревью до полудня, вторая половина дня остаётся свободной.",
    "Steady progress across tasks.": "Стабильный прогресс по всем задачам.",
    "Closed a few items.": "Закрыто несколько пунктов.",
  ]
}
