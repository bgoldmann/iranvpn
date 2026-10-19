//! DNS-over-HTTPS client. US-006, FR-9.
//! Prefer tunneled DoH after connect; graceful fallback when blocked.

use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use std::net::IpAddr;
use std::time::Duration;

#[derive(Clone, Debug)]
pub struct DohClient {
    pub provider_url: String,
    pub timeout: Duration,
    /// Optional SOCKS5 port for tunneled DoH (post-connect).
    pub socks_port: Option<u16>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DohResponse {
    #[serde(default, rename = "Status")]
    pub status: i32,
    #[serde(default, rename = "Answer")]
    pub answer: Vec<DohAnswer>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DohAnswer {
    #[serde(rename = "type")]
    pub typ: u16,
    pub data: String,
}

impl Default for DohClient {
    fn default() -> Self {
        Self {
            // Cloudflare DoH — often blocked in Iran on clearnet; use via SOCKS after connect
            provider_url: "https://cloudflare-dns.com/dns-query".to_string(),
            timeout: Duration::from_secs(5),
            socks_port: None,
        }
    }
}

impl DohClient {
    pub fn new(provider_url: String) -> Self {
        Self {
            provider_url,
            timeout: Duration::from_secs(5),
            socks_port: None,
        }
    }

    pub fn with_socks(mut self, port: u16) -> Self {
        self.socks_port = Some(port);
        self
    }

    fn client(&self) -> Result<reqwest::Client> {
        let mut b = reqwest::Client::builder().timeout(self.timeout);
        if let Some(port) = self.socks_port {
            let proxy = format!("socks5h://127.0.0.1:{port}");
            b = b.proxy(reqwest::Proxy::all(&proxy)?);
        }
        Ok(b.build()?)
    }

    /// Resolve hostname to IPs via DoH (application/dns-json).
    pub async fn resolve(&self, name: &str) -> Result<Vec<IpAddr>> {
        let client = self.client()?;
        let resp = client
            .get(&self.provider_url)
            .query(&[("name", name), ("type", "A")])
            .header("Accept", "application/dns-json")
            .send()
            .await?;
        if !resp.status().is_success() {
            return Err(anyhow!("DoH HTTP {}", resp.status()));
        }
        let body: DohResponse = resp.json().await?;
        if body.status != 0 && body.answer.is_empty() {
            return Err(anyhow!("DoH status {}", body.status));
        }
        let mut ips = Vec::new();
        for ans in body.answer {
            if ans.typ == 1 {
                // A record
                if let Ok(ip) = ans.data.parse::<IpAddr>() {
                    ips.push(ip);
                }
            }
        }
        // Also try AAAA
        let resp6 = client
            .get(&self.provider_url)
            .query(&[("name", name), ("type", "AAAA")])
            .header("Accept", "application/dns-json")
            .send()
            .await;
        if let Ok(r) = resp6 {
            if r.status().is_success() {
                if let Ok(body6) = r.json::<DohResponse>().await {
                    for ans in body6.answer {
                        if ans.typ == 28 {
                            if let Ok(ip) = ans.data.parse::<IpAddr>() {
                                ips.push(ip);
                            }
                        }
                    }
                }
            }
        }
        Ok(ips)
    }

    pub async fn is_available(&self) -> bool {
        self.resolve("example.com")
            .await
            .map(|v| !v.is_empty())
            .unwrap_or(false)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn doh_client_builds() {
        let c = DohClient::default();
        assert!(c.provider_url.contains("dns-query"));
    }
}
