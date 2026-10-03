extension LorvexSampleText {
  /// The sample datasets in Traditional Chinese, in Taiwan usage. People are
  /// 志明 (Sam), 家豪 (Alex), and 怡君 (Maya) in every dataset; product names
  /// (Zoom, Swift, GRPO, Apple) stay as written, and Q3 is written 第三季. The
  /// team offsite is a 共識營, and the car chore is 驗車, the vehicle
  /// inspection.
  static let traditionalChinese: [String: String] = [
    // Tags.
    "work": "工作",
    "planning": "規劃",
    "weekly": "每週",
    "home": "居家",
    "urgent": "緊急",
    "engineering": "工程",
    "research": "研究",
    "someday": "將來",

    // Lists.
    "Apple Native": "Apple 生態系",
    "Apple ecosystem apps and gear to try": "想試試的 Apple App 與裝置",
    "Work": "工作",
    "Day job & deep work": "正職與深度工作",
    "Personal": "個人",
    "Reading": "閱讀",
    "Papers & books": "論文與書籍",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "草擬共識營議程",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "排好各場次、選定主題演講，並留一些時間給分組討論。",
    "Confirm session topics with the leads": "跟各組負責人確認場次主題",
    "Share the draft agenda for feedback": "分享議程草稿並收集回饋",
    "Book the offsite venue": "預訂共識營場地",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "比較兩個候選場地，訂下最適合團隊的那一個。",
    "Send the weekly status update": "寄出每週進度回報",
    "Summarize progress, blockers, and next steps for the team.": "為團隊整理目前進度、阻礙事項和下一步。",
    "Look into a standing-desk setup": "研究一下升降桌的配置",
    "Keep this as a someday idea until the home office is sorted.": "家裡的工作空間整理好之前，先當作「將來再說」的點子。",
    "Pick the offsite dates": "決定共識營日期",
    "Cross-check the team calendar and lock the week.": "對照團隊行事曆，敲定是哪一週。",
    "Order a second monitor": "訂購第二台螢幕",
    "Dropped in favour of using the laptop display on the desk.": "不買了，直接用桌上的筆電螢幕就好。",
    "Renew the car registration": "安排驗車",
    "Reply to Maya about the catering quote": "回覆怡君外燴報價的事",
    "Review the Q3 budget draft": "審閱第三季預算初稿",
    "Outline the board deck": "擬好董事會簡報大綱",
    "Draft the hiring plan": "擬定徵才計畫",
    "Reply to the investor update email": "回覆投資人的近況更新信件",
    "Review the Q3 planning doc": "審閱第三季規劃文件",
    "Refactor the sync layer": "重構同步層",
    "Buy groceries for the week": "採買這週的食材",
    "Read the GRPO paper": "讀 GRPO 論文",
    "Renew passport": "換發護照",
    "Plan the spring offsite": "規劃春季共識營",
    "Submit the weekly timesheet": "繳交每週工時表",
    "Book the dentist appointment": "預約看牙醫",
    "Review the launch checklist": "過一遍上線核對清單",

    // Deferral notes.
    "The agenda comes first": "先確定議程",
    "Groceries can wait for the evening": "採買可以等到晚上",

    // Habits and their cues.
    "Daily Review": "每日回顧",
    "End of day": "一天結束時",
    "Evening walk": "晚上散步",
    "After dinner": "晚餐後",
    "Morning run": "晨跑",
    "After waking up": "起床後",
    "Read 30 minutes": "閱讀 30 分鐘",
    "Read 30 min": "閱讀 30 分鐘",
    "Before bed": "睡前",
    "Meditate": "冥想",
    "Mid-morning": "上午",
    "Review the day": "回顧今天",
    "Evening": "晚上",
    "Evening journal": "晚上寫日記",

    // Calendar events and locations.
    "Swift migration review": "Swift 遷移審查",
    "Conference Room B": "B 會議室",
    "Team standup": "團隊站立會議",
    "1:1 with Sam": "跟志明一對一",
    "Design review": "設計審查",
    "Studio": "工作室",
    "Sprint planning": "Sprint 規劃會議",
    "Lunch with Sam": "跟志明吃午餐",
    "1:1 with Alex": "跟家豪一對一",
    "Customer call": "客戶電話",
    "Dentist": "看牙醫",
    "Roadmap sync": "路線圖同步會議",
    "Morning gym": "早上健身",
    "Demo day": "成果展示日",
    "Team offsite": "團隊共識營",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "先確定共識營議程：議程沒定下來就無法預訂場地，所以我把預訂挪到明天。今天下午有兩場會議。",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "趁文件內容還記得清楚，先做規劃審查；午餐前那段完整的時間留給同步層重構。",
    "The launch checklist first; the status update after the design review.":
      "先過上線核對清單；進度回報等設計審查結束後再寄。",

    // Memory.
    "notes_for_ai": "給 AI 的備註",
    "new_laptop": "換新筆電",
    "work_rhythm": "工作節奏",
    "working_hours": "工作時間",
    "manager": "主管",
    "writing_style": "寫作風格",
    "current_focus": "目前重點",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "使用者正在為一個個人業餘專案比較幾個 UI 框架，給技術建議時請不要偏向特定框架。",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "換筆電之前，先匯出資料庫與照片圖庫，避免搬移時遺失東西。",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "深度工作安排在午餐前，下午留給會議和電子郵件。",
    "Focuses best 9am–12pm; protect mornings for deep work.": "上午 9 點到中午 12 點專注力最好，早上的時間要留給深度工作。",
    "Reports to Alex; weekly 1:1 on Mondays.": "直屬主管是家豪，每週一固定一對一。",
    "Prefers concise, direct updates — no filler.": "偏好簡潔直接的回報，不必客套。",
    "Shipping the Apple-native rewrite this quarter.": "本季要推出 Apple 原生重寫版。",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.": "回顧了這一週，也排好下週共識營的籌備工作。",
    "Cleared the inbox and locked in the offsite dates.": "清空了收件匣，也敲定了共識營日期。",
    "Still waiting on venue quotes before booking.": "還在等場地報價，暫時沒辦法預訂。",
    "Batching errands into one afternoon freed up the rest of the week.":
      "把雜事集中在一個下午處理，這週剩下的時間就空出來了。",
    "Solid morning of deep work; shipped the planning review.": "上午深度工作很順利，完成了規劃審查。",
    "Unblocked the sync layer; cleared the investor email.": "排除了同步層的阻礙，也回覆了投資人的信。",
    "Waiting on design sign-off for the calendar grid.": "行事曆網格還在等設計確認。",
    "Batching reviews before noon keeps the afternoon open.": "把審查集中在中午前完成，下午就能空出來。",
    "Steady progress across tasks.": "各項任務穩定推進中。",
    "Closed a few items.": "完成了幾件事。",
  ]
}
