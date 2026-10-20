import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// US-001 / US-008: Legal gate, then three-tab shell (Connect · Paths · About).
public struct ContentView: View {
    @AppStorage("disclaimerAccepted") private var disclaimerAccepted = false
    @State private var vpn = VpnController()
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        Group {
            if !disclaimerAccepted {
                LegalDisclaimerView(onAccept: { disclaimerAccepted = true })
            } else {
                MainShellView(vpn: vpn)
            }
        }
        .task {
            await vpn.refreshStatus()
        }
        // Dismiss remote keyboard when backgrounding — reduces Simulator XPC / background-task noise.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                resignKeyboard()
            }
        }
    }
}

@MainActor
func resignKeyboard() {
#if canImport(UIKit)
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
#endif
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
                    .fontWeight(.semibold)
                Text("Unauthorized VPN use is illegal in Iran (Supreme Council of Cyberspace, Feb 2024). This app is for research and informational use only. Users assume all legal and personal risks. We do not encourage illegal activity.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text("Security: Prefer tunneled DNS; avoid public Wi-Fi; keep the app updated.")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MainShellView: View {
    @Bindable var vpn: VpnController
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            ConnectTab(vpn: vpn)
                .tabItem { Label("اتصال / Connect", systemImage: "network") }
                .tag(0)
            PathsTab(vpn: vpn)
                .tabItem { Label("مسیرها / Paths", systemImage: "arrow.triangle.branch") }
                .tag(1)
            AboutTab()
                .tabItem { Label("درباره / About", systemImage: "info.circle") }
                .tag(2)
        }
        .tint(AppTheme.primary)
        .onChange(of: tab) { _, _ in resignKeyboard() }
    }
}

struct ConnectTab: View {
    @Bindable var vpn: VpnController

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 24)
            VStack(spacing: 6) {
                Text("Iran VPN")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primary)
                Text("ایران وی‌پی‌ان")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(AppTheme.accent)
            }
            .accessibilityAddTraits(.isHeader)

            StatusRing(vpn: vpn)
                .animation(.easeInOut(duration: 0.35), value: vpn.isConnected)
                .animation(.easeInOut(duration: 0.35), value: vpn.isConnecting)

            if let path = vpn.activePath, vpn.isConnected {
                Text("via \(path)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }

            connectControls

            if let err = vpn.errorMessage {
                Text(err)
                    .foregroundStyle(AppTheme.danger)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
            Text("Default path: Psiphon · Conduit on hold")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .iranVpnAtmosphere()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var connectControls: some View {
        if vpn.isConnecting {
            ProgressView()
                .controlSize(.large)
                .tint(AppTheme.primary)
            Button("لغو / Cancel") {
                resignKeyboard()
                Task { await vpn.disconnect() }
            }
            .buttonStyle(.bordered)
        } else if vpn.isConnected {
            Button {
                resignKeyboard()
                Task { await vpn.disconnect() }
            } label: {
                Text("قطع اتصال / Disconnect")
                    .font(.headline)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.danger)
            .scaleEffect(1)
        } else {
            Button {
                resignKeyboard()
                Task { await vpn.connect() }
            } label: {
                Text("اتصال / Connect")
                    .font(.headline)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primary)
        }
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
                .frame(width: 148, height: 148)
            Circle()
                .trim(from: 0, to: vpn.isConnected ? 1 : (vpn.isConnecting ? 0.65 : 0.2))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 148, height: 148)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.primary)
        }
    }
}

struct PathsTab: View {
    @Bindable var vpn: VpnController
    @State private var shareLink = ""
    @AppStorage("conduitPersonalCompartment") private var conduitCompartment = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sectionTitle("Conduit")
                    Text("Personal code pairs Psiphon in-proxy to your stations when distributor keys arrive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Conduit personal code (optional)", text: $conduitCompartment)
                        .textFieldStyle(.roundedBorder)
                        .disabled(vpn.isConnected || vpn.isConnecting)

                    Divider()

                    sectionTitle("Share link")
                    if vpn.xrayExtensionAvailable {
                        Text("vless:// · vmess:// · trojan:// · ss:// (Outline)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Paste share link", text: $shareLink, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                            .disabled(vpn.isConnected || vpn.isConnecting)
                        Button("Import share link") {
                            vpn.importedShareLink = shareLink.trimmingCharacters(in: .whitespacesAndNewlines)
                            shareLink = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.primary)
                        .disabled(shareLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || vpn.isConnected || vpn.isConnecting)
                        if let active = vpn.importedShareLink, !active.isEmpty {
                            Text("Imported — Connect uses Xray extension")
                                .font(.caption)
                                .foregroundStyle(AppTheme.accent)
                            Button("Clear share link (use Psiphon)") {
                                vpn.clearShareLink()
                            }
                            .buttonStyle(.borderless)
                        }
                        Text("hy2:// / Tor / sing-box: not on iOS yet. Use Android for those.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        if let stuck = vpn.importedShareLink, !stuck.isEmpty {
                            Text("Share link saved but Xray appex missing — Connect uses Psiphon.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Clear share link") { vpn.clearShareLink() }
                                .buttonStyle(.borderless)
                        }
                        Text("Xray extension not in this build — run scripts/fetch-ios-tunnel-deps.sh and embed IranVPNTunnelXray.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
            .iranVpnAtmosphere()
            .navigationTitle("مسیرها / Paths")
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(AppTheme.primary)
    }
}

struct AboutTab: View {
    @AppStorage("disclaimerAccepted") private var disclaimerAccepted = true
    @State private var showLegal = false

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Iran VPN")
                        .font(.title.weight(.bold))
                        .foregroundStyle(AppTheme.primary)
                    Text("ایران وی‌پی‌ان")
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent)

                    Text("Open circumvention client that races FOSS paths (Psiphon first) so you can reach the open internet under heavy filtering. Research and informational use only.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Divider()

                    Text("Security tips")
                        .font(.headline)
                        .foregroundStyle(AppTheme.primary)
                    Text("• Prefer tunneled DNS\n• Avoid untrusted public Wi‑Fi\n• Keep the app updated\n• Conduit / in-proxy is on hold until Psiphon distributor keys arrive")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Divider()

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
                        .padding(.top, 8)
                }
                .padding(24)
            }
            .iranVpnAtmosphere()
            .navigationTitle("درباره / About")
            .sheet(isPresented: $showLegal) {
                LegalDisclaimerView(onAccept: { showLegal = false })
            }
        }
    }
}

#Preview {
    ContentView()
}
