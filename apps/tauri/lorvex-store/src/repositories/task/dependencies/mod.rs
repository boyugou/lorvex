//! Task dependency edges: write side (`write`) plus graph-traversal
//! read API (`graph`).

mod write;

pub mod graph;

#[cfg(test)]
mod write_tests;

pub use write::*;
