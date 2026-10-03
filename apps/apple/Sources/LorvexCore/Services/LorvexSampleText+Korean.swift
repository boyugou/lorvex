extension LorvexSampleText {
  /// The sample datasets in Korean. People are 민준 님 (Sam), 지훈 님 (Alex),
  /// and 서연 님 (Maya) in every dataset, with the honorific 님 that a Korean
  /// workplace puts after a given name; product names (Zoom, Swift, GRPO,
  /// Apple) stay as written, and Q3 is written 3분기. The team offsite is a
  /// 워크숍, and the car chore is the 자동차 정기검사, the periodic vehicle
  /// inspection.
  static let korean: [String: String] = [
    // Tags.
    "work": "업무",
    "planning": "계획",
    "weekly": "주간",
    "home": "집",
    "urgent": "긴급",
    "engineering": "개발",
    "research": "연구",
    "someday": "언젠가",

    // Lists.
    "Apple Native": "Apple 생태계",
    "Apple ecosystem apps and gear to try": "써 보고 싶은 Apple 앱과 기기",
    "Work": "업무",
    "Day job & deep work": "본업과 딥워크",
    "Personal": "개인",
    "Reading": "독서",
    "Papers & books": "논문과 책",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "팀 워크숍 아젠다 초안 쓰기",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "세션 시간을 배분하고, 기조연설을 정하고, 소그룹 토론 시간도 남겨 두기.",
    "Confirm session topics with the leads": "팀장들과 세션 주제 확인하기",
    "Share the draft agenda for feedback": "아젠다 초안 공유하고 피드백 받기",
    "Book the offsite venue": "워크숍 장소 예약하기",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "후보 두 곳을 비교해서 팀에 맞는 곳으로 예약하기.",
    "Send the weekly status update": "주간 보고 보내기",
    "Summarize progress, blockers, and next steps for the team.": "진행 상황, 이슈, 다음 단계를 팀에 정리해서 공유하기.",
    "Look into a standing-desk setup": "스탠딩 데스크 알아보기",
    "Keep this as a someday idea until the home office is sorted.":
      "홈오피스가 정리될 때까지는 ‘언젠가’ 아이디어로 보류.",
    "Pick the offsite dates": "워크숍 날짜 정하기",
    "Cross-check the team calendar and lock the week.": "팀 캘린더와 맞춰 보고 진행할 주를 확정하기.",
    "Order a second monitor": "모니터 한 대 더 주문하기",
    "Dropped in favour of using the laptop display on the desk.": "취소. 책상에서는 노트북 화면으로 충분함.",
    "Renew the car registration": "자동차 정기검사 받기",
    "Reply to Maya about the catering quote": "서연 님께 케이터링 견적 답장하기",
    "Review the Q3 budget draft": "3분기 예산안 초안 검토하기",
    "Outline the board deck": "이사회 발표 자료 개요 잡기",
    "Draft the hiring plan": "채용 계획 초안 작성하기",
    "Reply to the investor update email": "투자자 업데이트 메일에 회신하기",
    "Review the Q3 planning doc": "3분기 기획 문서 검토하기",
    "Refactor the sync layer": "동기화 레이어 리팩터링하기",
    "Buy groceries for the week": "이번 주 장보기",
    "Read the GRPO paper": "GRPO 논문 읽기",
    "Renew passport": "여권 갱신하기",
    "Plan the spring offsite": "봄 워크숍 계획하기",
    "Submit the weekly timesheet": "주간 근무 시간표 제출하기",
    "Book the dentist appointment": "치과 예약하기",
    "Review the launch checklist": "출시 체크리스트 점검하기",

    // Deferral notes.
    "The agenda comes first": "아젠다가 먼저",
    "Groceries can wait for the evening": "장보기는 저녁에 해도 됨",

    // Habits and their cues.
    "Daily Review": "일일 회고",
    "End of day": "하루를 마칠 때",
    "Evening walk": "저녁 산책",
    "After dinner": "저녁 식사 후",
    "Morning run": "아침 러닝",
    "After waking up": "일어난 직후",
    "Read 30 minutes": "독서 30분",
    "Read 30 min": "독서 30분",
    "Before bed": "자기 전",
    "Meditate": "명상",
    "Mid-morning": "오전 중",
    "Review the day": "하루 돌아보기",
    "Evening": "저녁",
    "Evening journal": "저녁 일기",

    // Calendar events and locations.
    "Swift migration review": "Swift 마이그레이션 리뷰",
    "Conference Room B": "B 회의실",
    "Team standup": "팀 스탠드업",
    "1:1 with Sam": "민준 님과 1:1",
    "Design review": "디자인 리뷰",
    "Studio": "스튜디오",
    "Sprint planning": "스프린트 플래닝",
    "Lunch with Sam": "민준 님과 점심",
    "1:1 with Alex": "지훈 님과 1:1",
    "Customer call": "고객 통화",
    "Dentist": "치과",
    "Roadmap sync": "로드맵 싱크",
    "Morning gym": "아침 헬스",
    "Demo day": "데모 데이",
    "Team offsite": "팀 워크숍",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "워크숍 아젠다가 먼저예요. 아젠다가 정해져야 장소를 예약할 수 있어서 예약은 내일로 미뤘어요. 오늘 오후에는 회의가 두 개 있어요.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "기억이 생생할 때 기획 리뷰를 먼저 하고, 동기화 레이어 리팩터링은 점심 전 긴 시간대에 넣었어요.",
    "The launch checklist first; the status update after the design review.":
      "출시 체크리스트를 먼저 보고, 주간 보고는 디자인 리뷰 뒤에 보내요.",

    // Memory.
    "notes_for_ai": "AI 참고 메모",
    "new_laptop": "새 노트북",
    "work_rhythm": "업무 리듬",
    "working_hours": "업무 시간",
    "manager": "매니저",
    "writing_style": "글쓰기 스타일",
    "current_focus": "현재 집중 과제",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "개인 사이드 프로젝트에 쓸 UI 프레임워크를 몇 가지 비교 중이므로, 기술 제안은 특정 프레임워크에 치우치지 않게 할 것.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "노트북을 바꾸기 전에 데이터베이스와 사진 보관함을 내보내서 이전 과정에서 잃는 것이 없게 할 것.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "딥워크는 점심 전에 하고, 오후는 회의와 이메일에 쓴다.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "오전 9시~12시에 가장 집중이 잘 되므로, 오전은 딥워크 시간으로 지킬 것.",
    "Reports to Alex; weekly 1:1 on Mondays.": "지훈 님에게 보고하며, 매주 월요일에 1:1을 한다.",
    "Prefers concise, direct updates — no filler.": "군더더기 없이 간결하고 직접적인 업데이트를 선호한다.",
    "Shipping the Apple-native rewrite this quarter.": "이번 분기에 Apple 네이티브 재작성 버전을 출시할 예정.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.": "한 주를 돌아보고 다음 주 워크숍 준비를 잡아 뒀다.",
    "Cleared the inbox and locked in the offsite dates.": "수신함을 비우고 워크숍 날짜를 확정했다.",
    "Still waiting on venue quotes before booking.": "장소 견적을 기다리는 중이라 예약은 아직.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "잡무를 오후 한 번에 몰아서 처리했더니 남은 한 주가 여유로워졌다.",
    "Solid morning of deep work; shipped the planning review.": "오전에 딥워크가 잘 돼서 기획 리뷰를 끝냈다.",
    "Unblocked the sync layer; cleared the investor email.": "동기화 레이어 문제를 풀고 투자자 메일도 처리했다.",
    "Waiting on design sign-off for the calendar grid.": "캘린더 그리드 디자인 승인을 기다리는 중.",
    "Batching reviews before noon keeps the afternoon open.": "리뷰를 점심 전에 몰아서 하면 오후를 비워 둘 수 있다.",
    "Steady progress across tasks.": "모든 할 일이 꾸준히 진행 중.",
    "Closed a few items.": "몇 가지를 마무리했다.",
  ]
}
