//! Config types for VLESS, VMess, Trojan, WireGuard (Rostam-style).
//! Used for zero-config fetch and advanced user import.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use thiserror::Error;
use url::Url;

/// Kind of transport path (matches PRD fallback order).
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PathKind {
    Psiphon,
    Conduit,
    Xray,
    Rostam,
    /// User-imported custom (VLESS/VMess/Trojan/WireGuard)
    Custom,
}

/// Single path configuration (one of the protocol types).
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum PathConfig {
    Psiphon {
        #[serde(skip_serializing_if = "Option::is_none")]
        server_list_url: Option<String>,
    },
    Conduit {
        #[serde(skip_serializing_if = "Option::is_none")]
        discovery_url: Option<String>,
    },
    Xray {
        /// VLESS, VMess, or Trojan config (JSON or share link).
        config_json: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        subscription_url: Option<String>,
    },
    Rostam {
        /// Rostam-style obfuscated WireGuard config (INI or share link).
        wireguard_config: String,
    },
}

impl PathConfig {
    pub fn kind(&self) -> PathKind {
        match self {
            PathConfig::Psiphon { .. } => PathKind::Psiphon,
            PathConfig::Conduit { .. } => PathKind::Conduit,
            PathConfig::Xray { .. } => PathKind::Xray,
            PathConfig::Rostam { .. } => PathKind::Rostam,
        }
    }
}

/// Source for fetching server/config list (FR-8: decentralized/redundant).
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ConfigSource {
    pub url: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
}

/// Server list payload from config distribution (e.g. S3 + mirror).
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ServerList {
    #[serde(default)]
    pub paths: Vec<PathConfig>,
    #[serde(default)]
    pub sources: Vec<ConfigSource>,
    #[serde(default)]
    pub extra: HashMap<String, serde_json::Value>,
}

#[derive(Error, Debug)]
pub enum ConfigError {
    #[error("invalid URL: {0}")]
    InvalidUrl(String),
    #[error("parse error: {0}")]
    Parse(String),
    #[error("unsupported protocol: {0}")]
    UnsupportedProtocol(String),
}

/// Parse VLESS share link (vless://...).
pub fn parse_vless_share(link: &str) -> Result<PathConfig, ConfigError> {
    let url = Url::parse(link).map_err(|e| ConfigError::InvalidUrl(e.to_string()))?;
    if url.scheme() != "vless" {
        return Err(ConfigError::UnsupportedProtocol(url.scheme().to_string()));
    }
    let config_json = serde_json::json!({
        "share_link": link,
        "protocol": "vless"
    })
    .to_string();
    Ok(PathConfig::Xray {
        config_json,
        subscription_url: None,
    })
}

/// Parse VMess share link or base64 payload.
pub fn parse_vmess_share(link: &str) -> Result<PathConfig, ConfigError> {
    let config_json = if link.starts_with("vmess://") {
        let b64 = link.trim_start_matches("vmess://");
        use base64::Engine;
        let decoded = base64::engine::general_purpose::STANDARD
            .decode(b64)
            .map_err(|e| ConfigError::Parse(e.to_string()))?;
        let s = String::from_utf8(decoded).map_err(|e| ConfigError::Parse(e.to_string()))?;
        serde_json::json!({ "vmess": s }).to_string()
    } else {
        serde_json::json!({ "raw": link }).to_string()
    };
    Ok(PathConfig::Xray {
        config_json,
        subscription_url: None,
    })
}

/// Parse Trojan share link (trojan://...).
pub fn parse_trojan_share(link: &str) -> Result<PathConfig, ConfigError> {
    let _url = Url::parse(link).map_err(|e| ConfigError::InvalidUrl(e.to_string()))?;
    let config_json = serde_json::json!({ "share_link": link, "protocol": "trojan" }).to_string();
    Ok(PathConfig::Xray {
        config_json,
        subscription_url: None,
    })
}

/// Parse WireGuard / Rostam-style config (INI-style).
pub fn parse_wireguard_config(ini: &str) -> Result<PathConfig, ConfigError> {
    if ini.trim().is_empty() {
        return Err(ConfigError::Parse("empty config".into()));
    }
    Ok(PathConfig::Rostam {
        wireguard_config: ini.to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn path_config_kind() {
        let p = PathConfig::Psiphon {
            server_list_url: None,
        };
        assert_eq!(p.kind(), PathKind::Psiphon);
    }

    #[test]
    fn server_list_default() {
        let s = ServerList::default();
        assert!(s.paths.is_empty());
        assert!(s.sources.is_empty());
    }
}
