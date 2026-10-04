extension LorvexSampleText {
  /// The sample datasets in Indonesian. People are Budi (Sam), Andi (Alex), and
  /// Sari (Maya) in every dataset; product names (Zoom, Swift, GRPO, Apple) and
  /// Q3 stay as written. The team offsite is a retret tim, and Indonesia has no
  /// spring, so the spring offsite becomes next quarter's. The car chore is the
  /// STNK renewal, the vehicle registration. Task titles are bare imperative
  /// verbs, the way Indonesian to-do lists read; the briefings speak in the first
  /// person with saya, the reviews carry no subject, and the app's own terms
  /// (penyelarasan, daftar centang, Inbox) are the ones its catalogs use.
  static let indonesian: [String: String] = [
    // Tags.
    "work": "kerja",
    "planning": "perencanaan",
    "weekly": "mingguan",
    "home": "rumah",
    "urgent": "mendesak",
    "engineering": "pengembangan",
    "research": "riset",
    "someday": "suatu hari",

    // Lists.
    "Apple Native": "Ekosistem Apple",
    "Apple ecosystem apps and gear to try": "App dan perangkat dari ekosistem Apple untuk dicoba",
    "Work": "Kerja",
    "Day job & deep work": "Pekerjaan utama & kerja fokus",
    "Personal": "Pribadi",
    "Reading": "Bacaan",
    "Papers & books": "Makalah & buku",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "Susun agenda retret tim",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "Jadwalkan sesi, pilih pembicara utama, dan sisakan waktu untuk diskusi kelompok kecil.",
    "Confirm session topics with the leads": "Konfirmasikan topik sesi dengan para ketua tim",
    "Share the draft agenda for feedback": "Bagikan draf agenda untuk meminta masukan",
    "Book the offsite venue": "Pesan tempat retret tim",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "Bandingkan dua tempat yang masuk daftar pendek, lalu pesan yang paling sesuai untuk tim.",
    "Send the weekly status update": "Kirim pembaruan status mingguan",
    "Summarize progress, blockers, and next steps for the team.":
      "Rangkum kemajuan, hambatan, dan langkah berikutnya untuk tim.",
    "Look into a standing-desk setup": "Cari tahu soal meja berdiri",
    "Keep this as a someday idea until the home office is sorted.":
      "Simpan sebagai ide suatu hari nanti sampai ruang kerja di rumah selesai ditata.",
    "Pick the offsite dates": "Tentukan tanggal retret tim",
    "Cross-check the team calendar and lock the week.": "Cek kalender tim dan tetapkan minggunya.",
    "Order a second monitor": "Pesan monitor kedua",
    "Dropped in favour of using the laptop display on the desk.":
      "Dibatalkan karena cukup memakai layar laptop di meja.",
    "Renew the car registration": "Perpanjang STNK mobil",
    "Reply to Maya about the catering quote": "Balas Sari soal penawaran katering",
    "Review the Q3 budget draft": "Tinjau draf anggaran Q3",
    "Outline the board deck": "Buat kerangka presentasi untuk dewan direksi",
    "Draft the hiring plan": "Susun rencana perekrutan",
    "Reply to the investor update email": "Balas email pembaruan untuk investor",
    "Review the Q3 planning doc": "Tinjau dokumen perencanaan Q3",
    "Refactor the sync layer": "Refaktor lapisan penyelarasan",
    "Buy groceries for the week": "Beli bahan makanan untuk seminggu",
    "Read the GRPO paper": "Baca makalah GRPO",
    "Renew passport": "Perpanjang paspor",
    "Plan the spring offsite": "Rencanakan retret tim kuartal depan",
    "Submit the weekly timesheet": "Kirim timesheet mingguan",
    "Book the dentist appointment": "Buat janji dengan dokter gigi",
    "Review the launch checklist": "Tinjau daftar centang peluncuran",

    // Deferral notes.
    "The agenda comes first": "Agenda dulu",
    "Groceries can wait for the evening": "Belanja bahan makanan bisa menunggu sampai malam",

    // Habits and their cues.
    "Daily Review": "Tinjauan Harian",
    "End of day": "Akhir hari",
    "Evening walk": "Jalan malam",
    "After dinner": "Setelah makan malam",
    "Morning run": "Lari pagi",
    "After waking up": "Setelah bangun tidur",
    "Read 30 minutes": "Baca 30 menit",
    "Read 30 min": "Baca 30 mnt",
    "Before bed": "Sebelum tidur",
    "Meditate": "Meditasi",
    "Mid-morning": "Tengah pagi",
    "Review the day": "Tinjau kembali hari ini",
    "Evening": "Malam",
    "Evening journal": "Jurnal malam",

    // Calendar events and locations.
    "Swift migration review": "Tinjauan migrasi Swift",
    "Conference Room B": "Ruang Rapat B",
    "Team standup": "Standup tim",
    "1:1 with Sam": "1:1 dengan Budi",
    "Design review": "Tinjauan desain",
    "Studio": "Studio",
    "Sprint planning": "Perencanaan sprint",
    "Lunch with Sam": "Makan siang dengan Budi",
    "1:1 with Alex": "1:1 dengan Andi",
    "Customer call": "Panggilan pelanggan",
    "Dentist": "Dokter gigi",
    "Roadmap sync": "Penyelarasan roadmap",
    "Morning gym": "Gym pagi",
    "Demo day": "Hari demo",
    "Team offsite": "Retret tim",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "Agenda retret tim didahulukan: tempat belum bisa dipesan sebelum agendanya final, jadi pemesanannya saya pindahkan ke besok. Ada dua rapat siang ini.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "Tinjau perencanaan dulu selagi dokumennya masih segar; refaktor lapisan penyelarasan mendapat blok waktu yang panjang sebelum makan siang.",
    "The launch checklist first; the status update after the design review.":
      "Daftar centang peluncuran dulu; pembaruan status setelah tinjauan desain.",

    // Memory.
    "notes_for_ai": "Catatan untuk AI",
    "new_laptop": "Laptop baru",
    "work_rhythm": "Ritme kerja",
    "working_hours": "Jam kerja",
    "manager": "Atasan",
    "writing_style": "Gaya penulisan",
    "current_focus": "Fokus saat ini",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "Pengguna sedang mempertimbangkan beberapa framework UI untuk proyek sampingan pribadi – usahakan saran teknis tetap netral terhadap framework.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "Sebelum berganti laptop, ekspor basis data dan Pustaka Foto agar tidak ada yang hilang saat pindah.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "Melakukan kerja fokus sebelum makan siang dan menyisakan sore untuk rapat dan email.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "Paling fokus pukul 09.00–12.00; lindungi waktu pagi untuk kerja fokus.",
    "Reports to Alex; weekly 1:1 on Mondays.": "Melapor kepada Andi; 1:1 mingguan setiap Senin.",
    "Prefers concise, direct updates — no filler.":
      "Lebih suka pembaruan yang ringkas dan langsung – tanpa basa-basi.",
    "Shipping the Apple-native rewrite this quarter.":
      "Merilis penulisan ulang Apple-native kuartal ini.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "Meninjau minggu ini dan menyiapkan perencanaan retret untuk minggu depan.",
    "Cleared the inbox and locked in the offsite dates.":
      "Mengosongkan Inbox dan menetapkan tanggal retret.",
    "Still waiting on venue quotes before booking.":
      "Masih menunggu penawaran harga tempat sebelum memesan.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "Mengumpulkan semua urusan dalam satu siang membebaskan sisa minggu ini.",
    "Solid morning of deep work; shipped the planning review.":
      "Pagi yang produktif untuk kerja fokus; tinjauan perencanaan selesai.",
    "Unblocked the sync layer; cleared the investor email.":
      "Hambatan di lapisan penyelarasan teratasi; email investor sudah dibalas.",
    "Waiting on design sign-off for the calendar grid.":
      "Menunggu persetujuan desain untuk kisi kalender.",
    "Batching reviews before noon keeps the afternoon open.":
      "Mengumpulkan semua tinjauan sebelum tengah hari membuat siang tetap lowong.",
    "Steady progress across tasks.": "Kemajuan stabil di semua tugas.",
    "Closed a few items.": "Beberapa tugas selesai.",
  ]
}
