use lorvex_domain::naming::EntityKind;

const fn entity_type_to_bus(kind: EntityKind) -> Option<crate::event_bus::Entity> {
    crate::event_bus::Entity::from_parsed_entity_kind(kind)
}

pub(crate) fn emit_data_changed_for_entity_types(entity_types: &[EntityKind]) {
    let mut emitted = std::collections::HashSet::new();
    // when sync apply (or a pending-inbox drain
    // unblock) writes a habit_completion row, the local
    // `best_streak_cache` in `commands::habit_queries` would otherwise
    // serve a 24h-stale value to the next Habits-view open — peer
    // writes never invalidated it because invalidation lived only on
    // the local Tauri write path. We don't have the affected
    // `habit_id` at this seam (the `entity_types` slice is the bare
    // EntityKind labels collected by upstream callers), so the safest
    // correct invalidation is a full cache clear: the cache is at
    // most one entry per active habit, repopulating is a single
    // O(active-window) scan per habit on next open, and dropping it
    // wholesale costs nothing measurable in the steady state.
    let mut clear_best_streak = false;
    for &kind in entity_types {
        if matches!(kind, EntityKind::HabitCompletion) {
            clear_best_streak = true;
        }
        if let Some(entity) = entity_type_to_bus(kind) {
            let key = std::mem::discriminant(&entity);
            if emitted.insert(key) {
                crate::event_bus::emit_data_changed(entity);
            }
        }
    }
    if clear_best_streak {
        crate::commands::habits::queries::clear_best_streak_cache();
    }
}
