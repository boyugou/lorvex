use super::*;

#[test]
fn app_version_is_semver() {
    let parts: Vec<&str> = APP_VERSION.split('.').collect();
    assert_eq!(parts.len(), 3, "APP_VERSION must be semver");
    for part in &parts {
        part.parse::<u32>()
            .expect("each semver part must be numeric");
    }
}
