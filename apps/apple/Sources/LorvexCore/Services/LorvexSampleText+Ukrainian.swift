extension LorvexSampleText {
  /// The sample datasets in Ukrainian. People are Андрій (Sam), Олексій
  /// (Alex), and Оксана (Maya) in every dataset, in the case each sentence
  /// needs; product names (Zoom, Swift, GRPO, Apple) and Q3 stay as written.
  /// The car chore is the техогляд, the vehicle inspection. The briefings and
  /// reviews avoid first-person past-tense verbs, which Ukrainian inflects for
  /// the speaker's gender.
  static let ukrainian: [String: String] = [
    // Tags.
    "work": "робота",
    "planning": "планування",
    "weekly": "щотижня",
    "home": "дім",
    "urgent": "терміново",
    "engineering": "розробка",
    "research": "дослідження",
    "someday": "колись",

    // Lists.
    "Apple Native": "Екосистема Apple",
    "Apple ecosystem apps and gear to try": "Застосунки й гаджети Apple, які хочу спробувати",
    "Work": "Робота",
    "Day job & deep work": "Основна робота і глибокий фокус",
    "Personal": "Особисте",
    "Reading": "Читання",
    "Papers & books": "Статті та книжки",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "Скласти програму виїзду команди",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "Розподілити сесії за часом, обрати головну доповідь і залишити час на роботу в групах.",
    "Confirm session topics with the leads": "Узгодити теми сесій з керівниками",
    "Share the draft agenda for feedback": "Розіслати чернетку програми й зібрати відгуки",
    "Book the offsite venue": "Забронювати локацію для виїзду",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "Порівняти дві відібрані локації та забронювати ту, що підходить групі.",
    "Send the weekly status update": "Надіслати щотижневий статус",
    "Summarize progress, blockers, and next steps for the team.":
      "Описати для команди прогрес, блокери та наступні кроки.",
    "Look into a standing-desk setup": "Придивитися до стола для роботи стоячи",
    "Keep this as a someday idea until the home office is sorted.":
      "Залишити як ідею «колись», доки не облаштовано домашній кабінет.",
    "Pick the offsite dates": "Обрати дати виїзду",
    "Cross-check the team calendar and lock the week.":
      "Звірити з календарем команди й зафіксувати тиждень.",
    "Order a second monitor": "Замовити другий монітор",
    "Dropped in favour of using the laptop display on the desk.":
      "Скасовано: вистачить екрана ноутбука на столі.",
    "Renew the car registration": "Пройти техогляд",
    "Reply to Maya about the catering quote": "Відповісти Оксані щодо кошторису на кейтеринг",
    "Review the Q3 budget draft": "Перевірити чернетку бюджету на Q3",
    "Outline the board deck": "Накидати структуру презентації для ради директорів",
    "Draft the hiring plan": "Скласти план найму",
    "Reply to the investor update email": "Відповісти на лист з оновленням для інвесторів",
    "Review the Q3 planning doc": "Переглянути документ з планування на Q3",
    "Refactor the sync layer": "Відрефакторити шар синхронізації",
    "Buy groceries for the week": "Купити продукти на тиждень",
    "Read the GRPO paper": "Прочитати статтю про GRPO",
    "Renew passport": "Замінити закордонний паспорт",
    "Plan the spring offsite": "Спланувати весняний виїзд",
    "Submit the weekly timesheet": "Здати табель за тиждень",
    "Book the dentist appointment": "Записатися до стоматолога",
    "Review the launch checklist": "Пройтися по чек-листу запуску",

    // Deferral notes.
    "The agenda comes first": "Спочатку програма",
    "Groceries can wait for the evening": "Продукти зачекають до вечора",

    // Habits and their cues.
    "Daily Review": "Щоденні підсумки",
    "End of day": "Наприкінці дня",
    "Evening walk": "Вечірня прогулянка",
    "After dinner": "Після вечері",
    "Morning run": "Ранкова пробіжка",
    "After waking up": "Після пробудження",
    "Read 30 minutes": "Читати 30 хвилин",
    "Read 30 min": "Читати 30 хв",
    "Before bed": "Перед сном",
    "Meditate": "Медитація",
    "Mid-morning": "Ближче до полудня",
    "Review the day": "Підбити підсумки дня",
    "Evening": "Ввечері",
    "Evening journal": "Вечірній щоденник",

    // Calendar events and locations.
    "Swift migration review": "Рев’ю міграції на Swift",
    "Conference Room B": "Переговорна B",
    "Team standup": "Стендап команди",
    "1:1 with Sam": "1:1 з Андрієм",
    "Design review": "Дизайн-рев’ю",
    "Studio": "Студія",
    "Sprint planning": "Планування спринту",
    "Lunch with Sam": "Обід з Андрієм",
    "1:1 with Alex": "1:1 з Олексієм",
    "Customer call": "Розмова з клієнтом",
    "Dentist": "Стоматолог",
    "Roadmap sync": "Зустріч щодо роадмапу",
    "Morning gym": "Ранкове тренування",
    "Demo day": "День демо",
    "Team offsite": "Виїзд команди",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "Спочатку програма виїзду: доки її немає, локацію не забронювати, тож бронювання перенесено на завтра. Сьогодні по обіді дві зустрічі.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "Спочатку рев’ю планування, поки все свіже в пам’яті; рефакторинг синхронізації займе довгий блок до обіду.",
    "The launch checklist first; the status update after the design review.":
      "Спочатку чек-лист запуску; статус — після дизайн-рев’ю.",

    // Memory.
    "notes_for_ai": "Нотатки для ШІ",
    "new_laptop": "Новий ноутбук",
    "work_rhythm": "Ритм роботи",
    "working_hours": "Робочі години",
    "manager": "Керівник",
    "writing_style": "Стиль письма",
    "current_focus": "Поточний фокус",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "Користувач обирає між кількома фреймворками для UI в особистому проєкті — технічні поради мають бути нейтральними щодо фреймворків.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "Перед заміною ноутбука експортуй базу даних і бібліотеку фото, щоб нічого не втратити під час переїзду.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "Глибоку роботу виконує до обіду, а другу половину дня лишає для зустрічей і пошти.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "Найкраще зосереджується з 9 до 12; ранок варто берегти для глибокої роботи.",
    "Reports to Alex; weekly 1:1 on Mondays.":
      "Підпорядковується Олексію; щотижневе 1:1 у понеділок.",
    "Prefers concise, direct updates — no filler.": "Любить короткі й прямі апдейти — без води.",
    "Shipping the Apple-native rewrite this quarter.":
      "Цього кварталу випускає переписану нативну версію для Apple.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "Підсумки тижня підбито, підготовку виїзду на наступний тиждень заплановано.",
    "Cleared the inbox and locked in the offsite dates.":
      "Вхідні розібрано, дати виїзду затверджено.",
    "Still waiting on venue quotes before booking.": "Чекаю на розцінки локацій, щоб забронювати.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "Усі дрібні справи за один день — і решта тижня вільна.",
    "Solid morning of deep work; shipped the planning review.":
      "Продуктивний ранок глибокої роботи; рев’ю планування готове.",
    "Unblocked the sync layer; cleared the investor email.":
      "Шар синхронізації розблоковано; лист інвесторам опрацьовано.",
    "Waiting on design sign-off for the calendar grid.":
      "Чекаю на погодження дизайну сітки календаря.",
    "Batching reviews before noon keeps the afternoon open.":
      "Якщо зібрати рев’ю до полудня, друга половина дня лишається вільною.",
    "Steady progress across tasks.": "Стабільний прогрес за всіма завданнями.",
    "Closed a few items.": "Закрито кілька пунктів.",
  ]
}
