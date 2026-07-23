//! Three-state PATCH primitive for partial updates.
//!
//! `Patch<T>` replaces the historical `Option<Option<T>>` idiom that encoded
//! three update states with two layers of `Option` — a shape that compiles
//! but reads ambiguously, frequently nests as `Some(Some(x))` / `Some(None)`
//! / `None`, and offers no compiler hint that the outer/inner layers carry
//! different semantics.
//!
//! ```text
//!     Option<Option<T>>          Patch<T>
//!     -----------------          --------
//!     None              ───►     Patch::Unset      // field absent, leave as-is
//!     Some(None)        ───►     Patch::Clear      // explicit clear (JSON null)
//!     Some(Some(v))     ───►     Patch::Set(v)     // set to value
//! ```
//!
//! ## Wire format
//!
//! Custom `Deserialize` + `Serialize` impls preserve the canonical
//! three-state JSON shape:
//!
//! - missing key → `Patch::Unset`     (relies on the field's `#[serde(default)]`)
//! - `null`      → `Patch::Clear`
//! - any value   → `Patch::Set(value)`
//!
//! On the way out, `Patch::Unset` skips serialization entirely (use
//! `#[serde(skip_serializing_if = "Patch::is_unset")]` on the field),
//! `Patch::Clear` emits `null`, and `Patch::Set(v)` emits the inner value.
//!
//! ## JsonSchema
//!
//! When the `schemars` feature is enabled, `Patch<T>` exposes a
//! `JsonSchema` impl that mirrors the historical wire shape: the field is
//! `nullable: true` over `T`'s schema, so MCP tool consumers see the same
//! `Optional<T> | null` contract they always have.

use core::fmt;
use serde::{de::Visitor, Deserialize, Deserializer, Serialize, Serializer};

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub enum Patch<T> {
    /// Field is absent from the patch — leave the underlying value untouched.
    #[default]
    Unset,
    /// Field is explicitly cleared (wire form: JSON `null`).
    Clear,
    /// Field is set to a new value.
    Set(T),
}

impl<T> Patch<T> {
    /// Returns true if the patch is `Set` or `Clear` (i.e. the field was
    /// present in the patch).
    #[must_use]
    pub const fn is_set_or_clear(&self) -> bool {
        !matches!(self, Self::Unset)
    }

    /// Returns true if the patch is `Unset` (field absent).
    #[must_use]
    pub const fn is_unset(&self) -> bool {
        matches!(self, Self::Unset)
    }

    /// Returns true if the patch is `Clear` (explicit null).
    #[must_use]
    pub const fn is_clear(&self) -> bool {
        matches!(self, Self::Clear)
    }

    /// Returns true if the patch is `Set(_)`.
    #[must_use]
    pub const fn is_set(&self) -> bool {
        matches!(self, Self::Set(_))
    }

    /// View the inner value as a `Patch<&T>`.
    #[must_use]
    pub const fn as_ref(&self) -> Patch<&T> {
        match self {
            Self::Unset => Patch::Unset,
            Self::Clear => Patch::Clear,
            Self::Set(v) => Patch::Set(v),
        }
    }

    /// Map `Set(T) → Set(U)`; `Unset` and `Clear` pass through unchanged.
    #[must_use]
    pub fn map<U, F: FnOnce(T) -> U>(self, f: F) -> Patch<U> {
        match self {
            Self::Unset => Patch::Unset,
            Self::Clear => Patch::Clear,
            Self::Set(v) => Patch::Set(f(v)),
        }
    }

    /// Map `Set(T) → Result<Set(U), E>`; passes through `Unset` and `Clear`.
    pub fn try_map<U, E, F: FnOnce(T) -> Result<U, E>>(self, f: F) -> Result<Patch<U>, E> {
        match self {
            Self::Unset => Ok(Patch::Unset),
            Self::Clear => Ok(Patch::Clear),
            Self::Set(v) => Ok(Patch::Set(f(v)?)),
        }
    }

    /// Borrow the inner value, collapsing `Unset` and `Clear` to
    /// `None` and `Set(v)` to `Some(&v)`. Useful at SQL bind sites
    /// where the caller has already gated on `is_set_or_clear()` and
    /// just needs an `Option<&T>` to pass into rusqlite (which maps
    /// `None` to SQL NULL).
    #[must_use]
    pub const fn as_bind_value(&self) -> Option<&T> {
        match self {
            Self::Unset | Self::Clear => None,
            Self::Set(v) => Some(v),
        }
    }
}

impl<T> Patch<T>
where
    T: AsRef<str>,
{
    /// Convenience for borrowing the inner string slice when present.
    #[must_use]
    pub fn as_deref(&self) -> Patch<&str> {
        match self {
            Self::Unset => Patch::Unset,
            Self::Clear => Patch::Clear,
            Self::Set(v) => Patch::Set(v.as_ref()),
        }
    }
}

// -----------------------------------------------------------------------
// Serde
//
// Deserialize: we are only invoked when the key is present in the JSON
// (a missing key uses the field-level `#[serde(default)]` value, which
// is `Patch::Unset`). When invoked we map `null → Clear` and any other
// value → `Set(v)`.
//
// Serialize: `Unset` would normally emit `null` if a struct serializes
// it; consumers should pair `Patch<T>` fields with
// `#[serde(skip_serializing_if = "Patch::is_unset")]` to suppress the
// key entirely. We still emit `null` for `Unset` so the impl is valid
// in isolation; downstream tests prove the wire shape with the
// `skip_serializing_if` attribute applied.
// -----------------------------------------------------------------------

struct PatchVisitor<T>(core::marker::PhantomData<T>);

impl<'de, T> Visitor<'de> for PatchVisitor<T>
where
    T: Deserialize<'de>,
{
    type Value = Patch<T>;

    fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("a value or null for a Patch field")
    }

    fn visit_none<E>(self) -> Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
        // Rare: serde drivers that explicitly call visit_none for null.
        Ok(Patch::Clear)
    }

    fn visit_unit<E>(self) -> Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
        Ok(Patch::Clear)
    }

    fn visit_some<D>(self, deserializer: D) -> Result<Self::Value, D::Error>
    where
        D: Deserializer<'de>,
    {
        T::deserialize(deserializer).map(Patch::Set)
    }
}

impl<'de, T> Deserialize<'de> for Patch<T>
where
    T: Deserialize<'de>,
{
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        // The container deserializer has already decided that the key
        // exists. We then ask for an Option layer so `null` routes
        // through `visit_none`/`visit_unit` and any value through
        // `visit_some`.
        deserializer.deserialize_option(PatchVisitor::<T>(core::marker::PhantomData))
    }
}

impl<T> Serialize for Patch<T>
where
    T: Serialize,
{
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        match self {
            // When emitted (i.e. `skip_serializing_if` not applied), Unset
            // collapses to null — same wire shape as Clear. Pair with
            // `skip_serializing_if = "Patch::is_unset"` to suppress the key.
            Self::Unset | Self::Clear => serializer.serialize_none(),
            Self::Set(v) => serializer.serialize_some(v),
        }
    }
}

// -----------------------------------------------------------------------
// JsonSchema
//
// schemars 1.x — `nullable` is encoded via the type union { T | null }.
// We mirror what schemars does for `Option<T>`: an `anyOf` of the inner
// schema and a `Null` schema. That matches the MCP tool catalog's
// emitted shape for `Option<Option<T>>` (the outer Option is what
// schemars sees), so the wire-facing schema stays byte-identical
// across the typed-Patch migration.
// -----------------------------------------------------------------------

#[cfg(feature = "schemars")]
mod schemars_impl {
    use super::Patch;
    use schemars::{JsonSchema, Schema, SchemaGenerator};
    use std::borrow::Cow;

    impl<T: JsonSchema> JsonSchema for Patch<T> {
        fn schema_name() -> Cow<'static, str> {
            Cow::Owned(format!("Nullable_{}", T::schema_name()))
        }

        fn schema_id() -> Cow<'static, str> {
            Cow::Owned(format!("Patch<{}>", T::schema_id()))
        }

        fn json_schema(generator: &mut SchemaGenerator) -> Schema {
            // Mirror schemars 1.x `Option<T>` shape: anyOf [T, null].
            <Option<T>>::json_schema(generator)
        }

        fn inline_schema() -> bool {
            <Option<T>>::inline_schema()
        }
    }
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use serde::{Deserialize, Serialize};

    #[derive(Debug, Default, PartialEq, Serialize, Deserialize)]
    struct Holder {
        #[serde(default, skip_serializing_if = "Patch::is_unset")]
        body: Patch<String>,
        #[serde(default, skip_serializing_if = "Patch::is_unset")]
        count: Patch<u32>,
    }

    #[test]
    fn missing_key_deserializes_as_unset() {
        let h: Holder = serde_json::from_str("{}").unwrap();
        assert_eq!(h.body, Patch::Unset);
        assert_eq!(h.count, Patch::Unset);
    }

    #[test]
    fn null_deserializes_as_clear() {
        let h: Holder = serde_json::from_str(r#"{"body": null}"#).unwrap();
        assert_eq!(h.body, Patch::Clear);
        assert_eq!(h.count, Patch::Unset);
    }

    #[test]
    fn value_deserializes_as_set() {
        let h: Holder = serde_json::from_str(r#"{"body": "hello", "count": 7}"#).unwrap();
        assert_eq!(h.body, Patch::Set("hello".to_string()));
        assert_eq!(h.count, Patch::Set(7));
    }

    #[test]
    fn unset_skips_serialization() {
        let h = Holder {
            body: Patch::Unset,
            count: Patch::Unset,
        };
        assert_eq!(serde_json::to_string(&h).unwrap(), "{}");
    }

    #[test]
    fn clear_serializes_as_null() {
        let h = Holder {
            body: Patch::Clear,
            count: Patch::Unset,
        };
        assert_eq!(serde_json::to_string(&h).unwrap(), r#"{"body":null}"#);
    }

    #[test]
    fn set_serializes_as_value() {
        let h = Holder {
            body: Patch::Set("hello".to_string()),
            count: Patch::Set(7),
        };
        let s = serde_json::to_string(&h).unwrap();
        // Object-key order in serde_json follows struct field order, so
        // the output is deterministic here.
        assert_eq!(s, r#"{"body":"hello","count":7}"#);
    }

    #[test]
    fn round_trip_all_three_states() {
        let cases = [
            ("{}", Holder::default()),
            (
                r#"{"body":null}"#,
                Holder {
                    body: Patch::Clear,
                    count: Patch::Unset,
                },
            ),
            (
                r#"{"body":"x"}"#,
                Holder {
                    body: Patch::Set("x".to_string()),
                    count: Patch::Unset,
                },
            ),
        ];
        for (json, expected) in cases {
            let parsed: Holder = serde_json::from_str(json).unwrap();
            assert_eq!(parsed, expected, "deserialize: {json}");
            let reserialized = serde_json::to_string(&parsed).unwrap();
            assert_eq!(reserialized, json, "round-trip: {json}");
        }
    }

    #[test]
    fn map_transforms_set_only() {
        assert_eq!(Patch::<u32>::Unset.map(|v| v + 1), Patch::Unset);
        assert_eq!(Patch::<u32>::Clear.map(|v| v + 1), Patch::Clear);
        assert_eq!(Patch::Set(5_u32).map(|v| v + 1), Patch::Set(6));
    }

    #[test]
    fn as_ref_borrows_inner() {
        let p = Patch::Set("hi".to_string());
        match p.as_ref() {
            Patch::Set(s) => assert_eq!(*s, "hi"),
            _ => panic!("expected Set"),
        }
    }
}
