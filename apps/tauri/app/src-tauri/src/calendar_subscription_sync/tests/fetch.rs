use super::*;

// -----------------------------------------------------------------------
// Captive-portal body-sniff
// -----------------------------------------------------------------------

#[test]
fn captive_portal_body_detects_html_without_doctype() {
    assert!(looks_like_captive_portal_body(
        "<html><body>Please sign in to continue</body></html>"
    ));
}

#[test]
fn captive_portal_body_detects_doctype_prefix() {
    assert!(looks_like_captive_portal_body(
        "\n  <!DOCTYPE html>\n<html lang=\"en\">…"
    ));
}

#[test]
fn captive_portal_body_detects_json_gateway_payload() {
    // Enterprise gateways sometimes return {"action":"login","portal":"..."}
    // with Content-Type: application/json — the Content-Type gate above
    // misses it, so the body-sniff must catch "login" / "portal".
    assert!(looks_like_captive_portal_body(
        "{\"action\":\"login\",\"portal\":\"wifi.corp\"}"
    ));
}

#[test]
fn captive_portal_body_detects_location_header_style_body() {
    assert!(looks_like_captive_portal_body(
        "HTTP/1.1 302 Found\nLocation: https://captive.example.com/login\n\n"
    ));
}

#[test]
fn captive_portal_body_rejects_generic_non_calendar_text() {
    // A benign "wrong endpoint" text blob must NOT be classified
    // as a captive portal — it needs one of the marker substrings.
    assert!(!looks_like_captive_portal_body(
        "The calendar feed has moved to a new URL. Please update your subscription."
    ));
}

#[test]
fn captive_portal_body_rejects_empty_body() {
    assert!(!looks_like_captive_portal_body(""));
}
