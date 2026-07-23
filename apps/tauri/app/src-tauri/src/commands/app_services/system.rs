//! Cross-cutting Tauri IPC entry points that don't belong to any
//! single domain: the auto-update probe, the biometric-auth bridge,
//! and the explicit memory-lock hook. Sibling to the focus-session
//! machinery so the two concerns can grow independently.

#[tauri::command]
pub async fn check_for_update(app: tauri::AppHandle) -> Result<Option<String>, String> {
    use std::time::Duration;
    use tauri_plugin_updater::UpdaterExt;

    // cap the check at 20 s total. Without this,
    // `tauri_plugin_updater::check()` inherits reqwest's default
    // no-timeout and can hang on DNS-broken / captive-portal networks.
    match app
        .updater_builder()
        .timeout(Duration::from_secs(20))
        .configure_client(crate::proxy_env::apply_proxy_from_env_async)
        .build()
        .map_err(|error| crate::error::AppError::RemoteUpdateFailed(error.to_string()))?
        .check()
        .await
    {
        Ok(Some(update)) => Ok(Some(update.version)),
        Ok(None) => Ok(None),
        Err(tauri_plugin_updater::Error::ReleaseNotFound) => Ok(None),
        Err(tauri_plugin_updater::Error::Reqwest(ref req))
            if req.status().map(|s| s.as_u16() == 404).unwrap_or(false) =>
        {
            Ok(None)
        }
        Err(e) => Err(crate::error::AppError::RemoteUpdateFailed(e.to_string()).into()),
    }
}

/// #3648 — install the available update and relaunch the app. Paired
/// with the sidebar `UpdateBanner` "Install" affordance: the user has
/// already opted in via the confirm dialog, so this command downloads
/// the bundle, installs it, and (on success) relaunches the process so
/// the new binary takes over without the user having to find their
/// way back to the app.
#[tauri::command]
pub async fn install_update(app: tauri::AppHandle) -> Result<(), String> {
    use std::time::Duration;
    use tauri_plugin_updater::UpdaterExt;

    // Mirror the timeout / proxy plumbing of `check_for_update` so
    // the install path honors `HTTPS_PROXY` / `HTTP_PROXY` exactly
    // like the probe and never hangs on a captive-portal network.
    let updater = app
        .updater_builder()
        .timeout(Duration::from_secs(20))
        .configure_client(crate::proxy_env::apply_proxy_from_env_async)
        .build()
        .map_err(|error| crate::error::AppError::RemoteUpdateFailed(error.to_string()))?;

    let update = updater
        .check()
        .await
        .map_err(|error| crate::error::AppError::RemoteUpdateFailed(error.to_string()))?
        .ok_or_else(|| {
            crate::error::AppError::RemoteUpdateFailed("no update available".to_string())
        })?;

    update
        .download_and_install(|_chunk_len, _total_len| {}, || {})
        .await
        .map_err(|error| crate::error::AppError::RemoteUpdateFailed(error.to_string()))?;

    // `restart()` does not return; the call exits the current
    // process. Anything after it is unreachable.
    app.restart();
}

/// Prompt for biometric authentication. Delegates to `platform::biometrics`.
///
/// a successful biometric auth now flips the
/// process-wide [`crate::memory_lock`] state to `Unlocked` for the
/// default TTL. Memory commands consult this state at the IPC entry,
/// so a buggy or compromised renderer can no longer call them without
/// first invoking biometric auth — the lock is no longer purely
/// cosmetic.
#[tauri::command]
pub async fn authenticate_biometrics(reason: String) -> Result<bool, String> {
    let result = crate::platform::biometrics::authenticate(reason).await?;
    if result {
        crate::memory_lock::unlock_for_default_ttl();
    }
    Ok(result)
}
