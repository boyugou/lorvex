use super::*;

#[test]
fn english_default() {
    assert_eq!(
        action_title("en", NotificationActionString::Complete),
        "Complete"
    );
    assert_eq!(
        action_title("en", NotificationActionString::Snooze),
        "Remind Later"
    );
}

#[test]
fn simplified_chinese() {
    assert_eq!(
        action_title("zh", NotificationActionString::Complete),
        "完成"
    );
    assert_eq!(
        action_title("zh", NotificationActionString::Snooze),
        "稍后提醒"
    );
}

#[test]
fn traditional_chinese_uses_dedicated_entry() {
    assert_eq!(
        action_title("zh-Hant", NotificationActionString::Complete),
        "完成"
    );
    assert_eq!(
        action_title("zh-Hant", NotificationActionString::Snooze),
        "稍後提醒"
    );
}

#[test]
fn representative_supported_locales_are_localized() {
    assert_eq!(
        action_title("fr", NotificationActionString::Complete),
        "Terminer"
    );
    assert_eq!(
        action_title("de", NotificationActionString::Snooze),
        "Später erinnern"
    );
    assert_eq!(
        action_title("ja", NotificationActionString::Complete),
        "完了"
    );
    assert_eq!(
        action_title("ar", NotificationActionString::Snooze),
        "تأجيل"
    );
}

#[test]
fn every_frontend_locale_has_native_action_titles() {
    for locale in [
        "ar", "bn", "de", "el", "en", "es", "fa", "fr", "he", "hi", "id", "it", "ja", "ko", "ml",
        "mr", "ms", "nl", "pl", "pt", "ro", "ru", "ta", "te", "th", "tr", "uk", "ur", "vi", "zh",
        "zh-Hant",
    ] {
        assert!(
            lookup(locale, NotificationActionString::Complete).is_some(),
            "missing Complete title for {locale}"
        );
        assert!(
            lookup(locale, NotificationActionString::Snooze).is_some(),
            "missing Snooze title for {locale}"
        );
    }
}

#[test]
fn unknown_locale_falls_back_to_english() {
    assert_eq!(
        action_title("xx", NotificationActionString::Complete),
        "Complete"
    );
    assert_eq!(
        action_title("xx-YY", NotificationActionString::Snooze),
        "Remind Later"
    );
}
