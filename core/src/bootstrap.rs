//! Bootstrap order: last-good cache → signed embedded bundle → network fetch (post-tunnel).
//! FR-8 without requiring a live fetch before first connect.

use crate::config::{ConfigSource, ServerList};
use anyhow::{anyhow, Result};
use base64::Engine;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

/// Embedded bootstrap JSON (Psiphon zero-config; Conduit included in Psiphon).
pub const EMBEDDED_SERVER_LIST_JSON: &str =
    r#"{"paths":[{"type":"psiphon","server_list_url":null}],"sources":[]}"#;

/// Optional Ed25519 public key (32 bytes, base64) for verifying signed server lists.
/// Replace with your production key; unsigned lists are accepted only if no key is set
/// OR when using the embedded bootstrap.
static VERIFY_PUBKEY_B64: OnceLock<Option<String>> = OnceLock::new();

/// Signed envelope: `{"payload": <ServerList>, "signature": "<base64 ed25519>"}`
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SignedServerList {
    pub payload: ServerList,
    pub signature: String,
}

pub fn set_verify_pubkey_b64(key: Option<String>) {
    let _ = VERIFY_PUBKEY_B64.set(key);
}

fn verify_pubkey() -> Option<&'static str> {
    VERIFY_PUBKEY_B64.get().and_then(|o| o.as_deref())
}

/// Verify Ed25519 signature over canonical JSON of payload.
/// Uses a simple HMAC-style check with ed25519 if `ed25519-dalek` is available;
/// otherwise accepts unsigned when no pubkey configured.
pub fn verify_signed(list: &SignedServerList) -> Result<ServerList> {
    let Some(pk_b64) = verify_pubkey() else {
        // No key configured — accept payload (dev / embedded mode)
        return Ok(list.payload.clone());
    };
    let pk_bytes = base64::engine::general_purpose::STANDARD
        .decode(pk_b64)
        .map_err(|e| anyhow!("bad pubkey: {e}"))?;
    if pk_bytes.len() != 32 {
        return Err(anyhow!("pubkey must be 32 bytes"));
    }
    let sig_bytes = base64::engine::general_purpose::STANDARD
        .decode(&list.signature)
        .map_err(|e| anyhow!("bad signature b64: {e}"))?;
    if sig_bytes.len() != 64 {
        return Err(anyhow!("signature must be 64 bytes"));
    }
    let msg = serde_json::to_vec(&list.payload)?;
    if sig_bytes.iter().all(|&b| b == 0) {
        return Err(anyhow!("invalid signature"));
    }
    // Cryptographic verify requires ed25519-dalek. Until that dependency is enabled,
    // REJECT all signed envelopes when a pubkey is configured (fail closed).
    // Unsigned lists are only accepted when no pubkey is set (see parse_server_list_json).
    let _ = (pk_bytes, msg, &sig_bytes);
    Err(anyhow!(
        "signed server list verification not compiled in — unset verify pubkey or enable ed25519"
    ))
}

/// Parse either a raw ServerList or a SignedServerList JSON.
pub fn parse_server_list_json(json: &str) -> Result<ServerList> {
    if let Ok(signed) = serde_json::from_str::<SignedServerList>(json) {
        return verify_signed(&signed);
    }
    let list: ServerList = serde_json::from_str(json)?;
    if verify_pubkey().is_some() {
        // Key configured but payload unsigned — reject network lists
        return Err(anyhow!("unsigned server list rejected"));
    }
    Ok(list)
}

pub fn embedded_server_list() -> ServerList {
    serde_json::from_str(EMBEDDED_SERVER_LIST_JSON).unwrap_or_default()
}

pub fn last_good_path(cache_dir: &Path) -> PathBuf {
    cache_dir.join("last_good_server_list.json")
}

pub fn load_last_good(cache_dir: &Path) -> Option<ServerList> {
    let path = last_good_path(cache_dir);
    let data = std::fs::read_to_string(path).ok()?;
    parse_server_list_json(&data).ok()
}

pub fn save_last_good(cache_dir: &Path, list: &ServerList) -> Result<()> {
    std::fs::create_dir_all(cache_dir)?;
    let path = last_good_path(cache_dir);
    let json = serde_json::to_string(list)?;
    std::fs::write(path, json)?;
    Ok(())
}

/// Resolve bootstrap: last-good → embedded. Network fetch is separate (post-tunnel).
pub fn resolve_bootstrap(cache_dir: Option<&Path>) -> ServerList {
    if let Some(dir) = cache_dir {
        if let Some(list) = load_last_good(dir) {
            if !list.paths.is_empty() {
                return list;
            }
        }
    }
    embedded_server_list()
}

pub fn default_config_sources() -> Vec<ConfigSource> {
    vec![
        ConfigSource {
            url: "https://raw.githubusercontent.com/opensignalfoundation/iran-vpn/main/dist-config/server-list.json"
                .to_string(),
            label: Some("Primary (GitHub)".to_string()),
        },
        ConfigSource {
            url: "https://cdn.jsdelivr.net/gh/opensignalfoundation/iran-vpn@main/dist-config/server-list.json"
                .to_string(),
            label: Some("Mirror (jsDelivr)".to_string()),
        },
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn embedded_has_psiphon() {
        let list = embedded_server_list();
        assert!(!list.paths.is_empty());
        assert!(matches!(
            list.paths[0],
            crate::config::PathConfig::Psiphon { .. }
        ));
    }

    #[test]
    fn resolve_without_cache() {
        let list = resolve_bootstrap(None);
        assert!(!list.paths.is_empty());
    }
}
