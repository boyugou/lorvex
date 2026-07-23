mod guide_render;
mod guide_state;
mod severity;

pub(crate) use guide_render::{build_guide, guide_topic_to_str};
pub(crate) use guide_state::{auto_detect_guide_topic, guide_suggested_actions, GuideState};
pub(crate) use severity::severity_by_count;

#[cfg(test)]
mod tests;
