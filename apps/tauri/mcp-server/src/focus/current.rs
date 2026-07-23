mod model;
mod reads;
mod writes;

#[cfg(test)]
mod tests;

pub(crate) use model::enrich_current_focus_row;
pub(crate) use reads::get_current_focus;
pub(crate) use writes::{
    add_to_current_focus, clear_current_focus, remove_from_current_focus, set_current_focus,
};
