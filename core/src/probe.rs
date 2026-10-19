//! Connectivity probe: path is connected only after a known-token fetch via SOCKS.
//! "Process still running" is not connectivity.

use anyhow::{anyhow, Result};
use std::time::Duration;

/// Default probe URL and expected substring (Cloudflare trace).
pub const DEFAULT_PROBE_URL: &str = "https://www.cloudflare.com/cdn-cgi/trace";
pub const DEFAULT_TOKEN: &str = "ip=";
pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(8);

/// Probe through a local SOCKS5 proxy. Returns Ok(()) if body contains [token].
pub async fn probe_through_socks(
    socks_port: u16,
    url: &str,
    token: &str,
    timeout: Duration,
) -> Result<()> {
    if socks_port == 0 {
        return Err(anyhow!("no SOCKS port"));
    }
    let proxy_url = format!("socks5h://127.0.0.1:{socks_port}");
    let client = reqwest::Client::builder()
        .proxy(reqwest::Proxy::all(&proxy_url)?)
        .timeout(timeout)
        .user_agent("IranVPN/1.0")
        .build()?;
    let resp = client.get(url).send().await?;
    if !resp.status().is_success() {
        return Err(anyhow!("probe HTTP {}", resp.status()));
    }
    let body = resp.text().await?;
    if !body.contains(token) {
        return Err(anyhow!("probe token missing"));
    }
    Ok(())
}

/// Convenience: default Cloudflare probe.
pub async fn probe_default(socks_port: u16) -> Result<()> {
    probe_through_socks(
        socks_port,
        DEFAULT_PROBE_URL,
        DEFAULT_TOKEN,
        DEFAULT_TIMEOUT,
    )
    .await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn probe_rejects_zero_port() {
        let r = probe_default(0).await;
        assert!(r.is_err());
    }
}
