extension LorvexSampleText {
  /// The sample datasets in Turkish. People are Can (Sam), Alp (Alex), and Mina
  /// (Maya) in every dataset, and a suffix after a name follows an apostrophe
  /// (Mina’ya, Alp’e); product names (Zoom, Swift, GRPO, Apple) and Q3 stay as
  /// written. The team offsite is an ekip kampı, and the car chore is the araç
  /// muayenesi, the periodic vehicle inspection. Task titles are informal
  /// singular imperatives, the way a person writes them to themselves; the
  /// briefings and reviews use first-person verbs, which Turkish does not
  /// inflect for gender, and the app's own terms (Gelen Kutusu, eşzamanlama,
  /// kontrol listesi) are the ones its catalogs use.
  static let turkish: [String: String] = [
    // Tags.
    "work": "iş",
    "planning": "planlama",
    "weekly": "haftalık",
    "home": "ev",
    "urgent": "acil",
    "engineering": "mühendislik",
    "research": "araştırma",
    "someday": "bir gün",

    // Lists.
    "Apple Native": "Apple Ekosistemi",
    "Apple ecosystem apps and gear to try":
      "Denemek için Apple ekosistemi uygulamaları ve cihazları",
    "Work": "İş",
    "Day job & deep work": "Günlük işler ve derin çalışma",
    "Personal": "Kişisel",
    "Reading": "Okuma",
    "Papers & books": "Makaleler ve kitaplar",

    // Tasks, their notes, and checklist items.
    "Draft the team offsite agenda": "Ekip kampı gündemini taslak olarak hazırla",
    "Block out sessions, pick a keynote, and leave time for breakouts.":
      "Oturumları belirle, bir açılış konuşması seç ve grup çalışmalarına zaman bırak.",
    "Confirm session topics with the leads":
      "Oturum konularını ekip liderleriyle netleştir",
    "Share the draft agenda for feedback": "Taslak gündemi geri bildirim için paylaş",
    "Book the offsite venue": "Kamp mekânını rezerve et",
    "Compare the two shortlisted venues and reserve the one that fits the group.":
      "Kısa listedeki iki mekânı karşılaştır ve gruba uyanı rezerve et.",
    "Send the weekly status update": "Haftalık durum güncellemesini gönder",
    "Summarize progress, blockers, and next steps for the team.":
      "Ekip için ilerlemeyi, engelleri ve sonraki adımları özetle.",
    "Look into a standing-desk setup": "Ayakta çalışma masası kurulumunu araştır",
    "Keep this as a someday idea until the home office is sorted.":
      "Ev ofisi hazır olana kadar bunu ileride bakılacak bir fikir olarak sakla.",
    "Pick the offsite dates": "Kamp tarihlerini seç",
    "Cross-check the team calendar and lock the week.":
      "Ekip takvimiyle karşılaştır ve haftayı kesinleştir.",
    "Order a second monitor": "İkinci bir monitör sipariş et",
    "Dropped in favour of using the laptop display on the desk.":
      "Masada dizüstü bilgisayarın ekranını kullanmak için vazgeçildi.",
    "Renew the car registration": "Aracı muayeneye götür",
    "Reply to Maya about the catering quote":
      "Mina’ya yemek hizmeti teklifiyle ilgili yanıt ver",
    "Review the Q3 budget draft": "Q3 bütçe taslağını gözden geçir",
    "Outline the board deck": "Yönetim kurulu sunumunun taslağını çıkar",
    "Draft the hiring plan": "İşe alım planını taslak olarak hazırla",
    "Reply to the investor update email": "Yatırımcı güncellemesi e-postasını yanıtla",
    "Review the Q3 planning doc": "Q3 planlama belgesini gözden geçir",
    "Refactor the sync layer": "Eşzamanlama katmanını yeniden düzenle",
    "Buy groceries for the week": "Haftalık market alışverişini yap",
    "Read the GRPO paper": "GRPO makalesini oku",
    "Renew passport": "Pasaportu yenile",
    "Plan the spring offsite": "İlkbahar ekip kampını planla",
    "Submit the weekly timesheet": "Haftalık mesai çizelgesini gönder",
    "Book the dentist appointment": "Diş hekimi randevusu al",
    "Review the launch checklist": "Lansman kontrol listesini gözden geçir",

    // Deferral notes.
    "The agenda comes first": "Önce gündem",
    "Groceries can wait for the evening": "Market alışverişi akşama kalabilir",

    // Habits and their cues.
    "Daily Review": "Günlük gözden geçirme",
    "End of day": "Günün sonunda",
    "Evening walk": "Akşam yürüyüşü",
    "After dinner": "Akşam yemeğinden sonra",
    "Morning run": "Sabah koşusu",
    "After waking up": "Uyandıktan sonra",
    "Read 30 minutes": "30 dakika kitap oku",
    "Read 30 min": "30 dk kitap oku",
    "Before bed": "Yatmadan önce",
    "Meditate": "Meditasyon yap",
    "Mid-morning": "Sabahın ortasında",
    "Review the day": "Günü gözden geçir",
    "Evening": "Akşam",
    "Evening journal": "Akşam günlüğü",

    // Calendar events and locations.
    "Swift migration review": "Swift geçişi incelemesi",
    "Conference Room B": "B Toplantı Odası",
    "Team standup": "Günlük ekip toplantısı",
    "1:1 with Sam": "Can ile 1:1",
    "Design review": "Tasarım incelemesi",
    "Studio": "Stüdyo",
    "Sprint planning": "Sprint planlaması",
    "Lunch with Sam": "Can ile öğle yemeği",
    "1:1 with Alex": "Alp ile 1:1",
    "Customer call": "Müşteri görüşmesi",
    "Dentist": "Diş hekimi",
    "Roadmap sync": "Yol haritası toplantısı",
    "Morning gym": "Sabah spor salonu",
    "Demo day": "Demo günü",
    "Team offsite": "Ekip kampı",

    // The assistant's briefings.
    "The offsite agenda comes first: the venue can't be booked until it's settled, so I moved the booking to tomorrow. Two meetings this afternoon.":
      "Önce kamp gündemi: Gündem netleşmeden mekân rezerve edilemez, bu yüzden rezervasyonu yarına erteledim. Bugün öğleden sonra iki toplantı var.",
    "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.":
      "Belge tazeyken önce planlama incelemesi; eşzamanlama katmanının yeniden düzenlenmesi öğle yemeğinden önceki uzun bloğu alıyor.",
    "The launch checklist first; the status update after the design review.":
      "Önce lansman kontrol listesi; durum güncellemesi tasarım incelemesinden sonra.",

    // Memory.
    "notes_for_ai": "Yapay zekâ için notlar",
    "new_laptop": "Yeni dizüstü bilgisayar",
    "work_rhythm": "Çalışma ritmi",
    "working_hours": "Çalışma saatleri",
    "manager": "Yönetici",
    "writing_style": "Yazım tarzı",
    "current_focus": "Güncel odak",
    "The user is weighing a couple of UI frameworks for a personal side project — keep any tech suggestions framework-neutral.":
      "Kullanıcı kişisel bir yan proje için birkaç arayüz çerçevesini değerlendiriyor — teknik önerileri çerçeveden bağımsız tut.",
    "Before switching laptops, export the database and photo library so nothing is lost in the move.":
      "Dizüstü bilgisayarı değiştirmeden önce veritabanını ve fotoğraf kitaplığını dışa aktar; taşınma sırasında hiçbir şey kaybolmasın.",
    "Does deep work before lunch and keeps afternoons for meetings and email.":
      "Derin çalışmayı öğle yemeğinden önce yapar, öğleden sonralarını toplantı ve e-postalara ayırır.",
    "Focuses best 9am–12pm; protect mornings for deep work.":
      "En iyi 09:00–12:00 arasında odaklanır; sabahları derin çalışmaya ayır.",
    "Reports to Alex; weekly 1:1 on Mondays.":
      "Alp’e rapor verir; pazartesi günleri haftalık 1:1 yapar.",
    "Prefers concise, direct updates — no filler.":
      "Kısa ve doğrudan güncellemeleri tercih eder — dolgu olmasın.",
    "Shipping the Apple-native rewrite this quarter.":
      "Bu çeyrekte Apple’a özgü yeniden yazımı yayına alıyor.",

    // Daily reviews.
    "Reviewed the week and lined up next week's offsite planning.":
      "Haftayı gözden geçirdim ve gelecek haftanın kamp planlamasını hazırladım.",
    "Cleared the inbox and locked in the offsite dates.":
      "Gelen Kutusu’nu temizledim ve kamp tarihlerini kesinleştirdim.",
    "Still waiting on venue quotes before booking.":
      "Rezervasyondan önce mekân tekliflerini bekliyorum.",
    "Batching errands into one afternoon freed up the rest of the week.":
      "İşleri tek bir öğleden sonrada toplamak haftanın geri kalanını boşalttı.",
    "Solid morning of deep work; shipped the planning review.":
      "Derin çalışmayla geçen verimli bir sabah; planlama incelemesini tamamladım.",
    "Unblocked the sync layer; cleared the investor email.":
      "Eşzamanlama katmanındaki tıkanıklığı giderdim; yatırımcı e-postasını yanıtladım.",
    "Waiting on design sign-off for the calendar grid.":
      "Takvim ızgarası için tasarım onayını bekliyorum.",
    "Batching reviews before noon keeps the afternoon open.":
      "İncelemeleri öğleden önce toplamak öğleden sonrayı açık tutuyor.",
    "Steady progress across tasks.": "Görevlerde istikrarlı ilerleme.",
    "Closed a few items.": "Birkaç görevi kapattım.",
  ]
}
