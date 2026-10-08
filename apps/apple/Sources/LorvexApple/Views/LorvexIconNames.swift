import LorvexCore

/// Human names and search keywords for the SF Symbols the list and habit icon
/// picker offers, in the user's language.
///
/// The picker's buttons show only a glyph, so each one needs a name for its
/// tooltip and for VoiceOver, and the search field needs words a person would
/// type to look for an icon ("gym" for the dumbbell). Both come from the
/// string catalog, so a name or keyword is written in the interface language;
/// the symbol's own name stays searchable as well. A filled variant
/// (`star.fill`, chosen on an iPhone) has the name of its outline symbol.
enum LorvexIconNames {
  /// The localized name of `symbol`, or nil when the picker has none for it.
  static func name(for symbol: String) -> String? {
    switch outlineName(of: symbol) {
    case "list.bullet":
      return String(localized: "appearance.icon.name.list.bullet", defaultValue: "List", table: "Localizable", bundle: LorvexL10n.bundle)
    case "checklist":
      return String(localized: "appearance.icon.name.checklist", defaultValue: "Checklist", table: "Localizable", bundle: LorvexL10n.bundle)
    case "checkmark.seal":
      return String(localized: "appearance.icon.name.checkmark.seal", defaultValue: "Approved", table: "Localizable", bundle: LorvexL10n.bundle)
    case "star":
      return String(localized: "appearance.icon.name.star", defaultValue: "Star", table: "Localizable", bundle: LorvexL10n.bundle)
    case "flag":
      return String(localized: "appearance.icon.name.flag", defaultValue: "Flag", table: "Localizable", bundle: LorvexL10n.bundle)
    case "flag.checkered":
      return String(localized: "appearance.icon.name.flag.checkered", defaultValue: "Finish flag", table: "Localizable", bundle: LorvexL10n.bundle)
    case "tag":
      return String(localized: "appearance.icon.name.tag", defaultValue: "Tag", table: "Localizable", bundle: LorvexL10n.bundle)
    case "bolt":
      return String(localized: "appearance.icon.name.bolt", defaultValue: "Lightning", table: "Localizable", bundle: LorvexL10n.bundle)
    case "heart":
      return String(localized: "appearance.icon.name.heart", defaultValue: "Heart", table: "Localizable", bundle: LorvexL10n.bundle)
    case "leaf":
      return String(localized: "appearance.icon.name.leaf", defaultValue: "Leaf", table: "Localizable", bundle: LorvexL10n.bundle)
    case "flame":
      return String(localized: "appearance.icon.name.flame", defaultValue: "Flame", table: "Localizable", bundle: LorvexL10n.bundle)
    case "drop":
      return String(localized: "appearance.icon.name.drop", defaultValue: "Water", table: "Localizable", bundle: LorvexL10n.bundle)
    case "moon":
      return String(localized: "appearance.icon.name.moon", defaultValue: "Moon", table: "Localizable", bundle: LorvexL10n.bundle)
    case "moon.stars":
      return String(localized: "appearance.icon.name.moon.stars", defaultValue: "Moon and stars", table: "Localizable", bundle: LorvexL10n.bundle)
    case "sun.max":
      return String(localized: "appearance.icon.name.sun.max", defaultValue: "Sun", table: "Localizable", bundle: LorvexL10n.bundle)
    case "sun.haze":
      return String(localized: "appearance.icon.name.sun.haze", defaultValue: "Hazy sun", table: "Localizable", bundle: LorvexL10n.bundle)
    case "cloud":
      return String(localized: "appearance.icon.name.cloud", defaultValue: "Cloud", table: "Localizable", bundle: LorvexL10n.bundle)
    case "snowflake":
      return String(localized: "appearance.icon.name.snowflake", defaultValue: "Snowflake", table: "Localizable", bundle: LorvexL10n.bundle)
    case "sparkles":
      return String(localized: "appearance.icon.name.sparkles", defaultValue: "Sparkles", table: "Localizable", bundle: LorvexL10n.bundle)
    case "lightbulb":
      return String(localized: "appearance.icon.name.lightbulb", defaultValue: "Idea", table: "Localizable", bundle: LorvexL10n.bundle)
    case "target":
      return String(localized: "appearance.icon.name.target", defaultValue: "Target", table: "Localizable", bundle: LorvexL10n.bundle)
    case "trophy":
      return String(localized: "appearance.icon.name.trophy", defaultValue: "Trophy", table: "Localizable", bundle: LorvexL10n.bundle)
    case "rosette":
      return String(localized: "appearance.icon.name.rosette", defaultValue: "Rosette", table: "Localizable", bundle: LorvexL10n.bundle)
    case "pencil":
      return String(localized: "appearance.icon.name.pencil", defaultValue: "Pencil", table: "Localizable", bundle: LorvexL10n.bundle)
    case "book":
      return String(localized: "appearance.icon.name.book", defaultValue: "Book", table: "Localizable", bundle: LorvexL10n.bundle)
    case "books.vertical":
      return String(localized: "appearance.icon.name.books.vertical", defaultValue: "Books", table: "Localizable", bundle: LorvexL10n.bundle)
    case "doc.text":
      return String(localized: "appearance.icon.name.doc.text", defaultValue: "Document", table: "Localizable", bundle: LorvexL10n.bundle)
    case "newspaper":
      return String(localized: "appearance.icon.name.newspaper", defaultValue: "Newspaper", table: "Localizable", bundle: LorvexL10n.bundle)
    case "bookmark":
      return String(localized: "appearance.icon.name.bookmark", defaultValue: "Bookmark", table: "Localizable", bundle: LorvexL10n.bundle)
    case "paperclip":
      return String(localized: "appearance.icon.name.paperclip", defaultValue: "Paperclip", table: "Localizable", bundle: LorvexL10n.bundle)
    case "folder":
      return String(localized: "appearance.icon.name.folder", defaultValue: "Folder", table: "Localizable", bundle: LorvexL10n.bundle)
    case "tray":
      return String(localized: "appearance.icon.name.tray", defaultValue: "Inbox", table: "Localizable", bundle: LorvexL10n.bundle)
    case "archivebox":
      return String(localized: "appearance.icon.name.archivebox", defaultValue: "Archive", table: "Localizable", bundle: LorvexL10n.bundle)
    case "calendar":
      return String(localized: "appearance.icon.name.calendar", defaultValue: "Calendar", table: "Localizable", bundle: LorvexL10n.bundle)
    case "calendar.badge.clock":
      return String(localized: "appearance.icon.name.calendar.badge.clock", defaultValue: "Appointment", table: "Localizable", bundle: LorvexL10n.bundle)
    case "clock":
      return String(localized: "appearance.icon.name.clock", defaultValue: "Clock", table: "Localizable", bundle: LorvexL10n.bundle)
    case "alarm":
      return String(localized: "appearance.icon.name.alarm", defaultValue: "Alarm", table: "Localizable", bundle: LorvexL10n.bundle)
    case "hourglass":
      return String(localized: "appearance.icon.name.hourglass", defaultValue: "Hourglass", table: "Localizable", bundle: LorvexL10n.bundle)
    case "timer":
      return String(localized: "appearance.icon.name.timer", defaultValue: "Timer", table: "Localizable", bundle: LorvexL10n.bundle)
    case "stopwatch":
      return String(localized: "appearance.icon.name.stopwatch", defaultValue: "Stopwatch", table: "Localizable", bundle: LorvexL10n.bundle)
    case "bell":
      return String(localized: "appearance.icon.name.bell", defaultValue: "Bell", table: "Localizable", bundle: LorvexL10n.bundle)
    case "bell.badge":
      return String(localized: "appearance.icon.name.bell.badge", defaultValue: "Notification", table: "Localizable", bundle: LorvexL10n.bundle)
    case "envelope":
      return String(localized: "appearance.icon.name.envelope", defaultValue: "Mail", table: "Localizable", bundle: LorvexL10n.bundle)
    case "phone":
      return String(localized: "appearance.icon.name.phone", defaultValue: "Phone", table: "Localizable", bundle: LorvexL10n.bundle)
    case "message":
      return String(localized: "appearance.icon.name.message", defaultValue: "Message", table: "Localizable", bundle: LorvexL10n.bundle)
    case "bubble.left.and.bubble.right":
      return String(localized: "appearance.icon.name.bubble.left.and.bubble.right", defaultValue: "Conversation", table: "Localizable", bundle: LorvexL10n.bundle)
    case "video":
      return String(localized: "appearance.icon.name.video", defaultValue: "Video", table: "Localizable", bundle: LorvexL10n.bundle)
    case "person.2":
      return String(localized: "appearance.icon.name.person.2", defaultValue: "People", table: "Localizable", bundle: LorvexL10n.bundle)
    case "hand.raised":
      return String(localized: "appearance.icon.name.hand.raised", defaultValue: "Raised hand", table: "Localizable", bundle: LorvexL10n.bundle)
    case "figure.run":
      return String(localized: "appearance.icon.name.figure.run", defaultValue: "Running", table: "Localizable", bundle: LorvexL10n.bundle)
    case "figure.walk":
      return String(localized: "appearance.icon.name.figure.walk", defaultValue: "Walking", table: "Localizable", bundle: LorvexL10n.bundle)
    case "figure.hiking":
      return String(localized: "appearance.icon.name.figure.hiking", defaultValue: "Hiking", table: "Localizable", bundle: LorvexL10n.bundle)
    case "figure.cooldown":
      return String(localized: "appearance.icon.name.figure.cooldown", defaultValue: "Stretching", table: "Localizable", bundle: LorvexL10n.bundle)
    case "bicycle":
      return String(localized: "appearance.icon.name.bicycle", defaultValue: "Bicycle", table: "Localizable", bundle: LorvexL10n.bundle)
    case "dumbbell":
      return String(localized: "appearance.icon.name.dumbbell", defaultValue: "Workout", table: "Localizable", bundle: LorvexL10n.bundle)
    case "sportscourt":
      return String(localized: "appearance.icon.name.sportscourt", defaultValue: "Sports court", table: "Localizable", bundle: LorvexL10n.bundle)
    case "bed.double":
      return String(localized: "appearance.icon.name.bed.double", defaultValue: "Sleep", table: "Localizable", bundle: LorvexL10n.bundle)
    case "pills":
      return String(localized: "appearance.icon.name.pills", defaultValue: "Medication", table: "Localizable", bundle: LorvexL10n.bundle)
    case "cross.case":
      return String(localized: "appearance.icon.name.cross.case", defaultValue: "First aid", table: "Localizable", bundle: LorvexL10n.bundle)
    case "cross":
      return String(localized: "appearance.icon.name.cross", defaultValue: "Medical cross", table: "Localizable", bundle: LorvexL10n.bundle)
    case "stethoscope":
      return String(localized: "appearance.icon.name.stethoscope", defaultValue: "Stethoscope", table: "Localizable", bundle: LorvexL10n.bundle)
    case "lungs":
      return String(localized: "appearance.icon.name.lungs", defaultValue: "Lungs", table: "Localizable", bundle: LorvexL10n.bundle)
    case "brain.head.profile":
      return String(localized: "appearance.icon.name.brain.head.profile", defaultValue: "Mind", table: "Localizable", bundle: LorvexL10n.bundle)
    case "eye":
      return String(localized: "appearance.icon.name.eye", defaultValue: "Eye", table: "Localizable", bundle: LorvexL10n.bundle)
    case "fork.knife":
      return String(localized: "appearance.icon.name.fork.knife", defaultValue: "Dining", table: "Localizable", bundle: LorvexL10n.bundle)
    case "cup.and.saucer":
      return String(localized: "appearance.icon.name.cup.and.saucer", defaultValue: "Coffee", table: "Localizable", bundle: LorvexL10n.bundle)
    case "wineglass":
      return String(localized: "appearance.icon.name.wineglass", defaultValue: "Wine glass", table: "Localizable", bundle: LorvexL10n.bundle)
    case "carrot":
      return String(localized: "appearance.icon.name.carrot", defaultValue: "Carrot", table: "Localizable", bundle: LorvexL10n.bundle)
    case "house":
      return String(localized: "appearance.icon.name.house", defaultValue: "Home", table: "Localizable", bundle: LorvexL10n.bundle)
    case "cart":
      return String(localized: "appearance.icon.name.cart", defaultValue: "Cart", table: "Localizable", bundle: LorvexL10n.bundle)
    case "bag":
      return String(localized: "appearance.icon.name.bag", defaultValue: "Shopping bag", table: "Localizable", bundle: LorvexL10n.bundle)
    case "shippingbox":
      return String(localized: "appearance.icon.name.shippingbox", defaultValue: "Package", table: "Localizable", bundle: LorvexL10n.bundle)
    case "gift":
      return String(localized: "appearance.icon.name.gift", defaultValue: "Gift", table: "Localizable", bundle: LorvexL10n.bundle)
    case "pawprint":
      return String(localized: "appearance.icon.name.pawprint", defaultValue: "Paw print", table: "Localizable", bundle: LorvexL10n.bundle)
    case "camera":
      return String(localized: "appearance.icon.name.camera", defaultValue: "Camera", table: "Localizable", bundle: LorvexL10n.bundle)
    case "film":
      return String(localized: "appearance.icon.name.film", defaultValue: "Film", table: "Localizable", bundle: LorvexL10n.bundle)
    case "gamecontroller":
      return String(localized: "appearance.icon.name.gamecontroller", defaultValue: "Games", table: "Localizable", bundle: LorvexL10n.bundle)
    case "headphones":
      return String(localized: "appearance.icon.name.headphones", defaultValue: "Headphones", table: "Localizable", bundle: LorvexL10n.bundle)
    case "music.note":
      return String(localized: "appearance.icon.name.music.note", defaultValue: "Music", table: "Localizable", bundle: LorvexL10n.bundle)
    case "guitars":
      return String(localized: "appearance.icon.name.guitars", defaultValue: "Guitars", table: "Localizable", bundle: LorvexL10n.bundle)
    case "theatermasks":
      return String(localized: "appearance.icon.name.theatermasks", defaultValue: "Theater masks", table: "Localizable", bundle: LorvexL10n.bundle)
    case "puzzlepiece":
      return String(localized: "appearance.icon.name.puzzlepiece", defaultValue: "Puzzle piece", table: "Localizable", bundle: LorvexL10n.bundle)
    case "paintbrush":
      return String(localized: "appearance.icon.name.paintbrush", defaultValue: "Paintbrush", table: "Localizable", bundle: LorvexL10n.bundle)
    case "hammer":
      return String(localized: "appearance.icon.name.hammer", defaultValue: "Hammer", table: "Localizable", bundle: LorvexL10n.bundle)
    case "wrench.and.screwdriver":
      return String(localized: "appearance.icon.name.wrench.and.screwdriver", defaultValue: "Tools", table: "Localizable", bundle: LorvexL10n.bundle)
    case "gearshape":
      return String(localized: "appearance.icon.name.gearshape", defaultValue: "Gear", table: "Localizable", bundle: LorvexL10n.bundle)
    case "key":
      return String(localized: "appearance.icon.name.key", defaultValue: "Key", table: "Localizable", bundle: LorvexL10n.bundle)
    case "wifi":
      return String(localized: "appearance.icon.name.wifi", defaultValue: "Wi-Fi", table: "Localizable", bundle: LorvexL10n.bundle)
    case "briefcase":
      return String(localized: "appearance.icon.name.briefcase", defaultValue: "Briefcase", table: "Localizable", bundle: LorvexL10n.bundle)
    case "laptopcomputer":
      return String(localized: "appearance.icon.name.laptopcomputer", defaultValue: "Laptop", table: "Localizable", bundle: LorvexL10n.bundle)
    case "terminal":
      return String(localized: "appearance.icon.name.terminal", defaultValue: "Terminal", table: "Localizable", bundle: LorvexL10n.bundle)
    case "globe":
      return String(localized: "appearance.icon.name.globe", defaultValue: "Globe", table: "Localizable", bundle: LorvexL10n.bundle)
    case "map":
      return String(localized: "appearance.icon.name.map", defaultValue: "Map", table: "Localizable", bundle: LorvexL10n.bundle)
    case "mountain.2":
      return String(localized: "appearance.icon.name.mountain.2", defaultValue: "Mountains", table: "Localizable", bundle: LorvexL10n.bundle)
    case "umbrella":
      return String(localized: "appearance.icon.name.umbrella", defaultValue: "Umbrella", table: "Localizable", bundle: LorvexL10n.bundle)
    case "thermometer":
      return String(localized: "appearance.icon.name.thermometer", defaultValue: "Thermometer", table: "Localizable", bundle: LorvexL10n.bundle)
    case "airplane":
      return String(localized: "appearance.icon.name.airplane", defaultValue: "Airplane", table: "Localizable", bundle: LorvexL10n.bundle)
    case "graduationcap":
      return String(localized: "appearance.icon.name.graduationcap", defaultValue: "Graduation", table: "Localizable", bundle: LorvexL10n.bundle)
    case "dollarsign.circle":
      return String(localized: "appearance.icon.name.dollarsign.circle", defaultValue: "Money", table: "Localizable", bundle: LorvexL10n.bundle)
    case "creditcard":
      return String(localized: "appearance.icon.name.creditcard", defaultValue: "Credit card", table: "Localizable", bundle: LorvexL10n.bundle)
    case "banknote":
      return String(localized: "appearance.icon.name.banknote", defaultValue: "Banknote", table: "Localizable", bundle: LorvexL10n.bundle)
    case "chart.bar":
      return String(localized: "appearance.icon.name.chart.bar", defaultValue: "Bar chart", table: "Localizable", bundle: LorvexL10n.bundle)
    case "chart.pie":
      return String(localized: "appearance.icon.name.chart.pie", defaultValue: "Pie chart", table: "Localizable", bundle: LorvexL10n.bundle)
    case "chart.line.uptrend.xyaxis":
      return String(localized: "appearance.icon.name.chart.line.uptrend.xyaxis", defaultValue: "Growth chart", table: "Localizable", bundle: LorvexL10n.bundle)
    case "repeat":
      return String(localized: "appearance.icon.name.repeat", defaultValue: "Repeat", table: "Localizable", bundle: LorvexL10n.bundle)
    case "figure.mind.and.body":
      return String(localized: "appearance.icon.name.figure.mind.and.body", defaultValue: "Mindfulness", table: "Localizable", bundle: LorvexL10n.bundle)
    default: return nil
    }
  }

  /// Space-separated words, in the user's language, a person might type to find
  /// `symbol`, or nil when the picker has none for it. Shown nowhere; the search
  /// field matches against them.
  static func keywords(for symbol: String) -> String? {
    switch outlineName(of: symbol) {
    case "list.bullet":
      return String(localized: "appearance.icon.keywords.list.bullet", defaultValue: "bullets items outline todo", table: "Localizable", bundle: LorvexL10n.bundle)
    case "checklist":
      return String(localized: "appearance.icon.keywords.checklist", defaultValue: "tasks todo checkbox done", table: "Localizable", bundle: LorvexL10n.bundle)
    case "checkmark.seal":
      return String(localized: "appearance.icon.keywords.checkmark.seal", defaultValue: "verified quality badge certified", table: "Localizable", bundle: LorvexL10n.bundle)
    case "star":
      return String(localized: "appearance.icon.keywords.star", defaultValue: "favorite important rating", table: "Localizable", bundle: LorvexL10n.bundle)
    case "flag":
      return String(localized: "appearance.icon.keywords.flag", defaultValue: "milestone marker report", table: "Localizable", bundle: LorvexL10n.bundle)
    case "flag.checkered":
      return String(localized: "appearance.icon.keywords.flag.checkered", defaultValue: "race goal finish deadline", table: "Localizable", bundle: LorvexL10n.bundle)
    case "tag":
      return String(localized: "appearance.icon.keywords.tag", defaultValue: "label price category", table: "Localizable", bundle: LorvexL10n.bundle)
    case "bolt":
      return String(localized: "appearance.icon.keywords.bolt", defaultValue: "energy power fast electric", table: "Localizable", bundle: LorvexL10n.bundle)
    case "heart":
      return String(localized: "appearance.icon.keywords.heart", defaultValue: "love favorite health care", table: "Localizable", bundle: LorvexL10n.bundle)
    case "leaf":
      return String(localized: "appearance.icon.keywords.leaf", defaultValue: "plant nature eco green", table: "Localizable", bundle: LorvexL10n.bundle)
    case "flame":
      return String(localized: "appearance.icon.keywords.flame", defaultValue: "fire streak hot burn", table: "Localizable", bundle: LorvexL10n.bundle)
    case "drop":
      return String(localized: "appearance.icon.keywords.drop", defaultValue: "drop hydration liquid rain", table: "Localizable", bundle: LorvexL10n.bundle)
    case "moon":
      return String(localized: "appearance.icon.keywords.moon", defaultValue: "night sleep evening dark", table: "Localizable", bundle: LorvexL10n.bundle)
    case "moon.stars":
      return String(localized: "appearance.icon.keywords.moon.stars", defaultValue: "night sleep bedtime", table: "Localizable", bundle: LorvexL10n.bundle)
    case "sun.max":
      return String(localized: "appearance.icon.keywords.sun.max", defaultValue: "day morning sunny summer", table: "Localizable", bundle: LorvexL10n.bundle)
    case "sun.haze":
      return String(localized: "appearance.icon.keywords.sun.haze", defaultValue: "sunrise sunset morning weather", table: "Localizable", bundle: LorvexL10n.bundle)
    case "cloud":
      return String(localized: "appearance.icon.keywords.cloud", defaultValue: "weather sky storage", table: "Localizable", bundle: LorvexL10n.bundle)
    case "snowflake":
      return String(localized: "appearance.icon.keywords.snowflake", defaultValue: "winter cold snow ice", table: "Localizable", bundle: LorvexL10n.bundle)
    case "sparkles":
      return String(localized: "appearance.icon.keywords.sparkles", defaultValue: "magic clean new shine", table: "Localizable", bundle: LorvexL10n.bundle)
    case "lightbulb":
      return String(localized: "appearance.icon.keywords.lightbulb", defaultValue: "light bulb inspiration brainstorm", table: "Localizable", bundle: LorvexL10n.bundle)
    case "target":
      return String(localized: "appearance.icon.keywords.target", defaultValue: "goal aim focus bullseye", table: "Localizable", bundle: LorvexL10n.bundle)
    case "trophy":
      return String(localized: "appearance.icon.keywords.trophy", defaultValue: "win award achievement prize", table: "Localizable", bundle: LorvexL10n.bundle)
    case "rosette":
      return String(localized: "appearance.icon.keywords.rosette", defaultValue: "award ribbon badge prize", table: "Localizable", bundle: LorvexL10n.bundle)
    case "pencil":
      return String(localized: "appearance.icon.keywords.pencil", defaultValue: "write edit draw note", table: "Localizable", bundle: LorvexL10n.bundle)
    case "book":
      return String(localized: "appearance.icon.keywords.book", defaultValue: "read reading study library", table: "Localizable", bundle: LorvexL10n.bundle)
    case "books.vertical":
      return String(localized: "appearance.icon.keywords.books.vertical", defaultValue: "library reading study shelf", table: "Localizable", bundle: LorvexL10n.bundle)
    case "doc.text":
      return String(localized: "appearance.icon.keywords.doc.text", defaultValue: "file paper text report", table: "Localizable", bundle: LorvexL10n.bundle)
    case "newspaper":
      return String(localized: "appearance.icon.keywords.newspaper", defaultValue: "news press article", table: "Localizable", bundle: LorvexL10n.bundle)
    case "bookmark":
      return String(localized: "appearance.icon.keywords.bookmark", defaultValue: "save reading marker", table: "Localizable", bundle: LorvexL10n.bundle)
    case "paperclip":
      return String(localized: "appearance.icon.keywords.paperclip", defaultValue: "attachment clip office", table: "Localizable", bundle: LorvexL10n.bundle)
    case "folder":
      return String(localized: "appearance.icon.keywords.folder", defaultValue: "files project organize", table: "Localizable", bundle: LorvexL10n.bundle)
    case "tray":
      return String(localized: "appearance.icon.keywords.tray", defaultValue: "tray in box", table: "Localizable", bundle: LorvexL10n.bundle)
    case "archivebox":
      return String(localized: "appearance.icon.keywords.archivebox", defaultValue: "storage box old", table: "Localizable", bundle: LorvexL10n.bundle)
    case "calendar":
      return String(localized: "appearance.icon.keywords.calendar", defaultValue: "date schedule day planner", table: "Localizable", bundle: LorvexL10n.bundle)
    case "calendar.badge.clock":
      return String(localized: "appearance.icon.keywords.calendar.badge.clock", defaultValue: "calendar schedule event time", table: "Localizable", bundle: LorvexL10n.bundle)
    case "clock":
      return String(localized: "appearance.icon.keywords.clock", defaultValue: "time hour schedule", table: "Localizable", bundle: LorvexL10n.bundle)
    case "alarm":
      return String(localized: "appearance.icon.keywords.alarm", defaultValue: "wake up clock reminder", table: "Localizable", bundle: LorvexL10n.bundle)
    case "hourglass":
      return String(localized: "appearance.icon.keywords.hourglass", defaultValue: "time wait sand", table: "Localizable", bundle: LorvexL10n.bundle)
    case "timer":
      return String(localized: "appearance.icon.keywords.timer", defaultValue: "countdown time focus", table: "Localizable", bundle: LorvexL10n.bundle)
    case "stopwatch":
      return String(localized: "appearance.icon.keywords.stopwatch", defaultValue: "time race speed", table: "Localizable", bundle: LorvexL10n.bundle)
    case "bell":
      return String(localized: "appearance.icon.keywords.bell", defaultValue: "notification reminder alert", table: "Localizable", bundle: LorvexL10n.bundle)
    case "bell.badge":
      return String(localized: "appearance.icon.keywords.bell.badge", defaultValue: "bell alert reminder badge", table: "Localizable", bundle: LorvexL10n.bundle)
    case "envelope":
      return String(localized: "appearance.icon.keywords.envelope", defaultValue: "email letter message", table: "Localizable", bundle: LorvexL10n.bundle)
    case "phone":
      return String(localized: "appearance.icon.keywords.phone", defaultValue: "call telephone", table: "Localizable", bundle: LorvexL10n.bundle)
    case "message":
      return String(localized: "appearance.icon.keywords.message", defaultValue: "chat text sms", table: "Localizable", bundle: LorvexL10n.bundle)
    case "bubble.left.and.bubble.right":
      return String(localized: "appearance.icon.keywords.bubble.left.and.bubble.right", defaultValue: "chat talk discuss", table: "Localizable", bundle: LorvexL10n.bundle)
    case "video":
      return String(localized: "appearance.icon.keywords.video", defaultValue: "camera call film meeting", table: "Localizable", bundle: LorvexL10n.bundle)
    case "person.2":
      return String(localized: "appearance.icon.keywords.person.2", defaultValue: "friends team family group", table: "Localizable", bundle: LorvexL10n.bundle)
    case "hand.raised":
      return String(localized: "appearance.icon.keywords.hand.raised", defaultValue: "stop wave question", table: "Localizable", bundle: LorvexL10n.bundle)
    case "figure.run":
      return String(localized: "appearance.icon.keywords.figure.run", defaultValue: "run jog exercise fitness cardio", table: "Localizable", bundle: LorvexL10n.bundle)
    case "figure.walk":
      return String(localized: "appearance.icon.keywords.figure.walk", defaultValue: "walk steps stroll", table: "Localizable", bundle: LorvexL10n.bundle)
    case "figure.hiking":
      return String(localized: "appearance.icon.keywords.figure.hiking", defaultValue: "hike trail outdoors trek", table: "Localizable", bundle: LorvexL10n.bundle)
    case "figure.cooldown":
      return String(localized: "appearance.icon.keywords.figure.cooldown", defaultValue: "cooldown stretch yoga flexibility", table: "Localizable", bundle: LorvexL10n.bundle)
    case "bicycle":
      return String(localized: "appearance.icon.keywords.bicycle", defaultValue: "bike cycling ride", table: "Localizable", bundle: LorvexL10n.bundle)
    case "dumbbell":
      return String(localized: "appearance.icon.keywords.dumbbell", defaultValue: "gym weights strength exercise", table: "Localizable", bundle: LorvexL10n.bundle)
    case "sportscourt":
      return String(localized: "appearance.icon.keywords.sportscourt", defaultValue: "sport tennis basketball game", table: "Localizable", bundle: LorvexL10n.bundle)
    case "bed.double":
      return String(localized: "appearance.icon.keywords.bed.double", defaultValue: "bed rest bedroom", table: "Localizable", bundle: LorvexL10n.bundle)
    case "pills":
      return String(localized: "appearance.icon.keywords.pills", defaultValue: "pills medicine vitamins health", table: "Localizable", bundle: LorvexL10n.bundle)
    case "cross.case":
      return String(localized: "appearance.icon.keywords.cross.case", defaultValue: "medical doctor health kit", table: "Localizable", bundle: LorvexL10n.bundle)
    case "cross":
      return String(localized: "appearance.icon.keywords.cross", defaultValue: "health hospital doctor", table: "Localizable", bundle: LorvexL10n.bundle)
    case "stethoscope":
      return String(localized: "appearance.icon.keywords.stethoscope", defaultValue: "doctor health checkup medical", table: "Localizable", bundle: LorvexL10n.bundle)
    case "lungs":
      return String(localized: "appearance.icon.keywords.lungs", defaultValue: "breathing health breath", table: "Localizable", bundle: LorvexL10n.bundle)
    case "brain.head.profile":
      return String(localized: "appearance.icon.keywords.brain.head.profile", defaultValue: "brain thinking mental psychology", table: "Localizable", bundle: LorvexL10n.bundle)
    case "eye":
      return String(localized: "appearance.icon.keywords.eye", defaultValue: "look vision watch", table: "Localizable", bundle: LorvexL10n.bundle)
    case "fork.knife":
      return String(localized: "appearance.icon.keywords.fork.knife", defaultValue: "food meal eat restaurant", table: "Localizable", bundle: LorvexL10n.bundle)
    case "cup.and.saucer":
      return String(localized: "appearance.icon.keywords.cup.and.saucer", defaultValue: "tea drink cafe", table: "Localizable", bundle: LorvexL10n.bundle)
    case "wineglass":
      return String(localized: "appearance.icon.keywords.wineglass", defaultValue: "drink wine party", table: "Localizable", bundle: LorvexL10n.bundle)
    case "carrot":
      return String(localized: "appearance.icon.keywords.carrot", defaultValue: "vegetables food diet groceries", table: "Localizable", bundle: LorvexL10n.bundle)
    case "house":
      return String(localized: "appearance.icon.keywords.house", defaultValue: "house chores family", table: "Localizable", bundle: LorvexL10n.bundle)
    case "cart":
      return String(localized: "appearance.icon.keywords.cart", defaultValue: "shop groceries buy store", table: "Localizable", bundle: LorvexL10n.bundle)
    case "bag":
      return String(localized: "appearance.icon.keywords.bag", defaultValue: "shop buy purchase store", table: "Localizable", bundle: LorvexL10n.bundle)
    case "shippingbox":
      return String(localized: "appearance.icon.keywords.shippingbox", defaultValue: "delivery parcel shipping box", table: "Localizable", bundle: LorvexL10n.bundle)
    case "gift":
      return String(localized: "appearance.icon.keywords.gift", defaultValue: "present birthday holiday", table: "Localizable", bundle: LorvexL10n.bundle)
    case "pawprint":
      return String(localized: "appearance.icon.keywords.pawprint", defaultValue: "pet dog cat animal", table: "Localizable", bundle: LorvexL10n.bundle)
    case "camera":
      return String(localized: "appearance.icon.keywords.camera", defaultValue: "photo picture photography", table: "Localizable", bundle: LorvexL10n.bundle)
    case "film":
      return String(localized: "appearance.icon.keywords.film", defaultValue: "movie cinema video", table: "Localizable", bundle: LorvexL10n.bundle)
    case "gamecontroller":
      return String(localized: "appearance.icon.keywords.gamecontroller", defaultValue: "controller gaming play", table: "Localizable", bundle: LorvexL10n.bundle)
    case "headphones":
      return String(localized: "appearance.icon.keywords.headphones", defaultValue: "music podcast listen audio", table: "Localizable", bundle: LorvexL10n.bundle)
    case "music.note":
      return String(localized: "appearance.icon.keywords.music.note", defaultValue: "song note practice listen", table: "Localizable", bundle: LorvexL10n.bundle)
    case "guitars":
      return String(localized: "appearance.icon.keywords.guitars", defaultValue: "music instrument band", table: "Localizable", bundle: LorvexL10n.bundle)
    case "theatermasks":
      return String(localized: "appearance.icon.keywords.theatermasks", defaultValue: "theatre drama show arts", table: "Localizable", bundle: LorvexL10n.bundle)
    case "puzzlepiece":
      return String(localized: "appearance.icon.keywords.puzzlepiece", defaultValue: "puzzle plugin hobby", table: "Localizable", bundle: LorvexL10n.bundle)
    case "paintbrush":
      return String(localized: "appearance.icon.keywords.paintbrush", defaultValue: "art paint draw creative", table: "Localizable", bundle: LorvexL10n.bundle)
    case "hammer":
      return String(localized: "appearance.icon.keywords.hammer", defaultValue: "build repair diy fix", table: "Localizable", bundle: LorvexL10n.bundle)
    case "wrench.and.screwdriver":
      return String(localized: "appearance.icon.keywords.wrench.and.screwdriver", defaultValue: "repair maintenance fix build", table: "Localizable", bundle: LorvexL10n.bundle)
    case "gearshape":
      return String(localized: "appearance.icon.keywords.gearshape", defaultValue: "settings maintenance system", table: "Localizable", bundle: LorvexL10n.bundle)
    case "key":
      return String(localized: "appearance.icon.keywords.key", defaultValue: "password access keys", table: "Localizable", bundle: LorvexL10n.bundle)
    case "wifi":
      return String(localized: "appearance.icon.keywords.wifi", defaultValue: "internet network wireless", table: "Localizable", bundle: LorvexL10n.bundle)
    case "briefcase":
      return String(localized: "appearance.icon.keywords.briefcase", defaultValue: "work job business office", table: "Localizable", bundle: LorvexL10n.bundle)
    case "laptopcomputer":
      return String(localized: "appearance.icon.keywords.laptopcomputer", defaultValue: "computer work coding", table: "Localizable", bundle: LorvexL10n.bundle)
    case "terminal":
      return String(localized: "appearance.icon.keywords.terminal", defaultValue: "code programming command", table: "Localizable", bundle: LorvexL10n.bundle)
    case "globe":
      return String(localized: "appearance.icon.keywords.globe", defaultValue: "world travel language web", table: "Localizable", bundle: LorvexL10n.bundle)
    case "map":
      return String(localized: "appearance.icon.keywords.map", defaultValue: "travel navigation places", table: "Localizable", bundle: LorvexL10n.bundle)
    case "mountain.2":
      return String(localized: "appearance.icon.keywords.mountain.2", defaultValue: "hiking outdoors nature trip", table: "Localizable", bundle: LorvexL10n.bundle)
    case "umbrella":
      return String(localized: "appearance.icon.keywords.umbrella", defaultValue: "rain weather insurance", table: "Localizable", bundle: LorvexL10n.bundle)
    case "thermometer":
      return String(localized: "appearance.icon.keywords.thermometer", defaultValue: "temperature fever weather", table: "Localizable", bundle: LorvexL10n.bundle)
    case "airplane":
      return String(localized: "appearance.icon.keywords.airplane", defaultValue: "flight travel trip vacation", table: "Localizable", bundle: LorvexL10n.bundle)
    case "graduationcap":
      return String(localized: "appearance.icon.keywords.graduationcap", defaultValue: "school study university degree", table: "Localizable", bundle: LorvexL10n.bundle)
    case "dollarsign.circle":
      return String(localized: "appearance.icon.keywords.dollarsign.circle", defaultValue: "dollar cash finance budget", table: "Localizable", bundle: LorvexL10n.bundle)
    case "creditcard":
      return String(localized: "appearance.icon.keywords.creditcard", defaultValue: "payment bank bills", table: "Localizable", bundle: LorvexL10n.bundle)
    case "banknote":
      return String(localized: "appearance.icon.keywords.banknote", defaultValue: "cash money savings", table: "Localizable", bundle: LorvexL10n.bundle)
    case "chart.bar":
      return String(localized: "appearance.icon.keywords.chart.bar", defaultValue: "statistics data report", table: "Localizable", bundle: LorvexL10n.bundle)
    case "chart.pie":
      return String(localized: "appearance.icon.keywords.chart.pie", defaultValue: "statistics share budget", table: "Localizable", bundle: LorvexL10n.bundle)
    case "chart.line.uptrend.xyaxis":
      return String(localized: "appearance.icon.keywords.chart.line.uptrend.xyaxis", defaultValue: "progress trend stats", table: "Localizable", bundle: LorvexL10n.bundle)
    case "repeat":
      return String(localized: "appearance.icon.keywords.repeat", defaultValue: "loop routine again", table: "Localizable", bundle: LorvexL10n.bundle)
    case "figure.mind.and.body":
      return String(localized: "appearance.icon.keywords.figure.mind.and.body", defaultValue: "meditation yoga calm", table: "Localizable", bundle: LorvexL10n.bundle)
    default: return nil
    }
  }

  /// Whether `symbol` answers the search `query`: every word of the query must
  /// occur in the symbol's name, its keywords, or its SF Symbol name, ignoring
  /// case, accents, and letter variants. An empty query matches every symbol.
  static func matches(_ symbol: String, query: String) -> Bool {
    LorvexCatalogSearch.matches(query, fields: [name(for: symbol), keywords(for: symbol), symbol])
  }

  /// `symbol` without a trailing `.fill`, so a filled variant resolves to the
  /// entry of its outline symbol.
  private static func outlineName(of symbol: String) -> String {
    symbol.hasSuffix(".fill") ? String(symbol.dropLast(".fill".count)) : symbol
  }
}
