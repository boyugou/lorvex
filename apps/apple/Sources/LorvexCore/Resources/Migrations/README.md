# Resources/Migrations — derived copies, do not edit

Bundled byte-identical copies of the canonical migration ladder in
`schema/migrations/` at the monorepo root — the Apple app's schema authority
(one `NNN_<name>.sql` per post-baseline schema version, versions 002+).
`SwiftLorvexCoreService` loads these at open time, verifies each file against the
bundled `checksums.lock`, and passes the ladder to `LorvexStore.open`.

Never edit a file here directly: change the canonical `schema/migrations/`
copy per its README and mirror it here byte-identically.
`apps/apple/script/verify_schema_embed.sh` enforces the byte-parity with the
canonical `schema/migrations/`.
