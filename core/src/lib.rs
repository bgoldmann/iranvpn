//! Iran VPN Core — shared library for race/probe engine, config, DoH, bootstrap.
//!
//! Used by Android, iOS, Windows, and macOS apps. No UI.

pub mod bootstrap;
pub mod config;
pub mod doh;
pub mod fallback;
pub mod fetch;
pub mod path;
pub mod probe;
pub mod protocol_registry;

#[cfg(all(feature = "jni", target_os = "android"))]
pub mod jni_bridge;

pub mod ffi;

pub use bootstrap::{embedded_server_list, resolve_bootstrap};
pub use config::{ConfigSource, PathConfig, PathKind, ServerList};
pub use doh::DohClient;
pub use fallback::{FallbackEngine, FallbackEvent, FallbackState, NoSocksPort, SocksPortProvider};
pub use fetch::{
    bootstrap_server_list, default_config_sources, fallback_server_list, fetch_server_list,
    fetch_server_list_via_socks, load_last_good, save_last_good,
};
pub use path::{PathRunner, PathStatus};
pub use probe::{probe_default, probe_through_socks};
pub use protocol_registry::ProtocolRegistry;
