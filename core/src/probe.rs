//! Connectivity probe: path is connected only after a known-token fetch via SOCKS.
//! "Process still running" is not connectivity.

use anyhow::{anyhow, Result};
use std::time::Duration;

/// Default probe URL and expected substring (Cloudflare trace).
pub const DEFAULT_PROBE_URL: &str = "https://www.cloudflare.com/cdn-cgi/trace";
pub const DEFAULT_TOKEN: &str = "ip=";
pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(8);

/// One connectivity check through the tunnel.
/// `expect_status` rejects any other code (generate_204 must be 204, not a 200 block page).
/// Empty `token` with no `expect_status` accepts any 2xx.
struct ProbeSpec<'a> {
    url: &'a str,
    token: &'a str,
    expect_status: Option<u16>,
    timeout: Duration,
}

/// Cloudflare trace first, then endpoints that are not Cloudflare.
/// 1.1.1.1 and cp.cloudflare.com are the same network as the primary, so they
/// do not save Connect when Cloudflare itself is the failure.
fn default_probe_specs() -> [ProbeSpec<'static>; 3] {
    [
        ProbeSpec {
            url: DEFAULT_PROBE_URL,
            token: DEFAULT_TOKEN,
            expect_status: None,
            timeout: DEFAULT_TIMEOUT,
        },
        ProbeSpec {
            url: "https://www.gstatic.com/generate_204",
            token: "",
            expect_status: Some(204),
            timeout: Duration::from_secs(4),
        },
        ProbeSpec {
            url: "https://detectportal.firefox.com/success.txt",
            token: "success",
            expect_status: None,
            timeout: Duration::from_secs(4),
        },
    ]
}

/// Probe through a local SOCKS5 proxy. Returns Ok(()) if body contains [token]
/// (empty token = any 2xx is success).
pub async fn probe_through_socks(
    socks_port: u16,
    url: &str,
    token: &str,
    timeout: Duration,
) -> Result<()> {
    probe_one(
        socks_port,
        &ProbeSpec {
            url,
            token,
            expect_status: None,
            timeout,
        },
    )
    .await
}

async fn probe_one(socks_port: u16, spec: &ProbeSpec<'_>) -> Result<()> {
    if socks_port == 0 {
        return Err(anyhow!("no SOCKS port"));
    }
    let proxy_url = format!("socks5h://127.0.0.1:{socks_port}");
    let client = reqwest::Client::builder()
        .proxy(reqwest::Proxy::all(&proxy_url)?)
        .timeout(spec.timeout)
        .user_agent("IranVPN/1.0")
        .build()?;
    let resp = client.get(spec.url).send().await?;
    let status = resp.status();
    if let Some(expected) = spec.expect_status {
        if status.as_u16() != expected {
            return Err(anyhow!("probe HTTP {status}, want {expected}"));
        }
    } else if !status.is_success() {
        return Err(anyhow!("probe HTTP {status}"));
    }
    if spec.token.is_empty() {
        return Ok(());
    }
    let body = resp.text().await?;
    if !body.contains(spec.token) {
        return Err(anyhow!("probe token missing"));
    }
    Ok(())
}

/// Try Cloudflare trace, then non-Cloudflare checks, so a CF-only failure
/// does not fail the gate while the tunnel still reaches the rest of the internet.
pub async fn probe_default(socks_port: u16) -> Result<()> {
    let mut last_err = anyhow!("no probes");
    for spec in default_probe_specs() {
        match probe_one(socks_port, &spec).await {
            Ok(()) => return Ok(()),
            Err(e) => last_err = e,
        }
    }
    Err(last_err)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn probe_rejects_zero_port() {
        let r = probe_default(0).await;
        assert!(r.is_err());
    }

    #[test]
    fn fallback_is_not_cloudflare_only() {
        let specs = default_probe_specs();
        assert_eq!(specs[0].url, DEFAULT_PROBE_URL);
        assert!(specs.iter().any(|s| {
            let host = s.url.trim_start_matches("https://");
            !host.contains("cloudflare") && !host.starts_with("1.1.1.1")
        }));
        assert!(specs.iter().any(|s| s.expect_status == Some(204)));
    }
}
