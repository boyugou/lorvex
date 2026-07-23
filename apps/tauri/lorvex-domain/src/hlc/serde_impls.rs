//! `Display`, `Serialize`, and `Deserialize` impls for [`Hlc`]. The
//! canonical wire format is the same string the comparator and `Ord`
//! impls consume, so all three traits are kept together.

use std::fmt;

use serde::{Deserialize, Serialize};

use super::core::Hlc;

impl fmt::Display for Hlc {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{:013}_{:04}_{}",
            self.physical_ms, self.counter, self.device_suffix
        )
    }
}

impl Serialize for Hlc {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        // route through `Display` directly into
        // the serializer's writer via `collect_str`. The previous
        // `serialize_str(&self.to_string())` allocated a transient
        // `String` per serialize call (a hot path inside envelope
        // canonicalization); `collect_str` writes the formatted bytes
        // straight into the serializer with no intermediate heap
        // allocation.
        serializer.collect_str(self)
    }
}

impl<'de> Deserialize<'de> for Hlc {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let s = String::deserialize(deserializer)?;
        Hlc::parse(&s).map_err(serde::de::Error::custom)
    }
}
