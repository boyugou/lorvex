//! Locale-aware titles for native notification action buttons.
//!
//! The macOS `UNNotificationCategory` binds action titles at category
//! registration time (not per-notification), and Windows toast XML embeds
//! action `content=` strings inline in each notification payload. Both
//! need a lightweight Rust-side translation map because the frontend
//! TypeScript locale tables are not reachable from the platform layer.
//!
//! **Scope:** Only a small handful of strings — Complete, Snooze. Full
//! locale coverage lives in the frontend catalogs. Keep this table aligned
//! with `notifications.actionComplete` and `notifications.actionRemindLater`
//! for every registered frontend locale; unknown future locales fall back
//! through their base language and then English.

/// Identifier for a locale-aware notification action string.
#[derive(Clone, Copy, Debug)]
pub enum NotificationActionString {
    /// "Complete" — mark the task as done.
    Complete,
    /// "Snooze" — re-remind in a short interval.
    Snooze,
}

/// Resolve the display title for a notification action button at the given
/// locale. Falls back to English on unknown locales.
pub fn action_title(locale: &str, which: NotificationActionString) -> &'static str {
    if let Some(s) = lookup(locale, which) {
        return s;
    }
    // Try base language (e.g. "zh-Hant" → "zh").
    if let Some(base) = locale.split('-').next() {
        if base != locale {
            if let Some(s) = lookup(base, which) {
                return s;
            }
        }
    }
    // English fallback.
    lookup("en", which).unwrap_or("?")
}

fn lookup(locale: &str, which: NotificationActionString) -> Option<&'static str> {
    Some(match (locale, which) {
        ("ar", NotificationActionString::Complete) => "إكمال",
        ("ar", NotificationActionString::Snooze) => "تأجيل",
        ("bn", NotificationActionString::Complete) => "সম্পন্ন",
        ("bn", NotificationActionString::Snooze) => "স্নুজ",
        ("de", NotificationActionString::Complete) => "Erledigt",
        ("de", NotificationActionString::Snooze) => "Später erinnern",
        ("el", NotificationActionString::Complete) => "Ολοκλήρωση",
        ("el", NotificationActionString::Snooze) => "Αναβολή",
        ("en", NotificationActionString::Complete) => "Complete",
        ("en", NotificationActionString::Snooze) => "Remind Later",
        ("es", NotificationActionString::Complete) => "Completar",
        ("es", NotificationActionString::Snooze) => "Posponer",
        ("fa", NotificationActionString::Complete) => "تکمیل",
        ("fa", NotificationActionString::Snooze) => "به‌تعویق",
        ("fr", NotificationActionString::Complete) => "Terminer",
        ("fr", NotificationActionString::Snooze) => "Reporter",
        ("he", NotificationActionString::Complete) => "השלם",
        ("he", NotificationActionString::Snooze) => "נדנד",
        ("hi", NotificationActionString::Complete) => "पूरा करें",
        ("hi", NotificationActionString::Snooze) => "बाद में याद दिलाएँ",
        ("id", NotificationActionString::Complete) => "Selesaikan",
        ("id", NotificationActionString::Snooze) => "Tunda",
        ("it", NotificationActionString::Complete) => "Completa",
        ("it", NotificationActionString::Snooze) => "Posticipa",
        ("ja", NotificationActionString::Complete) => "完了",
        ("ja", NotificationActionString::Snooze) => "後でリマインド",
        ("ko", NotificationActionString::Complete) => "완료",
        ("ko", NotificationActionString::Snooze) => "미루기",
        ("ml", NotificationActionString::Complete) => "പൂര്‍ത്തിയാക്കുക",
        ("ml", NotificationActionString::Snooze) => "സ്‌നൂസ്",
        ("mr", NotificationActionString::Complete) => "पूर्ण",
        ("mr", NotificationActionString::Snooze) => "स्नूझ",
        ("ms", NotificationActionString::Complete) => "Selesai",
        ("ms", NotificationActionString::Snooze) => "Tunda",
        ("nl", NotificationActionString::Complete) => "Voltooien",
        ("nl", NotificationActionString::Snooze) => "Sluimeren",
        ("pl", NotificationActionString::Complete) => "Ukończ",
        ("pl", NotificationActionString::Snooze) => "Odłóż",
        ("pt", NotificationActionString::Complete) => "Concluir",
        ("pt", NotificationActionString::Snooze) => "Adiar",
        ("ro", NotificationActionString::Complete) => "Finalizează",
        ("ro", NotificationActionString::Snooze) => "Amână",
        ("ru", NotificationActionString::Complete) => "Выполнить",
        ("ru", NotificationActionString::Snooze) => "Отложить",
        ("ta", NotificationActionString::Complete) => "முடி",
        ("ta", NotificationActionString::Snooze) => "ஒத்திவை",
        ("te", NotificationActionString::Complete) => "పూర్తి",
        ("te", NotificationActionString::Snooze) => "వాయిదా",
        ("th", NotificationActionString::Complete) => "ทำเสร็จ",
        ("th", NotificationActionString::Snooze) => "เลื่อน",
        ("tr", NotificationActionString::Complete) => "Tamamla",
        ("tr", NotificationActionString::Snooze) => "Ertele",
        ("uk", NotificationActionString::Complete) => "Виконати",
        ("uk", NotificationActionString::Snooze) => "Відкласти",
        ("ur", NotificationActionString::Complete) => "مکمل",
        ("ur", NotificationActionString::Snooze) => "ملتوی",
        ("vi", NotificationActionString::Complete) => "Hoàn thành",
        ("vi", NotificationActionString::Snooze) => "Tạm hoãn",
        ("zh-Hant", NotificationActionString::Complete) => "完成",
        ("zh-Hant", NotificationActionString::Snooze) => "稍後提醒",
        ("zh", NotificationActionString::Complete) => "完成",
        ("zh", NotificationActionString::Snooze) => "稍后提醒",
        _ => return None,
    })
}

#[cfg(test)]
mod tests;
