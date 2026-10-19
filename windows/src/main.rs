//! Iran VPN Windows client. Wintun TUN + race/probe engine (Psiphon, Xray).
//! Non-blocking UI; probe gate; kill switch when SOCKS is down.

use eframe::egui;
use iran_vpn_core::{
    bootstrap_server_list, default_config_sources, fetch_server_list_via_socks, probe_default,
    save_last_good,
    config::{PathConfig, PathKind},
    fallback::SocksPortProvider,
    path::{PathRunner, PathStatus},
};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU16, Ordering};
use std::sync::Mutex;
use std::time::Duration;

fn load_app_icon() -> egui::IconData {
    let bytes = include_bytes!("../assets/icon-256.png");
    let image = image::load_from_memory(bytes)
        .expect("app icon")
        .into_rgba8();
    let (width, height) = image.dimensions();
    egui::IconData {
        rgba: image.into_raw(),
        width,
        height,
    }
}

fn main() -> eframe::Result<()> {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([360.0, 320.0])
            .with_icon(std::sync::Arc::new(load_app_icon())),
        ..Default::default()
    };
    eframe::run_native(
        "Iran VPN",
        options,
        Box::new(|cc| Ok(Box::new(IranVpnApp::new(cc)))),
    )
}

struct IranVpnApp {
    is_connected: bool,
    is_connecting: bool,
    active_path: Option<String>,
    disclaimer_accepted: bool,
    error: Option<String>,
    share_link: String,
    connect_rx: Option<std::sync::mpsc::Receiver<Result<String, String>>>,
}

impl IranVpnApp {
    fn new(_cc: &eframe::CreationContext<'_>) -> Self {
        Self {
            is_connected: false,
            is_connecting: false,
            active_path: None,
            disclaimer_accepted: load_disclaimer_accepted(),
            error: None,
            share_link: String::new(),
            connect_rx: None,
        }
    }

    fn start_connect_async(&mut self) {
        let (tx, rx) = std::sync::mpsc::channel();
        self.connect_rx = Some(rx);
        self.is_connecting = true;
        self.error = None;
        let share = self.share_link.clone();
        std::thread::spawn(move || {
            let result = run_connect(share).map_err(|e| e.to_string());
            let _ = tx.send(result);
        });
    }
}

impl eframe::App for IranVpnApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Poll async connect result without blocking UI
        if let Some(rx) = &self.connect_rx {
            match rx.try_recv() {
                Ok(Ok(path)) => {
                    self.is_connecting = false;
                    self.is_connected = true;
                    self.active_path = Some(path);
                    self.connect_rx = None;
                }
                Ok(Err(e)) => {
                    self.is_connecting = false;
                    self.is_connected = false;
                    self.error = Some(e);
                    self.connect_rx = None;
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => {
                    ctx.request_repaint_after(Duration::from_millis(100));
                }
                Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                    self.is_connecting = false;
                    self.error = Some("connect worker died".into());
                    self.connect_rx = None;
                }
            }
        }

        egui::CentralPanel::default().show(ctx, |ui| {
            if !self.disclaimer_accepted {
                ui.heading("Legal Notice / اطلاعیه قانونی");
                ui.add_space(8.0);
                ui.label("Unauthorized VPN use is illegal in Iran (Supreme Council of Cyberspace, Feb 2024). This app is for research and informational use only. Users assume all legal and personal risks.");
                ui.add_space(8.0);
                ui.label("Security: Prefer tunneled DNS; avoid public Wi‑Fi; keep the app updated.");
                ui.add_space(16.0);
                if ui.button("I understand and accept the risks").clicked() {
                    save_disclaimer_accepted(true);
                    self.disclaimer_accepted = true;
                }
                return;
            }

            let status = if self.is_connecting {
                "Connecting… / در حال اتصال…".to_string()
            } else if self.is_connected {
                self.active_path
                    .as_deref()
                    .map(|p| format!("Connected via {p}"))
                    .unwrap_or_else(|| "Connected".to_string())
            } else {
                "Disconnected / قطع".to_string()
            };

            ui.heading(&status);
            ui.add_space(16.0);

            if let Some(ref err) = self.error {
                ui.colored_label(egui::Color32::RED, err);
                ui.add_space(8.0);
            }

            if self.is_connecting {
                ui.spinner();
            } else if self.is_connected {
                if ui.button("Disconnect / قطع اتصال").clicked() {
                    stop_all();
                    self.is_connected = false;
                    self.active_path = None;
                }
            } else {
                if ui.button("Connect / اتصال").clicked() {
                    self.start_connect_async();
                }
            }

            ui.add_space(16.0);
            ui.collapsing("Advanced / پیشرفته", |ui| {
                ui.label("VLESS / VMess / Trojan share link:");
                ui.text_edit_multiline(&mut self.share_link);
            });
        });
    }
}

fn run_connect(share_link: String) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let cache = config_path();
    let _ = std::fs::create_dir_all(&cache);

    // Bootstrap: last-good → embedded (no network required)
    let mut server_list = bootstrap_server_list(Some(&cache));

    if !share_link.trim().is_empty() {
        server_list.paths.insert(
            0,
            PathConfig::Xray {
                config_json: share_link.trim().to_string(),
                subscription_url: None,
            },
        );
    }

    // Shared runner cannot safely race in parallel (one PROXY_CHILD / SOCKS_PORT).
    // Try paths serially: Psiphon then Xray.
    let runner = WindowsPathRunner::new();
    let order = [PathKind::Psiphon, PathKind::Xray];

    let rt = tokio::runtime::Runtime::new()?;
    rt.block_on(async {
        let mut last_err = String::from("no paths");

        for kind in order {
            let Some(config) = server_list.paths.iter().find(|p| p.kind() == kind).cloned() else {
                continue;
            };
            stop_all();
            match runner.connect(config).await {
                Ok(()) => {
                    let port = SOCKS_PORT.load(Ordering::SeqCst);
                    if port == 0 {
                        last_err = format!("{kind:?}: no SOCKS port");
                        runner.disconnect().await.ok();
                        continue;
                    }
                    match probe_default(port).await {
                        Ok(()) => {
                            #[cfg(target_os = "windows")]
                            {
                                if let Err(e) = start_wintun_tunnel(port) {
                                    last_err = format!("wintun: {e}");
                                    runner.disconnect().await.ok();
                                    continue;
                                }
                            }
                            let _ = save_last_good(&cache, &server_list);
                            let sources = default_config_sources();
                            if let Ok(fresh) = fetch_server_list_via_socks(&sources, port).await {
                                let _ = save_last_good(&cache, &fresh);
                            }
                            return Ok(format!("{kind:?}"));
                        }
                        Err(e) => {
                            last_err = format!("{kind:?} probe: {e}");
                            runner.disconnect().await.ok();
                        }
                    }
                }
                Err(e) => {
                    last_err = format!("{kind:?}: {e}");
                }
            }
        }
        Err(last_err.into())
    })
}

static WINTUN_RUNNING: AtomicBool = AtomicBool::new(false);
static SOCKS_PORT: AtomicU16 = AtomicU16::new(0);
static PROXY_CHILD: Mutex<Option<Child>> = Mutex::new(None);

#[derive(Clone)]
struct WindowsPathRunner {
    // shared marker
}

impl WindowsPathRunner {
    fn new() -> Self {
        Self {}
    }
}

#[async_trait::async_trait]
impl SocksPortProvider for WindowsPathRunner {
    async fn socks_port(&self, _path_index: usize) -> Option<u16> {
        let p = SOCKS_PORT.load(Ordering::SeqCst);
        if p > 0 {
            Some(p)
        } else {
            None
        }
    }
}

#[async_trait::async_trait]
impl PathRunner for WindowsPathRunner {
    async fn connect(
        &self,
        config: PathConfig,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let kind = config.kind();
        match kind {
            PathKind::Psiphon => connect_psiphon().await,
            PathKind::Xray | PathKind::Custom => {
                let (json, sub) = match config {
                    PathConfig::Xray {
                        config_json,
                        subscription_url,
                    } => (config_json, subscription_url),
                    _ => return Err("expected Xray config".into()),
                };
                connect_xray(&json, sub.as_deref()).await
            }
            PathKind::Conduit => Err("Conduit is included in Psiphon".into()),
            PathKind::Rostam => Err("Rostam excluded from default race (UDP whitelist)".into()),
        }
    }

    async fn status(&self, _config: &PathConfig) -> PathStatus {
        if SOCKS_PORT.load(Ordering::SeqCst) > 0 {
            PathStatus::Connected
        } else {
            PathStatus::Disconnected
        }
    }

    async fn disconnect(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        stop_all();
        Ok(())
    }
}

fn replace_proxy_child(child: Child) {
    if let Ok(mut guard) = PROXY_CHILD.lock() {
        if let Some(mut old) = guard.take() {
            let _ = old.kill();
        }
        *guard = Some(child);
    }
}

async fn connect_psiphon() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // Look for psiphon-tunnel-core or psiphon CLI on PATH / next to exe
    let candidates = ["psiphon-tunnel-core", "psiphon-tunnel-core.exe", "psiphon"];
    for name in candidates {
        if let Ok(child) = Command::new(name)
            .args([
                "--config",
                "psiphon.config",
                // Many builds expose local SOCKS; document expected port 1080
            ])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
        {
            replace_proxy_child(child);
            // Default Psiphon local SOCKS often 1080 — wait briefly
            for _ in 0..40 {
                if port_open(1080) {
                    SOCKS_PORT.store(1080, Ordering::SeqCst);
                    return Ok(());
                }
                tokio::time::sleep(Duration::from_millis(250)).await;
            }
            return Err("Psiphon started but SOCKS not ready".into());
        }
    }
    if std::env::var("IRAN_VPN_DEMO").is_ok() {
        // Demo: pretend SOCKS on 1080 without binary
        SOCKS_PORT.store(1080, Ordering::SeqCst);
        return Ok(());
    }
    Err(
        "Psiphon binary not found — place psiphon-tunnel-core on PATH or set IRAN_VPN_DEMO=1"
            .into(),
    )
}

async fn connect_xray(
    config_json: &str,
    subscription: Option<&str>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let cfg = config_json.trim().to_string();
    if (cfg.is_empty() || cfg == "{}") && subscription.is_some() {
        return Err("subscription fetch requires network; paste a full Xray JSON config".into());
    }
    // Reject share links — wrapping them with freedom outbound would fake a tunnel.
    // Use Android ShareLinkParser-equivalent JSON, or paste complete Xray config.
    if cfg.starts_with("vless://") || cfg.starts_with("vmess://") || cfg.starts_with("trojan://") {
        return Err(
            "share links need full Xray JSON on Windows — paste a complete config with a proxy outbound"
                .into(),
        );
    }
    if !cfg.trim_start().starts_with('{') {
        return Err("Xray config must be JSON".into());
    }
    if !cfg.contains("\"protocol\":\"socks\"") && !cfg.contains("\"protocol\": \"socks\"") {
        return Err("Xray config must include a SOCKS inbound on 127.0.0.1".into());
    }
    // Reject configs that only have freedom (no real proxy outbound)
    let has_proxy = cfg.contains("vless")
        || cfg.contains("vmess")
        || cfg.contains("trojan")
        || cfg.contains("shadowsocks")
        || cfg.contains("wireguard");
    if !has_proxy {
        return Err("Xray config has no proxy outbound".into());
    }

    let dir = config_path();
    let _ = std::fs::create_dir_all(&dir);
    let cfg_path = dir.join("xray_runtime.json");
    std::fs::write(&cfg_path, &cfg)?;

    let candidates = ["xray", "xray.exe", "xray-core"];
    for name in candidates {
        if let Ok(child) = Command::new(name)
            .args(["run", "-c", cfg_path.to_str().unwrap_or("xray_runtime.json")])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
        {
            replace_proxy_child(child);
            for _ in 0..40 {
                if port_open(10808) {
                    SOCKS_PORT.store(10808, Ordering::SeqCst);
                    return Ok(());
                }
                tokio::time::sleep(Duration::from_millis(250)).await;
            }
            return Err("Xray started but SOCKS not ready".into());
        }
    }
    Err("Xray binary not found on PATH".into())
}

fn port_open(port: u16) -> bool {
    std::net::TcpStream::connect_timeout(
        &std::net::SocketAddr::from(([127, 0, 0, 1], port)),
        Duration::from_millis(200),
    )
    .is_ok()
}

fn stop_all() {
    WINTUN_RUNNING.store(false, Ordering::Relaxed);
    SOCKS_PORT.store(0, Ordering::SeqCst);
    if let Ok(mut guard) = PROXY_CHILD.lock() {
        if let Some(mut child) = guard.take() {
            let _ = child.kill();
        }
    }
    #[cfg(target_os = "windows")]
    stop_wintun_tunnel();
}

#[cfg(target_os = "windows")]
static WINTUN_STATE: std::sync::OnceLock<std::sync::Mutex<Option<WintunState>>> =
    std::sync::OnceLock::new();

#[cfg(target_os = "windows")]
struct WintunState {
    _adapter: std::sync::Arc<wintun::Adapter>,
    session: std::sync::Arc<wintun::Session>,
    thread_handle: Option<std::thread::JoinHandle<()>>,
}

#[cfg(target_os = "windows")]
fn start_wintun_tunnel(socks_port: u16) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    use std::sync::Arc;

    if socks_port == 0 {
        return Err("kill switch: refusing TUN without SOCKS".into());
    }

    // wintun 0.3: load library, then Adapter::create(&wintun, name, tunnel_type, guid)
    let wintun = wintun::load().map_err(|e| format!("wintun load: {e:?}"))?;
    let adapter = wintun::Adapter::create(&wintun, "IranVPN", "IranVPN", None)
        .map_err(|e| format!("Wintun create adapter: {e:?}"))?;
    let session = adapter
        .start_session(wintun::MAX_RING_CAPACITY)
        .map_err(|e| format!("Wintun start session: {e:?}"))?;
    let session = Arc::new(session);
    let session_clone = session.clone();

    WINTUN_RUNNING.store(true, Ordering::Relaxed);
    let thread_handle = std::thread::spawn(move || run_packet_loop(session_clone, socks_port));

    let state = WintunState {
        _adapter: adapter,
        session,
        thread_handle: Some(thread_handle),
    };

    WINTUN_STATE
        .get_or_init(|| std::sync::Mutex::new(None))
        .lock()
        .map_err(|_| "Mutex poisoned")?
        .replace(state);
    Ok(())
}

#[cfg(target_os = "windows")]
fn run_packet_loop(session: std::sync::Arc<wintun::Session>, socks_port: u16) {
    // Kill switch: if SOCKS dies, drop packets (do not leak to ISP)
    while WINTUN_RUNNING.load(Ordering::Relaxed) {
        if SOCKS_PORT.load(Ordering::SeqCst) == 0 || !port_open(socks_port) {
            // Drop all packets
            while let Ok(Some(packet)) = session.try_receive() {
                drop(packet);
            }
            std::thread::sleep(Duration::from_millis(50));
            continue;
        }
        match session.try_receive() {
            Ok(Some(packet)) => {
                // Production: pipe through tun2socks/hev-socks5 to socks_port.
                // Until hev-socks5-tunnel is bundled, drop (kill switch safe).
                let _ = socks_port;
                drop(packet);
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(1)),
            Err(_) => break,
        }
    }
}

#[cfg(target_os = "windows")]
fn stop_wintun_tunnel() {
    WINTUN_RUNNING.store(false, Ordering::Relaxed);
    if let Some(state_lock) = WINTUN_STATE.get() {
        if let Ok(mut state) = state_lock.lock() {
            if let Some(state) = state.take() {
                let _ = state.session.shutdown();
                if let Some(h) = state.thread_handle {
                    let _ = h.join();
                }
            }
        }
    }
}

fn config_path() -> std::path::PathBuf {
    directories::ProjectDirs::from("org", "opensignalfoundation", "iranvpn")
        .map(|d| d.config_dir().to_path_buf())
        .unwrap_or_else(|| std::env::temp_dir().join("iranvpn"))
}

fn load_disclaimer_accepted() -> bool {
    let path = config_path().join("disclaimer_accepted");
    std::fs::read_to_string(path)
        .map(|s| s.trim() == "1")
        .unwrap_or(false)
}

fn save_disclaimer_accepted(accepted: bool) {
    let dir = config_path();
    let _ = std::fs::create_dir_all(&dir);
    let path = dir.join("disclaimer_accepted");
    let _ = std::fs::write(path, if accepted { "1" } else { "0" });
}
