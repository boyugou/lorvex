extension LorvexSampleText {
  /// The sample datasets in Japanese. People are 健太さん (Sam), 大輔さん
  /// (Alex), and 美咲さん (Maya) in every dataset; product names (Zoom, Swift,
  /// GRPO, Apple) stay as written, and Q3 is written 第3四半期. The team
  /// offsite is a 合宿, and the car chore is the 車検, the vehicle inspection.
  static let japanese: [String: String] = [
    // Tags.
    "work": "仕事",
    "planning": "計画",
    "weekly": "毎週",
    "home": "家",
    "urgent": "緊急",
    "engineering": "開発",
    "research": "研究",
    "someday": "いつか",

    // Lists.
    "Apple Native": "Appleエコシステム",
    "Apple ecosystem apps and gear to try": "試してみたいAppleのアプリとデバイス",
    "Work": "仕事",
    "Day job & deep work": "本業とディープワーク",
    "Personal": "プライベート",
    "Reading": "読書",
    "Papers & books": "論文と本",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "チーム合宿のアジェンダ案を作成",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "セッションの枠を決め、基調講演を選び、分科会の時間も確保する。",
    "Confirm session topics with the leads": "各リーダーとセッションのテーマを確認",
    "Share the draft agenda for feedback": "アジェンダ案を共有してフィードバックをもらう",
    "Book the offsite venue": "合宿の会場を予約",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "候補の2会場を比較して、チームに合う方を押さえる。",
    "Send the weekly status update": "週次の進捗報告を送る",
    "Summarize progress, blockers, and next steps for the team.": "進捗、課題、次のステップをチーム向けにまとめる。",
    "Look into a standing-desk setup": "スタンディングデスクを調べる",
    "Keep this as a someday idea until the home office is sorted.":
      "ホームオフィスが整うまでは「いつか」のアイデアとして置いておく。",
    "Pick the offsite dates": "合宿の日程を決める",
    "Cross-check the team calendar and lock the week.": "チームのカレンダーと照らし合わせて、実施する週を確定する。",
    "Order a second monitor": "2台目のモニターを注文",
    "Dropped in favour of using the laptop display on the desk.": "見送り。デスクではノートPCの画面を使うことにした。",
    "Renew the car registration": "車検の手続き",
    "Reply to Maya about the catering quote": "美咲さんにケータリングの見積もりを返信",
    "Review the Q3 budget draft": "第3四半期の予算案をチェック",
    "Outline the board deck": "取締役会資料の構成を作成",
    "Draft the hiring plan": "採用計画のドラフトを作成",
    "Reply to the investor update email": "投資家向けアップデートのメールに返信",
    "Review the Q3 planning doc": "第3四半期の計画書をレビュー",
    "Refactor the sync layer": "同期レイヤーをリファクタリング",
    "Buy groceries for the week": "1週間分の食料品を買い出し",
    "Read the GRPO paper": "GRPOの論文を読む",
    "Renew passport": "パスポートの更新",
    "Plan the spring offsite": "春の合宿を計画",
    "Submit the weekly timesheet": "週次のタイムシートを提出",
    "Book the dentist appointment": "歯医者の予約",
    "Review the launch checklist": "リリースのチェックリストを確認",

    // Deferral notes.
    "The agenda comes first": "まずアジェンダから",
    "Groceries can wait for the evening": "買い出しは夜でも間に合う",

    // Habits and their cues.
    "Daily Review": "毎日の振り返り",
    "End of day": "一日の終わり",
    "Evening walk": "夜の散歩",
    "After dinner": "夕食後",
    "Morning run": "朝ラン",
    "After waking up": "起床後",
    "Read 30 minutes": "読書30分",
    "Read 30 min": "読書30分",
    "Before bed": "寝る前",
    "Meditate": "瞑想",
    "Mid-morning": "午前中",
    "Review the day": "今日を振り返る",
    "Evening": "夜",
    "Evening journal": "夜の日記",

    // Calendar events and locations.
    "Swift migration review": "Swift移行レビュー",
    "Conference Room B": "会議室B",
    "Team standup": "チームの朝会",
    "1:1 with Sam": "健太さんと1on1",
    "Design review": "デザインレビュー",
    "Studio": "スタジオ",
    "Sprint planning": "スプリントプランニング",
    "Lunch with Sam": "健太さんとランチ",
    "1:1 with Alex": "大輔さんと1on1",
    "Customer call": "顧客との電話",
    "Dentist": "歯医者",
    "Roadmap sync": "ロードマップ共有会",
    "Morning gym": "朝ジム",
    "Demo day": "デモデー",
    "Team offsite": "チーム合宿",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "まずは合宿のアジェンダから。決まらないと会場を予約できないので、予約は明日に回しました。午後は会議が2件あります。",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "内容が頭に入っているうちに、計画レビューを先に。同期レイヤーのリファクタリングは、昼前の長い時間枠に入れました。",
    "The launch checklist first; the status update after the design review.":
      "まずリリースのチェックリスト。進捗報告はデザインレビューのあとで。",

    // Memory.
    "notes_for_ai": "AIへのメモ",
    "new_laptop": "新しいノートPC",
    "work_rhythm": "仕事のリズム",
    "working_hours": "仕事の時間帯",
    "manager": "上司",
    "writing_style": "文章のスタイル",
    "current_focus": "現在の重点",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "ユーザーは個人開発のプロジェクトで使うUIフレームワークをいくつか比較中。技術面の提案は、特定のフレームワークに偏らないこと。",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "ノートPCを買い替える前に、データベースと写真ライブラリを書き出しておく。移行で何も失わないように。",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "ディープワークは昼前に行い、午後は会議とメールに充てる。",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "集中できるのは午前9時〜12時。午前中はディープワークのために確保すること。",
    "Reports to Alex; weekly 1:1 on Mondays.": "報告先は大輔さん。毎週月曜に1on1がある。",
    "Prefers concise, direct updates — no filler.": "簡潔で率直な報告を好む。前置きは不要。",
    "Shipping the Apple-native rewrite this quarter.": "今四半期にAppleネイティブ版へのリライトをリリースする。",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.": "1週間を振り返り、来週の合宿準備の段取りをつけた。",
    "Cleared the inbox and locked in the offsite dates.": "インボックスを空にして、合宿の日程を確定した。",
    "Still waiting on venue quotes before booking.": "会場の見積もり待ちで、予約はまだ。",
    "Batching errands into one afternoon freed up the rest of the week.": "用事を午後にまとめたら、週の残りが空いた。",
    "Solid morning of deep work; shipped the planning review.": "午前はしっかりディープワーク。計画レビューを終えた。",
    "Unblocked the sync layer; cleared the investor email.": "同期レイヤーの詰まりを解消し、投資家へのメールも片づけた。",
    "Waiting on design sign-off for the calendar grid.": "カレンダーグリッドのデザイン承認待ち。",
    "Batching reviews before noon keeps the afternoon open.": "レビューを昼前にまとめると、午後が空く。",
    "Steady progress across tasks.": "どのタスクも着実に前進。",
    "Closed a few items.": "いくつか完了。",
  ]
}
