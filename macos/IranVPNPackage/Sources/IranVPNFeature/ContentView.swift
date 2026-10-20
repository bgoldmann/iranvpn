import SwiftUI

/// US-001: Legal gate, then three-tab shell (Connect · Paths · About).
public struct ContentView: View {
    @AppStorage("disclaimerAccepted") private var disclaimerAccepted = false
    @State private var vpn = VpnController()

    public init() {}

    public var body: some View {
        Group {
            if !disclaimerAccepted {
                LegalDisclaimerView(onAccept: { disclaimerAccepted = true })
            } else {
                MainShellView(vpn: vpn)
            }
        }
        .frame(minWidth: 420, minHeight: 480)
        .task { await vpn.refreshStatus() }
    }
}

struct LegalDisclaimerView: View {
    let onAccept: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Iran VPN")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppTheme.primary)
                Text("ایران وی‌پی‌ان")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                Text("اطلاعیه قانونی / Legal Notice")
                    .font(.headline)
                Text("Unauthorized VPN use is illegal in Iran (Supreme Council of Cyberspace, Feb 2024). This app is for research and informational use only. Users assume all legal and personal risks.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text("Security: Prefer tunneled DNS; avoid public Wi-Fi; keep updated.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button(action: onAccept) {
                    Text("می‌پذیرم / I understand and accept the risks")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
            }
            .padding(28)
        }
        .iranVpnAtmosphere()
    }
}

struct MainShellView: View {
    @Bindable var vpn: VpnController

    var body: some View {
        TabView {
            ConnectTab(vpn: vpn)
                .tabItem { Label("اتصال / Connect", systemImage: "network") }
            PathsTab()
                .tabItem { Label("مسیرها / Paths", systemImage: "arrow.triangle.branch") }
            AboutTab()
                .tabItem { Label("درباره / About", systemImage: "info.circle") }
        }
        .tint(AppTheme.primary)
    }
}

struct ConnectTab: View {
    @Bindable var vpn: VpnController

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 16)
            VStack(spacing: 4) {
                Text("Iran VPN")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primary)
                Text("ایران وی‌پی‌ان")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
            }

            StatusRing(vpn: vpn)
                .animation(.easeInOut(duration: 0.35), value: vpn.isConnected)

            if let path = vpn.activePath, vpn.isConnected {
                Text("via \(path)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }

            if vpn.isConnecting {
                ProgressView()
                Button("لغو / Cancel") {
                    Task { await vpn.disconnect() }
                }
            } else if vpn.isConnected {
                Button("قطع اتصال / Disconnect") {
                    Task { await vpn.disconnect() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.danger)
            } else {
                Button("اتصال / Connect") {
                    Task { await vpn.connect() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .controlSize(.large)
            }

            if let err = vpn.errorMessage {
                Text(err).foregroundStyle(AppTheme.danger).font(.caption)
            }

            Spacer()
            Text("macOS: Psiphon path · Conduit on hold")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .padding(24)
        .iranVpnAtmosphere()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StatusRing: View {
    @Bindable var vpn: VpnController

    private var ringColor: Color {
        if vpn.isConnecting { return AppTheme.accent }
        if vpn.isConnected { return AppTheme.primary }
        return Color.secondary.opacity(0.35)
    }

    private var label: String {
        if vpn.isConnecting { return "در حال اتصال…\nConnecting…" }
        if vpn.isConnected { return "متصل\nConnected" }
        return "قطع\nDisconnected"
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ringColor.opacity(0.25), lineWidth: 10)
                .frame(width: 132, height: 132)
            Circle()
                .trim(from: 0, to: vpn.isConnected ? 1 : (vpn.isConnecting ? 0.65 : 0.2))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 132, height: 132)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.primary)
        }
    }
}

struct PathsTab: View {
    @AppStorage("conduitPersonalCompartment") private var conduitCompartment = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("مسیرها / Paths")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.primary)

                Text("Conduit")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primary)
                Text("Stored for when Psiphon keys arrive. Tunnel injects InproxyClientPersonalCompartmentID.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Conduit personal code (optional)", text: $conduitCompartment)
                    .textFieldStyle(.roundedBorder)

                Divider()

                Text("Providers")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primary)
                Text("macOS is Psiphon-only for system VPN today. Xray / Outline need a second Packet Tunnel appex (iOS already has it). Hy2 / Tor / sing-box: use Android or Windows.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 520, alignment: .leading)
        }
        .iranVpnAtmosphere()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AboutTab: View {
    @State private var showLegal = false

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Iran VPN")
                    .font(.title.weight(.bold))
                    .foregroundStyle(AppTheme.primary)
                Text("ایران وی‌پی‌ان")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
                Text("Open circumvention client. Research and informational use only.")
                    .foregroundStyle(.secondary)
                Text("Security tips")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primary)
                Text("• Prefer tunneled DNS\n• Avoid untrusted public Wi‑Fi\n• Keep the app updated\n• Conduit on hold (Psiphon keys)")
                    .foregroundStyle(.secondary)
                Button("Show legal notice") { showLegal = true }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.primary)

                Divider()

                Text("Developed by Goldmann LLC")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
                Link("goldmannllc.com/websites/iranvpn", destination: URL(string: "https://goldmannllc.com/websites/iranvpn")!)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.accent)
                Link("Support / پشتیبانی", destination: URL(string: "https://goldmannllc.com/contact")!)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.accent)
                Text("support@goldmannllc.com")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Version \(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 520, alignment: .leading)
        }
        .iranVpnAtmosphere()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showLegal) {
            LegalDisclaimerView(onAccept: { showLegal = false })
                .frame(minWidth: 400, minHeight: 360)
        }
    }
}

#Preview {
    ContentView()
}
