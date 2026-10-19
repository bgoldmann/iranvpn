//! Config distribution: bootstrap first, then optional network refresh (FR-8).

use crate::bootstrap::{self, parse_server_list_json};
use crate::config::{ConfigSource, ServerList};
use anyhow::Result;
use reqwest::Client;
use std::path::Path;
use std::time::Duration;
use tracing::info;

const FETCH_TIMEOUT: Duration = Duration::from_secs(15);

pub use bootstrap::{
    default_config_sources, embedded_server_list, load_last_good, resolve_bootstrap,
    save_last_good, EMBEDDED_SERVER_LIST_JSON,
};

/// Fallback server list when all config sources fail (embedded bootstrap).
pub fn fallback_server_list() -> ServerList {
    embedded_server_list()
}

/// Bootstrap without network: last-good → embedded.
pub fn bootstrap_server_list(cache_dir: Option<&Path>) -> ServerList {
    resolve_bootstrap(cache_dir)
}

/// Fetch server list from first successful of multiple sources (redundant).
/// Prefer calling this *after* a tunnel is up.
pub async fn fetch_server_list(sources: &[ConfigSource]) -> Result<ServerList> {
    let client = Client::builder().timeout(FETCH_TIMEOUT).build()?;

    for source in sources {
        if let Ok(list) = fetch_one(&client, &source.url).await {
            info!(url = %source.url, "fetched server list");
            return Ok(list);
        }
    }
    anyhow::bail!("all config sources failed")
}

/// Fetch via SOCKS (post-tunnel refresh).
pub async fn fetch_server_list_via_socks(
    sources: &[ConfigSource],
    socks_port: u16,
) -> Result<ServerList> {
    let proxy_url = format!("socks5h://127.0.0.1:{socks_port}");
    let client = Client::builder()
        .proxy(reqwest::Proxy::all(&proxy_url)?)
        .timeout(FETCH_TIMEOUT)
        .build()?;

    for source in sources {
        if let Ok(list) = fetch_one(&client, &source.url).await {
            info!(url = %source.url, "fetched server list via socks");
            return Ok(list);
        }
    }
    anyhow::bail!("all config sources failed via socks")
}

async fn fetch_one(client: &Client, url: &str) -> Result<ServerList> {
    let resp = client.get(url).send().await?;
    resp.error_for_status_ref()?;
    let text = resp.text().await?;
    parse_server_list_json(&text)
}
