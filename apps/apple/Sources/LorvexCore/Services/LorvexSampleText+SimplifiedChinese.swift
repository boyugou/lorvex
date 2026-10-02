extension LorvexSampleText {
  /// The sample datasets in Simplified Chinese. People are 林悦 (Sam),
  /// 陈晨 (Alex), and 周敏 (Maya) in every dataset; product names (Zoom,
  /// Swift, GRPO, Apple) stay as written.
  static let simplifiedChinese: [String: String] = [
    // Tags.
    "work": "工作",
    "planning": "规划",
    "weekly": "每周",
    "home": "生活",
    "urgent": "紧急",
    "engineering": "工程",
    "research": "研究",
    "someday": "以后",

    // Lists.
    "Apple Native": "苹果生态",
    "Apple ecosystem apps and gear to try": "想试试的苹果生态应用和设备",
    "Work": "工作",
    "Day job & deep work": "本职工作与深度工作",
    "Personal": "个人",
    "Reading": "阅读",
    "Papers & books": "论文与书籍",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "起草团建议程",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "排好各个环节，选定主题分享，并留出分组讨论的时间。",
    "Confirm session topics with the leads": "和各组负责人确认议题",
    "Share the draft agenda for feedback": "分享议程草稿，收集反馈",
    "Book the offsite venue": "预订团建场地",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "比较入围的两个场地，订下最适合团队的那个。",
    "Send the weekly status update": "发送每周进展汇报",
    "Summarize progress, blockers, and next steps for the team.":
      "为团队总结本周进展、阻碍和下一步计划。",
    "Look into a standing-desk setup": "研究一下升降桌方案",
    "Keep this as a someday idea until the home office is sorted.":
      "家里的办公区收拾好之前，先当作以后再说的想法。",
    "Pick the offsite dates": "确定团建日期",
    "Cross-check the team calendar and lock the week.": "对照团队日历，定下具体哪一周。",
    "Order a second monitor": "买第二台显示器",
    "Dropped in favour of using the laptop display on the desk.": "不买了，直接用桌上的笔记本屏幕。",
    "Renew the car registration": "办理车辆年检",
    "Reply to Maya about the catering quote": "回复周敏的餐饮报价",
    "Review the Q3 budget draft": "审阅第三季度预算草案",
    "Outline the board deck": "列出董事会汇报提纲",
    "Draft the hiring plan": "起草招聘计划",
    "Reply to the investor update email": "回复投资人的进展邮件",
    "Review the Q3 planning doc": "审阅第三季度规划文档",
    "Refactor the sync layer": "重构同步层",
    "Buy groceries for the week": "采购这周的食材",
    "Read the GRPO paper": "读 GRPO 论文",
    "Renew passport": "换发护照",
    "Plan the spring offsite": "筹划春季团建",
    "Submit the weekly timesheet": "提交每周工时表",
    "Book the dentist appointment": "预约牙医",
    "Review the launch checklist": "过一遍发布检查清单",

    // Deferral notes.
    "The agenda comes first": "先定议程",
    "Groceries can wait for the evening": "买菜可以等到晚上",

    // Habits and their cues.
    "Daily Review": "每日回顾",
    "End of day": "一天结束时",
    "Evening walk": "晚间散步",
    "After dinner": "晚饭后",
    "Morning run": "晨跑",
    "After waking up": "起床后",
    "Read 30 minutes": "阅读 30 分钟",
    "Read 30 min": "阅读 30 分钟",
    "Before bed": "睡前",
    "Meditate": "冥想",
    "Mid-morning": "上午",
    "Review the day": "回顾今天",
    "Evening": "晚上",
    "Evening journal": "晚间日记",

    // Calendar events and locations.
    "Swift migration review": "Swift 迁移评审",
    "Conference Room B": "B 会议室",
    "Team standup": "团队站会",
    "1:1 with Sam": "和林悦一对一",
    "Design review": "设计评审",
    "Studio": "工作室",
    "Sprint planning": "迭代规划会",
    "Lunch with Sam": "和林悦吃午饭",
    "1:1 with Alex": "和陈晨一对一",
    "Customer call": "客户电话会",
    "Dentist": "看牙医",
    "Roadmap sync": "路线图同步会",
    "Morning gym": "早上健身",
    "Demo day": "演示日",
    "Team offsite": "团队团建",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "先定团建议程：议程没定下来就订不了场地，所以我把订场地挪到了明天。下午有两个会。",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "趁文档还新鲜，先做规划评审；午饭前那段整块时间留给同步层重构。",
    "The launch checklist first; the status update after the design review.":
      "先过发布检查清单，设计评审之后再发进展汇报。",

    // Memory.
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "用户正在为一个个人业余项目比较几个 UI 框架，提技术建议时不要偏向某个框架。",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "换笔记本电脑之前，先导出数据库和照片图库，免得迁移时丢东西。",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "午饭前做需要专注的工作，下午留给会议和邮件。",
    "Focuses best 9am–12pm; protect mornings for deep work.": "上午 9 点到 12 点最专注，早上留给深度工作。",
    "Reports to Alex; weekly 1:1 on Mondays.": "向陈晨汇报，每周一有一对一沟通。",
    "Prefers concise, direct updates — no filler.": "喜欢简洁直接的汇报，不要客套话。",
    "Shipping the Apple-native rewrite this quarter.": "本季度发布 Apple 原生重写版本。",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.": "回顾了这一周，排好了下周的团建筹备。",
    "Cleared the inbox and locked in the offsite dates.": "清空了收件箱，定下了团建日期。",
    "Still waiting on venue quotes before booking.": "还在等场地报价，暂时没法预订。",
    "Batching errands into one afternoon freed up the rest of the week.": "把杂事集中到一个下午处理，这周其余时间就空出来了。",
    "Solid morning of deep work; shipped the planning review.": "上午专注工作效率很高，完成了规划评审。",
    "Unblocked the sync layer; cleared the investor email.": "解决了同步层的阻碍，回复了投资人邮件。",
    "Waiting on design sign-off for the calendar grid.": "日历网格还在等设计确认。",
    "Batching reviews before noon keeps the afternoon open.": "把评审集中在中午前完成，下午就能空出来。",
    "Steady progress across tasks.": "各项任务稳步推进。",
    "Closed a few items.": "完成了几件事。",
  ]
}
