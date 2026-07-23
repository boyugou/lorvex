//! `lorvex-mcp-derive` — internal proc-macro derive for MCP contract
//! validation.
//!
//! # Why this crate exists
//!
//! `mcp-server/src/contract/` defines ~114 `Args` / `Input` / `Request`
//! structs that describe the JSON envelopes accepted by the MCP tool
//! surface. Each handler then runs a near-identical preamble against
//! the deserialized struct: validate UUID-shaped fields, cap string
//! lengths, range-check priorities, dedup + existence-check tag /
//! task / list ID lists. The hand-rolled call sites live in
//! `mcp-server/src/tasks/validation.rs` (~300 LoC) plus inline calls
//! across every handler module.
//!
//! Most of those checks are mechanically derivable from the
//! `JsonSchema` annotations the contract structs already carry —
//! `range(min=1, max=3)`, `Option<String>` length caps, `Vec<String>`
//! UUID lists. The `#[derive(ContractValidate)]` macro emitted by this
//! crate replaces the hand-written preamble with a single
//! `args.validate(&ctx)?` call.
//!
//! # Adopting on new contract structs
//!
//! Coverage today: the derive is wired across representative
//! task / calendar / list / habit / preference `Args` structs for the
//! shape-only half (`validate_shape`), and across the focus-write and
//! daily-review-amend args structs for the DB-touching `exists_in`
//! half (`validate`). Other handlers still call the hand-rolled
//! preamble directly.
//!
//! `mcp-server/src/tasks/validation.rs` is the source of truth for
//! the underlying check rules; the derive emits calls into those
//! helpers, it does not reimplement them.
//!
//! To migrate another struct:
//!
//! 1. Add `#[derive(lorvex_mcp_derive::ContractValidate)]` to the
//!    struct definition in `mcp-server/src/contract/...`.
//! 2. Annotate each field that needs validation with one or more
//!    `#[validate(...)]` attributes (see "Supported attributes"
//!    below).
//! 3. Replace the hand-rolled validation preamble in the handler
//!    with a single `args.validate(&ctx)?` (or the no-DB variant
//!    `args.validate_shape()?` for purely shape-only structs).
//! 4. If the struct is fully covered by the derive, delete the
//!    corresponding lines from the handler. If only part is covered,
//!    let the derive run first (it returns early on the first error)
//!    and keep the residual hand-rolled calls.
//!
//! # Supported attributes
//!
//! All attributes attach to struct fields and live under the
//! `#[validate(...)]` namespace.
//!
//! | Attribute | Field type | Emits |
//! |---|---|---|
//! | `#[validate(uuid)]` | `String` / `Option<String>` | `validate_uuid_arg` |
//! | `#[validate(uuid_list)]` | `Option<Vec<String>>` / `Vec<String>` | per-element `validate_uuid_shape` |
//! | `#[validate(string, max_length = CONST)]` | `String` / `Option<String>` | `validate_string_length` / `validate_optional_string_length` |
//! | `#[validate(tags, max_length = CONST)]` | `Option<Vec<String>>` | `validate_tags_length` |
//! | `#[validate(int_range(min = N, max = M))]` | `Option<i64>` / `Option<u8>` / `Option<u32>` etc. | manual range check + `McpError::Validation` |
//! | `#[validate(exists_in = "tasks")]` | `Option<Vec<String>>` / `Vec<String>` | `validate_task_ids_exist` (needs `&ValidationCtx`) |
//! | `#[validate(exists_in = "tasks_active")]` | same | `validate_task_ids_active` |
//! | `#[validate(exists_in = "lists")]` | same | `validate_list_ids_exist` |
//!
//! # Trait surface
//!
//! The derive emits `impl crate::contract_validate::ContractValidate
//! for <Struct>`. Two methods:
//!
//! - `validate_shape(&self) -> Result<(), McpError>` — runs every
//!   non-DB check (UUID shape, string length, range, tag length).
//! - `validate(&self, ctx: &ValidationCtx) -> Result<(), McpError>` —
//!   runs `validate_shape` first, then the DB-touching `exists_in`
//!   checks. Defaults to calling `validate_shape` if no `exists_in`
//!   attribute is present on any field.
//!
//! `ValidationCtx` is a thin borrow over a `&Connection` defined in
//! `mcp-server/src/contract_validate.rs`.
//!
//! # Path conventions
//!
//! The derive emits paths rooted at `crate::` — i.e. it assumes the
//! generated `impl` lives inside the `lorvex-mcp-server` crate. This
//! is intentional: the derive is `pub(crate)`-flavored and not meant
//! to be consumed from outside the MCP server.

use proc_macro::TokenStream;
use proc_macro2::TokenStream as TokenStream2;
use quote::{format_ident, quote};
use syn::{
    parse_macro_input, Data, DeriveInput, Expr, ExprLit, Fields, Lit, Meta, Token, Type, TypePath,
};

/// Derive macro entry point. See crate-level docs for the supported
/// attribute surface.
#[proc_macro_derive(ContractValidate, attributes(validate))]
pub fn derive_contract_validate(input: TokenStream) -> TokenStream {
    let input = parse_macro_input!(input as DeriveInput);
    match expand(&input) {
        Ok(ts) => ts.into(),
        Err(e) => e.to_compile_error().into(),
    }
}

fn expand(input: &DeriveInput) -> syn::Result<TokenStream2> {
    let struct_ident = &input.ident;
    let fields = match &input.data {
        Data::Struct(s) => match &s.fields {
            Fields::Named(named) => &named.named,
            _ => {
                return Err(syn::Error::new_spanned(
                    struct_ident,
                    "ContractValidate only supports structs with named fields",
                ))
            }
        },
        _ => {
            return Err(syn::Error::new_spanned(
                struct_ident,
                "ContractValidate only supports structs",
            ))
        }
    };

    let mut shape_checks: Vec<TokenStream2> = Vec::new();
    let mut db_checks: Vec<TokenStream2> = Vec::new();

    for field in fields {
        let Some(field_ident) = field.ident.as_ref() else {
            continue;
        };
        let field_name_str = field_ident.to_string();
        let ty = &field.ty;
        let is_opt = is_option(ty);

        for attr in &field.attrs {
            if !attr.path().is_ident("validate") {
                continue;
            }
            let entries = parse_validate_attr(attr)?;
            for entry in entries {
                match entry {
                    ValidateEntry::Uuid => {
                        shape_checks.push(emit_uuid(field_ident, &field_name_str, is_opt));
                    }
                    ValidateEntry::UuidList => {
                        shape_checks.push(emit_uuid_list(field_ident, &field_name_str, is_opt));
                    }
                    ValidateEntry::String { max_length } => {
                        shape_checks.push(emit_string(
                            field_ident,
                            &field_name_str,
                            is_opt,
                            &max_length,
                        ));
                    }
                    ValidateEntry::Tags { max_length } => {
                        shape_checks.push(emit_tags(field_ident, &max_length));
                    }
                    ValidateEntry::IntRange { min, max } => {
                        shape_checks.push(emit_int_range(field_ident, &field_name_str, &min, &max));
                    }
                    ValidateEntry::ExistsIn(kind) => {
                        db_checks.push(emit_exists_in(
                            field_ident,
                            &field_name_str,
                            &kind,
                            is_opt,
                        )?);
                    }
                }
            }
        }
    }

    // helper struct to reference the trait without leaking the
    // module path into every consumer.
    let trait_path = quote!(crate::contract_validate::ContractValidate);
    let ctx_path = quote!(crate::contract_validate::ValidationCtx);
    let err_path = quote!(crate::error::McpError);

    Ok(quote! {
        impl #trait_path for #struct_ident {
            fn validate_shape(&self) -> ::core::result::Result<(), #err_path> {
                #(#shape_checks)*
                ::core::result::Result::Ok(())
            }

            fn validate(&self, ctx: &#ctx_path<'_>) -> ::core::result::Result<(), #err_path> {
                <Self as #trait_path>::validate_shape(self)?;
                let _ctx = ctx;
                #(#db_checks)*
                ::core::result::Result::Ok(())
            }
        }

    })
}

// ── attribute parsing ──────────────────────────────────────────────

enum ValidateEntry {
    Uuid,
    UuidList,
    String {
        max_length: TokenStream2,
    },
    Tags {
        max_length: TokenStream2,
    },
    IntRange {
        min: TokenStream2,
        max: TokenStream2,
    },
    ExistsIn(String),
}

fn parse_validate_attr(attr: &syn::Attribute) -> syn::Result<Vec<ValidateEntry>> {
    let mut out = Vec::new();
    let nested =
        attr.parse_args_with(syn::punctuated::Punctuated::<Meta, Token![,]>::parse_terminated)?;

    let mut iter = nested.into_iter().peekable();
    while let Some(meta) = iter.next() {
        match meta {
            Meta::Path(p) if p.is_ident("uuid") => out.push(ValidateEntry::Uuid),
            Meta::Path(p) if p.is_ident("uuid_list") => out.push(ValidateEntry::UuidList),
            Meta::Path(p) if p.is_ident("string") => {
                let max_length = take_max_length(&mut iter, &p)?;
                out.push(ValidateEntry::String { max_length });
            }
            Meta::Path(p) if p.is_ident("tags") => {
                let max_length = take_max_length(&mut iter, &p)?;
                out.push(ValidateEntry::Tags { max_length });
            }
            Meta::List(list) if list.path.is_ident("int_range") => {
                let mut min: Option<TokenStream2> = None;
                let mut max: Option<TokenStream2> = None;
                let inner = list.parse_args_with(
                    syn::punctuated::Punctuated::<Meta, Token![,]>::parse_terminated,
                )?;
                for m in inner {
                    if let Meta::NameValue(nv) = m {
                        let key = nv
                            .path
                            .get_ident()
                            .map(|i| i.to_string())
                            .unwrap_or_default();
                        let val_tokens = expr_to_tokens(&nv.value);
                        match key.as_str() {
                            "min" => min = Some(val_tokens),
                            "max" => max = Some(val_tokens),
                            other => {
                                return Err(syn::Error::new_spanned(
                                    nv.path,
                                    format!("unknown int_range key '{other}' (expected min|max)"),
                                ));
                            }
                        }
                    } else {
                        return Err(syn::Error::new_spanned(
                            m,
                            "int_range expects `min = N, max = M`",
                        ));
                    }
                }
                let (Some(min), Some(max)) = (min, max) else {
                    return Err(syn::Error::new_spanned(
                        list,
                        "int_range requires both `min` and `max`",
                    ));
                };
                out.push(ValidateEntry::IntRange { min, max });
            }
            Meta::NameValue(nv) if nv.path.is_ident("exists_in") => {
                let s = match &nv.value {
                    Expr::Lit(ExprLit {
                        lit: Lit::Str(s), ..
                    }) => s.value(),
                    _ => {
                        return Err(syn::Error::new_spanned(
                            &nv.value,
                            "exists_in requires a string literal (\"tasks\"|\"tasks_active\"|\"lists\")",
                        ))
                    }
                };
                out.push(ValidateEntry::ExistsIn(s));
            }
            other => {
                return Err(syn::Error::new_spanned(
                    other,
                    "unknown validate attribute; supported: uuid, uuid_list, string, tags, int_range(min=..,max=..), exists_in=\"...\"",
                ));
            }
        }
    }

    Ok(out)
}

/// Consume the next `max_length = EXPR` entry from the iterator. The
/// `string` and `tags` attribute forms always pair with a
/// `max_length` modifier; pre-fix the parser swallowed the `string`
/// keyword and silently accepted a missing `max_length`.
fn take_max_length<I: Iterator<Item = Meta>>(
    iter: &mut std::iter::Peekable<I>,
    parent: &syn::Path,
) -> syn::Result<TokenStream2> {
    let next = iter.next().ok_or_else(|| {
        syn::Error::new_spanned(parent, "missing `max_length = ...` after this keyword")
    })?;
    match next {
        Meta::NameValue(nv) if nv.path.is_ident("max_length") => Ok(expr_to_tokens(&nv.value)),
        other => Err(syn::Error::new_spanned(
            other,
            "expected `max_length = EXPR` (a usize-typed const path or literal)",
        )),
    }
}

fn expr_to_tokens(e: &Expr) -> TokenStream2 {
    quote!(#e)
}

// ── codegen ────────────────────────────────────────────────────────

fn emit_uuid(field: &syn::Ident, field_name: &str, is_opt: bool) -> TokenStream2 {
    if is_opt {
        quote! {
            if let ::core::option::Option::Some(__v) = self.#field.as_deref() {
                crate::tasks::validation::validate_uuid_shape(__v, #field_name)?;
            }
        }
    } else {
        quote! {
            crate::tasks::validation::validate_uuid_shape(&self.#field, #field_name)?;
        }
    }
}

fn emit_uuid_list(field: &syn::Ident, field_name: &str, is_opt: bool) -> TokenStream2 {
    if is_opt {
        quote! {
            if let ::core::option::Option::Some(__list) = self.#field.as_deref() {
                for __id in __list {
                    crate::tasks::validation::validate_uuid_shape(__id, #field_name)?;
                }
            }
        }
    } else {
        quote! {
            for __id in &self.#field {
                crate::tasks::validation::validate_uuid_shape(__id, #field_name)?;
            }
        }
    }
}

fn emit_string(
    field: &syn::Ident,
    field_name: &str,
    is_opt: bool,
    max_len: &TokenStream2,
) -> TokenStream2 {
    if is_opt {
        quote! {
            crate::tasks::validation::validate_optional_string_length(
                self.#field.as_deref(),
                #field_name,
                #max_len,
            )?;
        }
    } else {
        quote! {
            crate::tasks::validation::validate_string_length(
                &self.#field,
                #field_name,
                #max_len,
            )?;
        }
    }
}

fn emit_tags(field: &syn::Ident, max_len: &TokenStream2) -> TokenStream2 {
    quote! {
        crate::tasks::validation::validate_tags_length(
            self.#field.as_deref(),
            #max_len,
        )?;
    }
}

fn emit_int_range(
    field: &syn::Ident,
    field_name: &str,
    min: &TokenStream2,
    max: &TokenStream2,
) -> TokenStream2 {
    let err_var = format_ident!("__lorvex_range_err_{}", field);
    let _ = err_var;
    // emits its own range check (rather than reusing
    // `lorvex_domain::validation::validate_priority`) so the same
    // attribute can express any range — priority (1..=3), mood
    // (1..=5), arbitrary numeric caps. The error wording mirrors the
    // hand-rolled `validate_priority` shape so existing tests that
    // grep for "must be between" continue to pass.
    quote! {
        if let ::core::option::Option::Some(__v) = self.#field {
            let __v_i64: i64 = ::core::convert::TryFrom::try_from(__v).map_err(|_| {
                crate::error::McpError::Validation(format!(
                    "{} value out of i64 range",
                    #field_name
                ))
            })?;
            if !((#min as i64)..=(#max as i64)).contains(&__v_i64) {
                return ::core::result::Result::Err(crate::error::McpError::Validation(
                    format!(
                        "{} must be between {} and {} (got {})",
                        #field_name,
                        #min,
                        #max,
                        __v_i64,
                    ),
                ));
            }
        }
    }
}

fn emit_exists_in(
    field: &syn::Ident,
    field_name: &str,
    kind: &str,
    is_opt: bool,
) -> syn::Result<TokenStream2> {
    let call: TokenStream2 = match kind {
        "tasks" => quote!(crate::tasks::validation::validate_task_ids_exist),
        "tasks_active" => quote!(crate::tasks::validation::validate_task_ids_active),
        "lists" => quote!(crate::tasks::validation::validate_list_ids_exist),
        other => {
            return Err(syn::Error::new_spanned(
                field,
                format!("unknown exists_in target '{other}' (expected tasks|tasks_active|lists)"),
            ))
        }
    };
    Ok(if is_opt {
        quote! {
            if let ::core::option::Option::Some(__list) = self.#field.as_deref() {
                #call(_ctx.conn, __list, #field_name)?;
            }
        }
    } else {
        quote! {
            #call(_ctx.conn, &self.#field, #field_name)?;
        }
    })
}

// ── tiny type inspector ────────────────────────────────────────────

fn is_option(ty: &Type) -> bool {
    let Type::Path(TypePath { path, .. }) = ty else {
        return false;
    };
    path.segments
        .last()
        .map(|s| s.ident == "Option")
        .unwrap_or(false)
}
