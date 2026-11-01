//! Bootstrap order: last-good cache → signed embedded bundle → network fetch (post-tunnel).
//! FR-8 without requiring a live fetch before first connect.

use crate::config::{ConfigSource, ServerList};
use anyhow::{anyhow, Result};
use base64::Engine;
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::{Deserialize, Serialize};
use serde_json::Value;
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

/// Compact JSON with object keys sorted. Signatures are over these bytes.
pub fn canonical_json(value: &Value) -> Result<Vec<u8>> {
    let mut out = Vec::new();
    write_canonical(&mut out, value)?;
    Ok(out)
}

fn write_canonical(out: &mut Vec<u8>, value: &Value) -> Result<()> {
    match value {
        Value::Null => out.extend_from_slice(b"null"),
        Value::Bool(true) => out.extend_from_slice(b"true"),
        Value::Bool(false) => out.extend_from_slice(b"false"),
        Value::Number(n) => out.extend_from_slice(n.to_string().as_bytes()),
        Value::String(s) => {
            let encoded = serde_json::to_string(s)?;
            out.extend_from_slice(encoded.as_bytes());
        }
        Value::Array(items) => {
            out.push(b'[');
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push(b',');
                }
                write_canonical(out, item)?;
            }
            out.push(b']');
        }
        Value::Object(map) => {
            out.push(b'{');
            let mut keys: Vec<&String> = map.keys().collect();
            keys.sort();
            for (i, key) in keys.iter().enumerate() {
                if i > 0 {
                    out.push(b',');
                }
                let encoded = serde_json::to_string(key)?;
                out.extend_from_slice(encoded.as_bytes());
                out.push(b':');
                write_canonical(out, &map[*key])?;
            }
            out.push(b'}');
        }
    }
    Ok(())
}

/// Verify Ed25519 over the canonical JSON of `payload`.
/// No configured key: accept the payload (current published lists are unsigned).
/// A configured key: a bad or missing signature is rejected.
pub fn verify_signed(list: &SignedServerList) -> Result<ServerList> {
    verify_signed_with_key(list, verify_pubkey())
}

pub fn verify_signed_with_key(list: &SignedServerList, pk_b64: Option<&str>) -> Result<ServerList> {
    let mut payload = serde_json::to_value(&list.payload)?;
    if let Some(obj) = payload.as_object_mut() {
        let empty_extra = obj
            .get("extra")
            .and_then(|v| v.as_object())
            .map(|m| m.is_empty())
            .unwrap_or(false);
        if empty_extra {
            obj.remove("extra");
        }
    }
    verify_payload_value(&payload, &list.signature, pk_b64)
}

fn verify_payload_value(payload: &Value, signature: &str, pk_b64: Option<&str>) -> Result<ServerList> {
    let list: ServerList = serde_json::from_value(payload.clone())
        .map_err(|e| anyhow!("server list payload: {e}"))?;
    if list.paths.is_empty() {
        return Err(anyhow!("server list has no paths"));
    }
    let Some(pk_b64) = pk_b64 else {
        return Ok(list);
    };
    let pk_bytes = base64::engine::general_purpose::STANDARD
        .decode(pk_b64)
        .map_err(|e| anyhow!("bad pubkey: {e}"))?;
    let sig_bytes = base64::engine::general_purpose::STANDARD
        .decode(signature)
        .map_err(|e| anyhow!("bad signature b64: {e}"))?;
    if pk_bytes.len() != 32 || sig_bytes.len() != 64 {
        return Err(anyhow!("pubkey must be 32 bytes and signature 64 bytes"));
    }
    let key_bytes: [u8; 32] = pk_bytes
        .as_slice()
        .try_into()
        .map_err(|_| anyhow!("pubkey must be 32 bytes"))?;
    let sig_array: [u8; 64] = sig_bytes
        .as_slice()
        .try_into()
        .map_err(|_| anyhow!("signature must be 64 bytes"))?;
    let key = VerifyingKey::from_bytes(&key_bytes).map_err(|e| anyhow!("bad pubkey: {e}"))?;
    let sig = Signature::from_bytes(&sig_array);
    let msg = canonical_json(payload)?;
    key.verify(&msg, &sig)
        .map_err(|_| anyhow!("server list signature rejected"))?;
    Ok(list)
}

/// Parse either a raw ServerList or a SignedServerList JSON.
/// The signature covers [canonical_json] of the `payload` object as it appears
/// in the file (sorted keys, no extra whitespace).
pub fn parse_server_list_json(json: &str) -> Result<ServerList> {
    parse_server_list_json_with_key(json, verify_pubkey())
}

pub fn parse_server_list_json_with_key(json: &str, pk_b64: Option<&str>) -> Result<ServerList> {
    let value: Value = serde_json::from_str(json).map_err(|e| anyhow!("server list json: {e}"))?;
    if value.get("payload").is_some() && value.get("signature").is_some() {
        let signature = value["signature"]
            .as_str()
            .ok_or_else(|| anyhow!("signature must be a string"))?;
        return verify_payload_value(&value["payload"], signature, pk_b64);
    }
    let list: ServerList =
        serde_json::from_value(value).map_err(|e| anyhow!("server list json: {e}"))?;
    if pk_b64.is_some() {
        return Err(anyhow!("unsigned server list rejected"));
    }
    if list.paths.is_empty() {
        return Err(anyhow!("server list has no paths"));
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
            // Cloudflare Worker mirror — see docs/cloudflare-config-mirror.md
            url: "https://iranvpn-config.goldmannllc.com/server-list.json".to_string(),
            label: Some("Mirror (Cloudflare Worker)".to_string()),
        },
        ConfigSource {
            url: "https://raw.githubusercontent.com/bgoldmann/iranvpn/main/dist-config/server-list.json"
                .to_string(),
            label: Some("Primary (GitHub)".to_string()),
        },
        ConfigSource {
            url: "https://cdn.jsdelivr.net/gh/bgoldmann/iranvpn@main/dist-config/server-list.json"
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

    #[test]
    fn dist_server_list_matches_hardcoded_sources() {
        let json = include_str!("../../dist-config/server-list.json");
        let list = parse_server_list_json(json).expect("dist server-list");
        assert!(matches!(
            list.paths.first(),
            Some(crate::config::PathConfig::Psiphon { .. })
        ));
        let defaults = default_config_sources();
        assert_eq!(list.sources.len(), defaults.len());
        for (from_file, hardcoded) in list.sources.iter().zip(defaults.iter()) {
            assert_eq!(from_file.url, hardcoded.url);
            assert_eq!(from_file.label, hardcoded.label);
        }
        assert!(defaults[0].url.contains("iranvpn-config.goldmannllc.com"));
    }

    #[test]
    fn ed25519_verifies_signed_list_and_rejects_tamper() {
        use ed25519_dalek::{Signer, SigningKey};

        let signing = SigningKey::from_bytes(&[9u8; 32]);
        let pubkey = base64::engine::general_purpose::STANDARD.encode(signing.verifying_key().to_bytes());
        let payload = serde_json::json!({
            "paths": [{ "type": "psiphon" }],
            "sources": []
        });
        let msg = canonical_json(&payload).unwrap();
        let sig = base64::engine::general_purpose::STANDARD.encode(signing.sign(&msg).to_bytes());
        let envelope = serde_json::json!({
            "payload": payload,
            "signature": sig,
        });
        let json = envelope.to_string();
        let list = parse_server_list_json_with_key(&json, Some(&pubkey)).expect("valid signature");
        assert!(matches!(
            list.paths.first(),
            Some(crate::config::PathConfig::Psiphon { .. })
        ));

        let mut flipped = signing.sign(&msg).to_bytes();
        flipped[0] ^= 0xff;
        let mut bad = envelope.clone();
        bad["signature"] = serde_json::Value::String(
            base64::engine::general_purpose::STANDARD.encode(flipped),
        );
        let bad_json = bad.to_string();
        assert!(parse_server_list_json_with_key(&bad_json, Some(&pubkey)).is_err());

        let unsigned = r#"{"paths":[{"type":"psiphon"}],"sources":[]}"#;
        assert!(parse_server_list_json_with_key(unsigned, Some(&pubkey)).is_err());
        assert!(parse_server_list_json_with_key(unsigned, None).is_ok());
    }
}
