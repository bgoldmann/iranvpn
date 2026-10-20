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

fn brand_visuals() -> egui::Visuals {
    let mut v = egui::Visuals::light();
    let teal = egui::Color32::from_rgb(0x0B, 0x3D, 0x3A);
    let gold = egui::Color32::from_rgb(0xC4, 0xA5, 0x74);
    let mist = egui::Color32::from_rgb(0xF1, 0xF4, 0xF5);
    v.override_text_color = Some(teal);
    v.widgets.inactive.bg_fill = mist;
    v.widgets.hovered.bg_fill = egui::Color32::from_rgb(0xDB, 0xEE, 0xEB);
    v.widgets.active.bg_fill = teal;
    v.widgets.active.fg_stroke = egui::Stroke::new(1.0, egui::Color32::WHITE);
    v.selection.bg_fill = gold;
    v.panel_fill = mist;
    v.window_fill = mist;
    v.extreme_bg_color = egui::Color32::from_rgb(0xDB, 0xEE, 0xEB);
    v.hyperlink_color = teal;
    v
}

fn main() -> eframe::Result<()> {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([440.0, 520.0])
            .with_icon(std::sync::Arc::new(load_app_icon())),
        ..Default::default()
    };
    eframe::run_native(
        "Iran VPN",
        options,
        Box::new(|cc| Ok(Box::new(IranVpnApp::new(cc)))),
    )
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum AppTab {
    Connect,
    Paths,
    About,
}

struct IranVpnApp {
    is_connected: bool,
    is_connecting: bool,
    active_path: Option<String>,
    disclaimer_accepted: bool,
    error: Option<String>,
    share_link: String,
    tab: AppTab,
    connect_rx: Option<std::sync::mpsc::Receiver<Result<String, String>>>,
}

impl IranVpnApp {
    fn new(cc: &eframe::CreationContext<'_>) -> Self {
        cc.egui_ctx.set_visuals(brand_visuals());
        Self {
            is_connected: false,
            is_connecting: false,
            active_path: None,
            disclaimer_accepted: load_disclaimer_accepted(),
            error: None,
            share_link: String::new(),
            tab: AppTab::Connect,
            connect_rx: None,
        }
    }

    fn start_connect_async(&mut self) {
        // Drop any prior in-flight connect so Disconnect → Connect always works.
        stop_all();
        let (tx, rx) = std::sync::mpsc::channel();
        self.connect_rx = Some(rx);
        self.is_connecting = true;
        self.is_connected = false;
        self.active_path = None;
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

        let teal = egui::Color32::from_rgb(0x0B, 0x3D, 0x3A);
        let gold = egui::Color32::from_rgb(0xC4, 0xA5, 0x74);

        egui::CentralPanel::default().show(ctx, |ui| {
            if !self.disclaimer_accepted {
                ui.vertical_centered(|ui| {
                    ui.add_space(24.0);
                    ui.heading(
                        egui::RichText::new("Iran VPN")
                            .color(teal)
                            .size(28.0)
                            .strong(),
                    );
                    ui.label(egui::RichText::new("ایران وی‌پی‌ان").color(gold).size(18.0));
                    ui.add_space(12.0);
                    ui.heading("Legal Notice / اطلاعیه قانونی");
                    ui.add_space(8.0);
                    ui.label("Unauthorized VPN use is illegal in Iran (Supreme Council of Cyberspace, Feb 2024). This app is for research and informational use only. Users assume all legal and personal risks.");
                    ui.add_space(8.0);
                    ui.label("Security: Prefer tunneled DNS; avoid public Wi‑Fi; keep the app updated.");
                    ui.add_space(16.0);
                    if ui
                        .add(egui::Button::new("می‌پذیرم / I understand and accept the risks").fill(teal))
                        .clicked()
                    {
                        save_disclaimer_accepted(true);
                        self.disclaimer_accepted = true;
                    }
                });
                return;
            }

            ui.horizontal(|ui| {
                for (tab, label) in [
                    (AppTab::Connect, "اتصال / Connect"),
                    (AppTab::Paths, "مسیرها / Paths"),
                    (AppTab::About, "درباره / About"),
                ] {
                    let selected = self.tab == tab;
                    let text = if selected {
                        egui::RichText::new(label).color(teal).strong()
                    } else {
                        egui::RichText::new(label).color(teal.gamma_multiply(0.55))
                    };
                    if ui
                        .selectable_label(selected, text)
                        .clicked()
                    {
                        self.tab = tab;
                    }
                    ui.add_space(8.0);
                }
            });
            ui.separator();
            ui.add_space(8.0);

            match self.tab {
                AppTab::Connect => self.ui_connect_tab(ui, teal, gold),
                AppTab::Paths => self.ui_paths_tab(ui, teal),
                AppTab::About => self.ui_about_tab(ui, teal, gold),
            }
        });
    }
}

impl IranVpnApp {
    fn ui_connect_tab(&mut self, ui: &mut egui::Ui, teal: egui::Color32, gold: egui::Color32) {
        ui.vertical_centered(|ui| {
            ui.heading(
                egui::RichText::new("Iran VPN")
                    .color(teal)
                    .size(28.0)
                    .strong(),
            );
            ui.label(egui::RichText::new("ایران وی‌پی‌ان").color(gold).size(16.0));
            ui.add_space(16.0);

            let status = if self.is_connecting {
                "در حال اتصال… / Connecting…"
            } else if self.is_connected {
                "متصل / Connected"
            } else {
                "قطع / Disconnected"
            };
            ui.label(egui::RichText::new(status).color(teal).size(18.0).strong());

            if self.is_connected {
                if let Some(ref path) = self.active_path {
                    let caption = if path.contains("system TUN not") {
                        format!("Local SOCKS ready — {path}")
                    } else {
                        format!("via {path}")
                    };
                    ui.label(egui::RichText::new(caption).color(gold));
                }
            }

            ui.add_space(16.0);
            if let Some(ref err) = self.error {
                ui.colored_label(egui::Color32::from_rgb(0xBF, 0x38, 0x33), err);
                ui.add_space(8.0);
            }

            if self.is_connecting {
                ui.spinner();
                if ui.button("Cancel / لغو").clicked() {
                    stop_all();
                    self.connect_rx = None;
                    self.is_connecting = false;
                    self.is_connected = false;
                    self.active_path = None;
                    self.error = None;
                }
            } else if self.is_connected {
                if ui
                    .add(
                        egui::Button::new("Disconnect / قطع اتصال")
                            .fill(egui::Color32::from_rgb(0xBF, 0x38, 0x33)),
                    )
                    .clicked()
                {
                    stop_all();
                    self.connect_rx = None;
                    self.is_connected = false;
                    self.is_connecting = false;
                    self.active_path = None;
                    self.error = None;
                }
            } else if ui
                .add(egui::Button::new("Connect / اتصال").fill(teal).min_size([180.0, 36.0].into()))
                .clicked()
            {
                self.start_connect_async();
            }

            ui.add_space(24.0);
            ui.label(
                egui::RichText::new("Default: Psiphon · Conduit on hold")
                    .color(teal.gamma_multiply(0.55))
                    .small(),
            );
        });
    }

    fn ui_paths_tab(&mut self, ui: &mut egui::Ui, teal: egui::Color32) {
        ui.heading(egui::RichText::new("مسیرها / Paths").color(teal));
        ui.add_space(8.0);
        ui.label("Share link (vless / vmess / trojan / ss:// / hy2 / sing-box JSON). Requires binaries on PATH.");
        ui.add_space(6.0);
        ui.add(
            egui::TextEdit::multiline(&mut self.share_link)
                .desired_width(f32::INFINITY)
                .desired_rows(5),
        );
        ui.add_space(8.0);
        ui.label(
            egui::RichText::new("Imported links are tried after Psiphon when xray / sing-box / tor are available.")
                .small()
                .color(teal.gamma_multiply(0.6)),
        );
    }

    fn ui_about_tab(&mut self, ui: &mut egui::Ui, teal: egui::Color32, gold: egui::Color32) {
        ui.heading(egui::RichText::new("Iran VPN").color(teal).strong());
        ui.label(egui::RichText::new("ایران وی‌پی‌ان").color(gold));
        ui.add_space(8.0);
        ui.label("Open circumvention client that races FOSS paths (Psiphon first). Research and informational use only.");
        ui.add_space(12.0);
        ui.label(egui::RichText::new("Security tips").color(teal).strong());
        ui.label("• Prefer tunneled DNS");
        ui.label("• Avoid untrusted public Wi‑Fi");
        ui.label("• Keep the app updated");
        ui.label("• Conduit / in-proxy on hold until Psiphon keys arrive");
        ui.add_space(12.0);
        ui.label(
            egui::RichText::new(
                "Unauthorized VPN use is illegal in Iran (SCC, Feb 2024). Users assume all risks.",
            )
            .small()
            .color(teal.gamma_multiply(0.55)),
        );
        ui.add_space(12.0);
        ui.label(egui::RichText::new("Developed by Goldmann LLC").color(teal).strong());
        ui.hyperlink_to(
            "goldmannllc.com/websites/iranvpn",
            "https://goldmannllc.com/websites/iranvpn",
        );
        ui.hyperlink_to("Support / پشتیبانی", "https://goldmannllc.com/contact");
        ui.label(
            egui::RichText::new("support@goldmannllc.com")
                .small()
                .color(teal.gamma_multiply(0.55)),
        );
        ui.add_space(8.0);
        ui.label(egui::RichText::new("Version 0.1.0").color(gold).small());
    }
}

fn which_bin(name: &str) -> bool {
    // Binary exists if the OS can spawn it (exit code may still be non-zero).
    Command::new(name)
        .arg("--version")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .is_ok()
}

fn run_connect(share_link: String) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let cache = config_path();
    let _ = std::fs::create_dir_all(&cache);

    // Bootstrap: last-good → embedded (no network required)
    let mut server_list = bootstrap_server_list(Some(&cache));

    let trimmed = share_link.trim().to_string();
    if !trimmed.is_empty() {
        let path = if trimmed.starts_with("ss://") || trimmed.starts_with("SS://") {
            PathConfig::Outline {
                access_key: trimmed,
            }
        } else if trimmed.starts_with("hy2://") || trimmed.starts_with("hysteria2://") {
            PathConfig::SingBox {
                config_json: trimmed,
                subscription_url: None,
            }
        } else if trimmed.starts_with('{')
            && (trimmed.contains("\"hysteria2\"")
                || trimmed.contains("\"listen_port\"")
                || trimmed.contains("\"type\": \"socks\""))
        {
            PathConfig::SingBox {
                config_json: trimmed.clone(),
                subscription_url: None,
            }
        } else {
            PathConfig::Xray {
                config_json: trimmed,
                subscription_url: None,
            }
        };
        // Prefer imported path right after Psiphon in the list.
        server_list.paths.insert(1.min(server_list.paths.len()), path);
    }

    // Shared runner cannot safely race in parallel (one PROXY_CHILD / SOCKS_PORT).
    // Conduit on hold (awaiting Psiphon keys). Order matches core/Android DEFAULT_PATH_ORDER.
    let runner = WindowsPathRunner::new();
    let xray_on_path = ["xray", "xray.exe", "xray-core"]
        .iter()
        .any(|bin| which_bin(bin));
    let singbox_on_path = ["sing-box", "sing-box.exe"].iter().any(|bin| which_bin(bin));
    let tor_on_path = ["tor", "tor.exe"].iter().any(|bin| which_bin(bin));
    let mut order: Vec<PathKind> = vec![PathKind::Psiphon];
    if xray_on_path {
        order.push(PathKind::Xray);
    }
    if singbox_on_path {
        order.push(PathKind::SingBox);
    }
    if tor_on_path {
        order.push(PathKind::Tor);
    }
    if singbox_on_path {
        order.push(PathKind::Outline);
    }

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
                            // Do NOT bring up Wintun until tun2socks/hev-socks5 is bundled.
                            // A TUN that only drops packets blackholes the OS — worse than no VPN.
                            #[cfg(target_os = "windows")]
                            {
                                let _ = port; // local SOCKS is up for probe/config refresh
                            }
                            let _ = save_last_good(&cache, &server_list);
                            let sources = default_config_sources();
                            if let Ok(fresh) = fetch_server_list_via_socks(&sources, port).await {
                                let _ = save_last_good(&cache, &fresh);
                            }
                            return Ok(format!(
                                "{kind:?} (local SOCKS :{port}; system TUN not bundled yet)"
                            ));
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
            PathKind::Conduit => Err(
                "Conduit is included in Psiphon — set InproxyClientPersonalCompartmentID in psiphon.config"
                    .into(),
            ),
            PathKind::SingBox => {
                let (json, _) = match config {
                    PathConfig::SingBox {
                        config_json,
                        subscription_url,
                    } => (config_json, subscription_url),
                    _ => return Err("expected SingBox config".into()),
                };
                connect_singbox(&json).await
            }
            PathKind::Outline => {
                let key = match config {
                    PathConfig::Outline { access_key } => access_key,
                    _ => return Err("expected Outline config".into()),
                };
                connect_outline_ss(&key).await
            }
            PathKind::Tor => connect_tor_socks().await,
            PathKind::AmneziaWg => Err("AmneziaWG Advanced-only".into()),
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

fn resolve_psiphon_config() -> Option<std::path::PathBuf> {
    let mut candidates = Vec::new();
    if let Ok(p) = std::env::var("IRAN_VPN_PSIPHON_CONFIG") {
        candidates.push(std::path::PathBuf::from(p));
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            candidates.push(dir.join("psiphon").join("psiphon.config"));
            candidates.push(dir.join("psiphon.config"));
        }
    }
    candidates.push(std::path::PathBuf::from("psiphon/psiphon.config"));
    candidates.push(std::path::PathBuf::from("psiphon.config"));
    // Repo layout when running from `windows/` or workspace root.
    candidates.push(std::path::PathBuf::from("windows/psiphon/psiphon.config"));
    candidates
        .into_iter()
        .find(|p| p.is_file())
}

async fn connect_psiphon() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let config_path = resolve_psiphon_config().ok_or(
        "psiphon.config not found — expected windows/psiphon/psiphon.config (or IRAN_VPN_PSIPHON_CONFIG)",
    )?;
    let config_arg = config_path.to_string_lossy().into_owned();
    // Look for psiphon-tunnel-core or psiphon CLI on PATH / next to exe
    let candidates = ["psiphon-tunnel-core", "psiphon-tunnel-core.exe", "psiphon"];
    for name in candidates {
        if let Ok(child) = Command::new(name)
            .args(["--config", &config_arg])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
        {
            replace_proxy_child(child);
            // Bundled config sets LocalSocksProxyPort=1080
            for _ in 0..80 {
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
        SOCKS_PORT.store(1080, Ordering::SeqCst);
        return Ok(());
    }
    Err(
        "Psiphon binary not found — place psiphon-tunnel-core on PATH or set IRAN_VPN_DEMO=1"
            .into(),
    )
}

async fn await_socks(port: u16, attempts: u32) -> bool {
    for _ in 0..attempts {
        if port_open(port) {
            SOCKS_PORT.store(port, Ordering::SeqCst);
            return true;
        }
        tokio::time::sleep(Duration::from_millis(250)).await;
    }
    false
}

async fn connect_singbox(config_json: &str) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let port = 10809u16;
    let json = config_json.trim().to_string();
    if json.starts_with("hy2://") || json.starts_with("hysteria2://") {
        return Err("paste full sing-box JSON for Hy2 on Windows, or use Android hy2:// parser".into());
    }
    if !json.contains("\"socks\"") && !json.contains("listen_port") {
        return Err("sing-box config needs a socks inbound".into());
    }
    let dir = std::env::temp_dir().join("iranvpn-singbox");
    let _ = std::fs::create_dir_all(&dir);
    let cfg = dir.join("config.json");
    std::fs::write(&cfg, &json)?;
    for name in ["sing-box", "sing-box.exe"] {
        if let Ok(child) = Command::new(name)
            .args(["run", "-c", cfg.to_string_lossy().as_ref()])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
        {
            replace_proxy_child(child);
            if await_socks(port, 40).await {
                return Ok(());
            }
            return Err("sing-box started but SOCKS not ready".into());
        }
    }
    Err("sing-box not found on PATH".into())
}

async fn connect_outline_ss(access_key: &str) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let port = 10810u16;
    let json = singbox_json_from_ss(access_key, port)
        .ok_or("Could not parse Outline ss:// access key")?;
    let dir = std::env::temp_dir().join("iranvpn-outline");
    let _ = std::fs::create_dir_all(&dir);
    let cfg = dir.join("config.json");
    std::fs::write(&cfg, &json)?;
    for name in ["sing-box", "sing-box.exe"] {
        if let Ok(child) = Command::new(name)
            .args(["run", "-c", cfg.to_string_lossy().as_ref()])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
        {
            replace_proxy_child(child);
            if await_socks(port, 40).await {
                return Ok(());
            }
            return Err("outline/sing-box started but SOCKS not ready".into());
        }
    }
    Err("sing-box not found on PATH (required for Outline ss://)".into())
}

/// SIP002 / legacy `ss://` → minimal sing-box socks+shadowsocks JSON (mirrors Android OutlinePathRunner).
fn singbox_json_from_ss(ss_uri: &str, socks_port: u16) -> Option<String> {
    let raw = ss_uri
        .trim()
        .strip_prefix("ss://")
        .or_else(|| ss_uri.trim().strip_prefix("SS://"))?
        .split('#')
        .next()?;
    let (method, password, host, port) = if let Some(at) = raw.rfind('@') {
        let user_b64 = &raw[..at];
        let mut host_port = &raw[at + 1..];
        if let Some(q) = host_port.find('?') {
            host_port = &host_port[..q];
        }
        let decoded = decode_b64_utf8(user_b64)?;
        let colon = decoded.find(':')?;
        let method = decoded[..colon].to_string();
        let password = decoded[colon + 1..].to_string();
        let (host, port) = split_host_port(host_port)?;
        (method, password, host, port)
    } else {
        let decoded = decode_b64_utf8(raw)?;
        let at = decoded.rfind('@')?;
        let user = &decoded[..at];
        let mut host_port = &decoded[at + 1..];
        if let Some(q) = host_port.find('?') {
            host_port = &host_port[..q];
        }
        let colon = user.find(':')?;
        let method = user[..colon].to_string();
        let password = user[colon + 1..].to_string();
        let (host, port) = split_host_port(host_port)?;
        (method, password, host, port)
    };
    let root = serde_json::json!({
        "inbounds": [{
            "type": "socks",
            "tag": "socks-in",
            "listen": "127.0.0.1",
            "listen_port": socks_port,
        }],
        "outbounds": [{
            "type": "shadowsocks",
            "tag": "proxy",
            "server": host,
            "server_port": port,
            "method": method,
            "password": password,
        }],
    });
    Some(root.to_string())
}

fn split_host_port(host_port: &str) -> Option<(String, u16)> {
    if let Some(rest) = host_port.strip_prefix('[') {
        let end = rest.find(']')?;
        let host = rest[..end].to_string();
        let after = &rest[end + 1..];
        let port: u16 = after.strip_prefix(':')?.parse().ok()?;
        return Some((host, port));
    }
    let colon = host_port.rfind(':')?;
    let host = host_port[..colon].to_string();
    let port: u16 = host_port[colon + 1..].parse().ok()?;
    Some((host, port))
}

fn decode_b64_utf8(s: &str) -> Option<String> {
    use base64::Engine;
    let normalized = s.replace('-', "+").replace('_', "/");
    let pad = (4 - (normalized.len() % 4)) % 4;
    let padded = format!("{}{}", normalized, "=".repeat(pad));
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(padded.as_bytes())
        .ok()?;
    String::from_utf8(bytes).ok()
}

async fn connect_tor_socks() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // Use existing Tor SOCKS (9050) if already running; else spawn tor.
    if await_socks(9050, 4).await {
        return Ok(());
    }
    for name in ["tor", "tor.exe"] {
        if let Ok(child) = Command::new(name)
            .args(["--SocksPort", "9050"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
        {
            replace_proxy_child(child);
            if await_socks(9050, 80).await {
                return Ok(());
            }
            return Err("tor started but SOCKS :9050 not ready".into());
        }
    }
    Err("tor not found on PATH — install Tor Expert Bundle".into())
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
