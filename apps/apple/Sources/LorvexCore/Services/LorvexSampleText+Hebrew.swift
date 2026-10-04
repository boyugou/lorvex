extension LorvexSampleText {
  /// The sample datasets in Hebrew. People are שי (Sam), אלכס (Alex), and
  /// מאיה (Maya) in every dataset; product names (Zoom, Swift, GRPO, Apple)
  /// and the abbreviations AI and UI stay as written, after a hyphen where a
  /// prefix letter attaches to them, and Q3 is written הרבעון השלישי. The team
  /// offsite is a כנס, and the car chore is the חידוש רישיון הרכב, the vehicle
  /// license renewal. Task titles are verbal nouns, notes about the user are
  /// noun phrases, and the first-person sentences use past-tense forms
  /// Hebrew inflects the same for every speaker, so no sentence depends on
  /// the speaker's gender.
  static let hebrew: [String: String] = [
    // Tags.
    "work": "עבודה",
    "planning": "תכנון",
    "weekly": "שבועי",
    "home": "בית",
    "urgent": "דחוף",
    "engineering": "הנדסה",
    "research": "מחקר",
    "someday": "מתישהו",

    // Lists.
    "Apple Native": "אקוסיסטם Apple",
    "Apple ecosystem apps and gear to try": "אפליקציות ומכשירים של Apple שכדאי לנסות",
    "Work": "עבודה",
    "Day job & deep work": "המשרה ועבודה עמוקה",
    "Personal": "אישי",
    "Reading": "קריאה",
    "Papers & books": "מאמרים וספרים",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "הכנת טיוטה לסדר היום של כנס הצוות",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "חלוקת הזמן בין הסשנים, בחירת הרצאת מפתח והשארת זמן לקבוצות דיון קטנות.",
    "Confirm session topics with the leads": "אישור נושאי הסשנים עם ראשי הצוותים",
    "Share the draft agenda for feedback": "שיתוף טיוטת סדר היום לקבלת משוב",
    "Book the offsite venue": "הזמנת המקום לכנס",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "השוואה בין שני המקומות שנבחרו והזמנת המתאים לקבוצה.",
    "Send the weekly status update": "שליחת עדכון הסטטוס השבועי",
    "Summarize progress, blockers, and next steps for the team.":
      "סיכום ההתקדמות, החסמים והצעדים הבאים עבור הצוות.",
    "Look into a standing-desk setup": "בדיקת האפשרות להתקין שולחן עמידה",
    "Keep this as a someday idea until the home office is sorted.":
      "להשאיר זאת כרעיון ל\"מתישהו\" עד שהמשרד הביתי יהיה מוכן.",
    "Pick the offsite dates": "בחירת תאריכי הכנס",
    "Cross-check the team calendar and lock the week.": "בדיקה מול לוח השנה של הצוות וסגירת השבוע.",
    "Order a second monitor": "הזמנת מסך שני",
    "Dropped in favour of using the laptop display on the desk.":
      "בוטל; מסך המחשב הנייד על השולחן מספיק.",
    "Renew the car registration": "חידוש רישיון הרכב",
    "Reply to Maya about the catering quote": "מענה למאיה לגבי הצעת המחיר של הקייטרינג",
    "Review the Q3 budget draft": "סקירת טיוטת התקציב לרבעון השלישי",
    "Outline the board deck": "הכנת מתווה למצגת הדירקטוריון",
    "Draft the hiring plan": "הכנת טיוטת תוכנית הגיוס",
    "Reply to the investor update email": "מענה לאימייל העדכון למשקיעים",
    "Review the Q3 planning doc": "סקירת מסמך התכנון לרבעון השלישי",
    "Refactor the sync layer": "ריפקטורינג לשכבת הסנכרון",
    "Buy groceries for the week": "קניית מצרכים לשבוע",
    "Read the GRPO paper": "קריאת מאמר GRPO",
    "Renew passport": "חידוש דרכון",
    "Plan the spring offsite": "תכנון כנס האביב",
    "Submit the weekly timesheet": "הגשת דוח השעות השבועי",
    "Book the dentist appointment": "קביעת תור לרופא שיניים",
    "Review the launch checklist": "סקירת רשימת התיוג להשקה",

    // Deferral notes.
    "The agenda comes first": "קודם סדר היום",
    "Groceries can wait for the evening": "הקניות יכולות לחכות עד הערב",

    // Habits and their cues.
    "Daily Review": "סקירה יומית",
    "End of day": "בסוף היום",
    "Evening walk": "הליכת ערב",
    "After dinner": "אחרי ארוחת הערב",
    "Morning run": "ריצת בוקר",
    "After waking up": "אחרי ההתעוררות",
    "Read 30 minutes": "30 דקות קריאה",
    "Read 30 min": "30 דק׳ קריאה",
    "Before bed": "לפני השינה",
    "Meditate": "מדיטציה",
    "Mid-morning": "באמצע הבוקר",
    "Review the day": "סקירת היום",
    "Evening": "ערב",
    "Evening journal": "יומן ערב",

    // Calendar events and locations.
    "Swift migration review": "סקירת המעבר ל-Swift",
    "Conference Room B": "חדר ישיבות B",
    "Team standup": "סטנד-אפ הצוות",
    "1:1 with Sam": "אחד על אחד עם שי",
    "Design review": "סקירת עיצוב",
    "Studio": "סטודיו",
    "Sprint planning": "תכנון ספרינט",
    "Lunch with Sam": "ארוחת צהריים עם שי",
    "1:1 with Alex": "אחד על אחד עם אלכס",
    "Customer call": "שיחה עם לקוח",
    "Dentist": "רופא שיניים",
    "Roadmap sync": "סנכרון מפת הדרכים",
    "Morning gym": "חדר כושר בבוקר",
    "Demo day": "יום הדגמה",
    "Team offsite": "כנס צוות",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "קודם כל סדר היום של הכנס: אי אפשר להזמין את המקום עד שסדר היום נסגר, ולכן דחיתי את ההזמנה למחר. אחר הצהריים יש שתי פגישות.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "קודם סקירת התכנון, כל עוד המסמך טרי בראש; ריפקטורינג שכבת הסנכרון מקבל את הבלוק הארוך לפני הצהריים.",
    "The launch checklist first; the status update after the design review.":
      "קודם רשימת התיוג להשקה; עדכון הסטטוס אחרי סקירת העיצוב.",

    // Memory.
    "notes_for_ai": "הערות עבור AI",
    "new_laptop": "מחשב נייד חדש",
    "work_rhythm": "קצב עבודה",
    "working_hours": "שעות עבודה",
    "manager": "הממונה",
    "writing_style": "סגנון כתיבה",
    "current_focus": "המיקוד הנוכחי",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "המשתמש שוקל כמה פריימוורקים של UI לפרויקט צד אישי — כדאי שההצעות הטכניות יישארו ניטרליות ביחס לפריימוורק.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "לפני החלפת המחשב הנייד יש לייצא את מסד הנתונים ואת ספריית התמונות, כדי שדבר לא יאבד במעבר.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "עבודה עמוקה לפני ארוחת הצהריים; אחר הצהריים מוקדשות לפגישות ולאימייל.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "הריכוז הטוב ביותר בין 9:00 ל-12:00; כדאי לשמור את הבקרים לעבודה עמוקה.",
    "Reports to Alex; weekly 1:1 on Mondays.": "הממונה: אלכס; פגישת אחד על אחד שבועית בימי שני.",
    "Prefers concise, direct updates — no filler.": "עדכונים תמציתיים וישירים, ללא מילות מילוי.",
    "Shipping the Apple-native rewrite this quarter.":
      "השקת הגרסה המקורית ל-Apple שנכתבה מחדש ברבעון הזה.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "סקרתי את השבוע וסידרתי את התכנון לכנס של השבוע הבא.",
    "Cleared the inbox and locked in the offsite dates.":
      "רוקנתי את תיבת הדואר הנכנס וסגרתי את תאריכי הכנס.",
    "Still waiting on venue quotes before booking.":
      "עדיין ממתינים להצעות מחיר מהמקומות לפני ההזמנה.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "ריכוז כל הסידורים באחר צהריים אחד פינה את שאר השבוע.",
    "Solid morning of deep work; shipped the planning review.":
      "בוקר טוב של עבודה עמוקה; סקירת התכנון הושלמה.",
    "Unblocked the sync layer; cleared the investor email.":
      "הסרתי את החסם בשכבת הסנכרון ועניתי לאימייל של המשקיעים.",
    "Waiting on design sign-off for the calendar grid.": "ממתינים לאישור העיצוב של רשת לוח השנה.",
    "Batching reviews before noon keeps the afternoon open.":
      "ריכוז הסקירות לפני הצהריים משאיר את אחר הצהריים פנוי.",
    "Steady progress across tasks.": "התקדמות יציבה בכל המשימות.",
    "Closed a few items.": "סגרתי כמה פריטים.",
  ]
}
