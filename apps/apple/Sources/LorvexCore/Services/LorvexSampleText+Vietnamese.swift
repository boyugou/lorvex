extension LorvexSampleText {
  /// The sample datasets in Vietnamese. People are Minh (Sam), Hùng (Alex), and
  /// Lan (Maya) in every dataset; product names (Zoom, Swift, GRPO, Apple), the
  /// loanwords offsite, standup, sprint, roadmap, and checklist, and Q3 stay as
  /// written. The spring offsite becomes next quarter's. The car chore is the
  /// đăng kiểm, the periodic vehicle inspection. Task titles are bare verbs, the
  /// way Vietnamese to-do lists read; the briefings speak in the first person with
  /// tôi, the reviews carry no subject, and the app's own terms (đồng bộ hóa, Hộp
  /// thư đến) are the ones its catalogs use.
  static let vietnamese: [String: String] = [
    // Tags.
    "work": "công việc",
    "planning": "lập kế hoạch",
    "weekly": "hàng tuần",
    "home": "nhà",
    "urgent": "khẩn cấp",
    "engineering": "kỹ thuật",
    "research": "nghiên cứu",
    "someday": "một ngày nào đó",

    // Lists.
    "Apple Native": "Hệ sinh thái Apple",
    "Apple ecosystem apps and gear to try": "Ứng dụng và thiết bị trong hệ sinh thái Apple để thử",
    "Work": "Công việc",
    "Day job & deep work": "Công việc chính & làm việc tập trung",
    "Personal": "Cá nhân",
    "Reading": "Tài liệu đọc",
    "Papers & books": "Bài báo & sách",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "Soạn chương trình họp offsite của nhóm",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "Sắp xếp các phiên, chọn diễn giả chính và dành thời gian cho các buổi thảo luận nhóm nhỏ.",
    "Confirm session topics with the leads": "Xác nhận chủ đề các phiên với các trưởng nhóm",
    "Share the draft agenda for feedback": "Chia sẻ bản nháp chương trình để xin góp ý",
    "Book the offsite venue": "Đặt địa điểm họp offsite",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "So sánh hai địa điểm trong danh sách rút gọn và đặt địa điểm phù hợp nhất với nhóm.",
    "Send the weekly status update": "Gửi cập nhật trạng thái hàng tuần",
    "Summarize progress, blockers, and next steps for the team.":
      "Tóm tắt tiến độ, trở ngại và các bước tiếp theo cho nhóm.",
    "Look into a standing-desk setup": "Tìm hiểu về bàn đứng làm việc",
    "Keep this as a someday idea until the home office is sorted.":
      "Giữ làm ý tưởng cho sau này, cho đến khi chỗ làm việc ở nhà được sắp xếp xong.",
    "Pick the offsite dates": "Chọn ngày họp offsite",
    "Cross-check the team calendar and lock the week.": "Đối chiếu lịch của nhóm và chốt tuần.",
    "Order a second monitor": "Đặt mua màn hình thứ hai",
    "Dropped in favour of using the laptop display on the desk.":
      "Bỏ vì dùng màn hình laptop trên bàn là đủ.",
    "Renew the car registration": "Đi đăng kiểm xe ô tô",
    "Reply to Maya about the catering quote": "Trả lời Lan về báo giá dịch vụ ăn uống",
    "Review the Q3 budget draft": "Xem lại bản nháp ngân sách Q3",
    "Outline the board deck": "Phác thảo bài thuyết trình cho hội đồng quản trị",
    "Draft the hiring plan": "Soạn kế hoạch tuyển dụng",
    "Reply to the investor update email": "Trả lời email cập nhật cho nhà đầu tư",
    "Review the Q3 planning doc": "Xem lại tài liệu kế hoạch Q3",
    "Refactor the sync layer": "Tái cấu trúc lớp đồng bộ hóa",
    "Buy groceries for the week": "Mua đồ tạp hóa cho cả tuần",
    "Read the GRPO paper": "Đọc bài báo về GRPO",
    "Renew passport": "Gia hạn hộ chiếu",
    "Plan the spring offsite": "Lên kế hoạch họp offsite quý sau",
    "Submit the weekly timesheet": "Nộp bảng chấm công hàng tuần",
    "Book the dentist appointment": "Đặt lịch hẹn với nha sĩ",
    "Review the launch checklist": "Xem lại checklist ra mắt",

    // Deferral notes.
    "The agenda comes first": "Làm chương trình trước",
    "Groceries can wait for the evening": "Việc mua đồ tạp hóa có thể đợi đến tối",

    // Habits and their cues.
    "Daily Review": "Tổng kết hàng ngày",
    "End of day": "Cuối ngày",
    "Evening walk": "Đi bộ buổi tối",
    "After dinner": "Sau bữa tối",
    "Morning run": "Chạy bộ buổi sáng",
    "After waking up": "Sau khi thức dậy",
    "Read 30 minutes": "Đọc sách 30 phút",
    "Read 30 min": "Đọc 30 phút",
    "Before bed": "Trước khi ngủ",
    "Meditate": "Thiền",
    "Mid-morning": "Giữa buổi sáng",
    "Review the day": "Tổng kết một ngày",
    "Evening": "Buổi tối",
    "Evening journal": "Nhật ký buổi tối",

    // Calendar events and locations.
    "Swift migration review": "Rà soát chuyển đổi sang Swift",
    "Conference Room B": "Phòng họp B",
    "Team standup": "Họp standup của nhóm",
    "1:1 with Sam": "1:1 với Minh",
    "Design review": "Đánh giá thiết kế",
    "Studio": "Studio",
    "Sprint planning": "Lập kế hoạch sprint",
    "Lunch with Sam": "Ăn trưa với Minh",
    "1:1 with Alex": "1:1 với Hùng",
    "Customer call": "Cuộc gọi với khách hàng",
    "Dentist": "Nha sĩ",
    "Roadmap sync": "Họp đồng bộ roadmap",
    "Morning gym": "Tập gym buổi sáng",
    "Demo day": "Ngày demo",
    "Team offsite": "Offsite của nhóm",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "Ưu tiên chương trình họp offsite trước: chưa thể đặt địa điểm khi chương trình chưa chốt, nên tôi đã dời việc đặt chỗ sang ngày mai. Chiều nay có hai cuộc họp.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "Xem lại kế hoạch trước, khi tài liệu còn mới; phần tái cấu trúc lớp đồng bộ hóa chiếm khoảng thời gian dài trước bữa trưa.",
    "The launch checklist first; the status update after the design review.":
      "Checklist ra mắt trước; cập nhật trạng thái sau buổi đánh giá thiết kế.",

    // Memory.
    "notes_for_ai": "Ghi chú cho AI",
    "new_laptop": "Laptop mới",
    "work_rhythm": "Nhịp làm việc",
    "working_hours": "Giờ làm việc",
    "manager": "Quản lý",
    "writing_style": "Phong cách viết",
    "current_focus": "Trọng tâm hiện tại",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "Người dùng đang cân nhắc một vài framework giao diện cho dự án phụ cá nhân – hãy giữ các gợi ý kỹ thuật trung lập về framework.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "Trước khi chuyển sang laptop mới, hãy xuất cơ sở dữ liệu và thư viện ảnh để không mất gì khi chuyển.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "Làm việc tập trung trước bữa trưa và dành buổi chiều cho các cuộc họp và email.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "Tập trung tốt nhất từ 9 giờ đến 12 giờ; dành buổi sáng cho công việc cần tập trung.",
    "Reports to Alex; weekly 1:1 on Mondays.": "Báo cáo cho Hùng; họp 1:1 hàng tuần vào thứ Hai.",
    "Prefers concise, direct updates — no filler.":
      "Thích cập nhật ngắn gọn, trực tiếp – không dài dòng.",
    "Shipping the Apple-native rewrite this quarter.":
      "Phát hành bản viết lại Apple-native trong quý này.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "Đã tổng kết tuần và chuẩn bị kế hoạch họp offsite cho tuần tới.",
    "Cleared the inbox and locked in the offsite dates.":
      "Đã dọn sạch Hộp thư đến và chốt ngày họp offsite.",
    "Still waiting on venue quotes before booking.": "Vẫn đang chờ báo giá địa điểm trước khi đặt.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "Gom hết việc vặt vào một buổi chiều giúp phần còn lại của tuần thoải mái hơn.",
    "Solid morning of deep work; shipped the planning review.":
      "Một buổi sáng làm việc tập trung hiệu quả; phần xem lại kế hoạch đã xong.",
    "Unblocked the sync layer; cleared the investor email.":
      "Đã gỡ vướng cho lớp đồng bộ hóa; đã xử lý xong email nhà đầu tư.",
    "Waiting on design sign-off for the calendar grid.": "Đang chờ duyệt thiết kế cho lưới lịch.",
    "Batching reviews before noon keeps the afternoon open.":
      "Gom các buổi xem lại vào trước buổi trưa giúp buổi chiều thoải mái.",
    "Steady progress across tasks.": "Tiến độ ổn định trên các nhiệm vụ.",
    "Closed a few items.": "Đã hoàn thành vài nhiệm vụ.",
  ]
}
