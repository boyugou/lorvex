extension LorvexSampleText {
  /// The sample datasets in Thai. People are นนท์ (Sam), เอก (Alex), and มายา
  /// (Maya) in every dataset; product names (Zoom, Swift, GRPO, Apple) and Q3
  /// stay as written, and Q3 is written ไตรมาส 3. The team offsite is a สัมมนาทีม,
  /// and the car chore is the ต่อทะเบียนรถยนต์, the vehicle registration
  /// renewal. Thai puts no spaces between words, so phrases are separated by a
  /// space and a space sits around each Latin or numeric token; sentences carry
  /// no final period. Task titles are bare verbs, the way Thai to-do lists read,
  /// and the app's own terms (เชื่อมข้อมูล, กล่องเข้า, เช็คลิสต์) are the ones its
  /// catalogs use. The spring offsite becomes next quarter's, since Thailand has
  /// no spring.
  static let thai: [String: String] = [
    // Tags.
    "work": "งาน",
    "planning": "การวางแผน",
    "weekly": "รายสัปดาห์",
    "home": "บ้าน",
    "urgent": "ด่วน",
    "engineering": "วิศวกรรม",
    "research": "การค้นคว้า",
    "someday": "สักวัน",

    // Lists.
    "Apple Native": "ระบบนิเวศ Apple",
    "Apple ecosystem apps and gear to try":
      "แอปและอุปกรณ์ในระบบนิเวศ Apple ที่อยากลอง",
    "Work": "งาน",
    "Day job & deep work": "งานประจำและงานที่ต้องใช้สมาธิ",
    "Personal": "ส่วนตัว",
    "Reading": "การอ่าน",
    "Papers & books": "เปเปอร์และหนังสือ",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "ร่างกำหนดการสัมมนาทีม",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "กันเวลาสำหรับแต่ละช่วง เลือกผู้บรรยายหลัก และเว้นเวลาไว้สำหรับกลุ่มย่อย",
    "Confirm session topics with the leads":
      "ยืนยันหัวข้อของแต่ละช่วงกับหัวหน้าทีม",
    "Share the draft agenda for feedback": "แชร์ร่างกำหนดการเพื่อขอความเห็น",
    "Book the offsite venue": "จองสถานที่สัมมนา",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "เปรียบเทียบสถานที่ 2 แห่งที่คัดไว้ แล้วจองแห่งที่เหมาะกับกลุ่ม",
    "Send the weekly status update": "ส่งอัปเดตสถานะประจำสัปดาห์",
    "Summarize progress, blockers, and next steps for the team.":
      "สรุปความคืบหน้า อุปสรรค และขั้นตอนถัดไปให้ทีม",
    "Look into a standing-desk setup": "หาข้อมูลโต๊ะทำงานแบบยืน",
    "Keep this as a someday idea until the home office is sorted.":
      "เก็บไว้เป็นไอเดียสำหรับสักวัน จนกว่าจะจัดมุมทำงานที่บ้านเสร็จ",
    "Pick the offsite dates": "เลือกวันสัมมนา",
    "Cross-check the team calendar and lock the week.":
      "ตรวจสอบกับปฏิทินของทีมแล้วล็อกสัปดาห์ให้เรียบร้อย",
    "Order a second monitor": "สั่งจอภาพเพิ่มอีกหนึ่งจอ",
    "Dropped in favour of using the laptop display on the desk.":
      "ยกเลิกเพราะใช้หน้าจอแล็ปท็อปบนโต๊ะแทน",
    "Renew the car registration": "ต่อทะเบียนรถยนต์",
    "Reply to Maya about the catering quote":
      "ตอบมายาเรื่องใบเสนอราคาอาหารจัดเลี้ยง",
    "Review the Q3 budget draft": "ตรวจร่างงบประมาณไตรมาส 3",
    "Outline the board deck": "ร่างโครงสไลด์สำหรับคณะกรรมการ",
    "Draft the hiring plan": "ร่างแผนการรับสมัครพนักงาน",
    "Reply to the investor update email": "ตอบอีเมลอัปเดตนักลงทุน",
    "Review the Q3 planning doc": "ตรวจเอกสารวางแผนไตรมาส 3",
    "Refactor the sync layer": "ปรับโครงสร้างเลเยอร์การเชื่อมข้อมูล",
    "Buy groceries for the week": "ซื้อของใช้และอาหารสำหรับสัปดาห์นี้",
    "Read the GRPO paper": "อ่านเปเปอร์ GRPO",
    "Renew passport": "ต่ออายุหนังสือเดินทาง",
    "Plan the spring offsite": "วางแผนสัมมนาทีมไตรมาสหน้า",
    "Submit the weekly timesheet": "ส่งใบลงเวลาทำงานประจำสัปดาห์",
    "Book the dentist appointment": "นัดหมายทันตแพทย์",
    "Review the launch checklist": "ตรวจเช็คลิสต์ก่อนเปิดตัว",

    // Deferral notes.
    "The agenda comes first": "กำหนดการต้องมาก่อน",
    "Groceries can wait for the evening": "ซื้อของไว้ตอนเย็นได้",

    // Habits and their cues.
    "Daily Review": "ทบทวนประจำวัน",
    "End of day": "ตอนจบวัน",
    "Evening walk": "เดินเล่นตอนเย็น",
    "After dinner": "หลังอาหารเย็น",
    "Morning run": "วิ่งตอนเช้า",
    "After waking up": "หลังตื่นนอน",
    "Read 30 minutes": "อ่านหนังสือ 30 นาที",
    "Read 30 min": "อ่าน 30 นาที",
    "Before bed": "ก่อนนอน",
    "Meditate": "นั่งสมาธิ",
    "Mid-morning": "ช่วงสาย",
    "Review the day": "ทบทวนวันนี้",
    "Evening": "ตอนเย็น",
    "Evening journal": "บันทึกตอนเย็น",

    // Calendar events and locations.
    "Swift migration review": "ทบทวนการย้ายไป Swift",
    "Conference Room B": "ห้องประชุม B",
    "Team standup": "สแตนด์อัปของทีม",
    "1:1 with Sam": "คุย 1:1 กับนนท์",
    "Design review": "ทบทวนดีไซน์",
    "Studio": "สตูดิโอ",
    "Sprint planning": "วางแผนสปรินต์",
    "Lunch with Sam": "ทานข้าวกลางวันกับนนท์",
    "1:1 with Alex": "คุย 1:1 กับเอก",
    "Customer call": "โทรคุยกับลูกค้า",
    "Dentist": "ทันตแพทย์",
    "Roadmap sync": "ประชุมโรดแมป",
    "Morning gym": "ออกกำลังกายตอนเช้า",
    "Demo day": "วันเดโม",
    "Team offsite": "สัมมนาทีม",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "กำหนดการสัมมนามาก่อน เพราะจองสถานที่ไม่ได้จนกว่าจะสรุป จึงเลื่อนการจองไปพรุ่งนี้ บ่ายนี้มีประชุม 2 รายการ",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "ตรวจเอกสารวางแผนก่อนขณะที่ยังจำได้ดี ส่วนการปรับโครงสร้างเลเยอร์เชื่อมข้อมูลใช้ช่วงยาวก่อนพักเที่ยง",
    "The launch checklist first; the status update after the design review.":
      "เช็คลิสต์ก่อนเปิดตัวมาก่อน ส่วนอัปเดตสถานะทำหลังทบทวนดีไซน์",

    // Memory.
    "notes_for_ai": "บันทึกสำหรับ AI",
    "new_laptop": "แล็ปท็อปเครื่องใหม่",
    "work_rhythm": "จังหวะการทำงาน",
    "working_hours": "เวลาทำงาน",
    "manager": "หัวหน้า",
    "writing_style": "สไตล์การเขียน",
    "current_focus": "สิ่งที่โฟกัสอยู่",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "ผู้ใช้กำลังชั่งใจระหว่างเฟรมเวิร์ก UI สองสามตัวสำหรับโปรเจกต์เสริมส่วนตัว — ควรเสนอแนะด้านเทคนิคแบบไม่เจาะจงเฟรมเวิร์ก",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "ก่อนเปลี่ยนแล็ปท็อป ให้ส่งออกฐานข้อมูลและคลังรูปภาพ เพื่อไม่ให้ข้อมูลหายระหว่างย้ายเครื่อง",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "ทำงานที่ต้องใช้สมาธิก่อนพักเที่ยง และเก็บช่วงบ่ายไว้สำหรับประชุมและอีเมล",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "มีสมาธิดีที่สุดช่วง 9:00–12:00 น. ควรกันช่วงเช้าไว้สำหรับงานที่ต้องใช้สมาธิ",
    "Reports to Alex; weekly 1:1 on Mondays.": "รายงานต่อเอก คุย 1:1 ทุกวันจันทร์",
    "Prefers concise, direct updates — no filler.":
      "ชอบอัปเดตที่กระชับตรงประเด็น ไม่ต้องมีคำฟุ่มเฟือย",
    "Shipping the Apple-native rewrite this quarter.":
      "กำลังปล่อยเวอร์ชันที่เขียนใหม่แบบเนทีฟบน Apple ในไตรมาสนี้",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "ทบทวนสัปดาห์นี้และเตรียมแผนสัมมนาของสัปดาห์หน้า",
    "Cleared the inbox and locked in the offsite dates.":
      "เคลียร์กล่องเข้าและล็อกวันสัมมนาเรียบร้อย",
    "Still waiting on venue quotes before booking.":
      "ยังรอใบเสนอราคาสถานที่ก่อนจอง",
    "Batching errands into one afternoon freed up the rest of the week.":
      "รวมธุระทั้งหมดไว้ในบ่ายเดียวทำให้เวลาที่เหลือของสัปดาห์ว่างขึ้น",
    "Solid morning of deep work; shipped the planning review.":
      "เช้านี้ทำงานที่ต้องใช้สมาธิได้เต็มที่ และตรวจเอกสารวางแผนเสร็จแล้ว",
    "Unblocked the sync layer; cleared the investor email.":
      "แก้ปัญหาติดขัดของเลเยอร์เชื่อมข้อมูลได้แล้ว และตอบอีเมลนักลงทุนเรียบร้อย",
    "Waiting on design sign-off for the calendar grid.":
      "รออนุมัติดีไซน์ของตารางปฏิทิน",
    "Batching reviews before noon keeps the afternoon open.":
      "รวมงานตรวจก่อนเที่ยงช่วยให้ช่วงบ่ายว่าง",
    "Steady progress across tasks.": "ทุกงานคืบหน้าอย่างสม่ำเสมอ",
    "Closed a few items.": "ปิดงานได้หลายรายการ",
  ]
}
