import NetworkExtension
import SwiftUI

/// US-001: Zero-config Connect/Disconnect. Never fakes Connected — waits for VPN status.
/// US-008: Legal disclaimer on first launch.
public struct ContentView: View {
    @AppStorage("disclaimerAccepted") private var disclaimerAccepted = false
    @State private var vpn = VpnController()

    public init() {}

    public var body: some View {
        Group {
            if !disclaimerAccepted {
                LegalDisclaimerView(onAccept: { disclaimerAccepted = true })
            } else {
                ConnectView(vpn: vpn)
            }
        }
        .task {
            await vpn.refreshStatus()
        }
    }
}

struct LegalDisclaimerView: View {
    let onAccept: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("اطلاعیه قانونی / Legal Notice")
                    .font(.headline)
                    .fontWeight(.bold)
                Text("Unauthorized VPN use is illegal in Iran (Supreme Council of Cyberspace, Feb 2024). This app is for research and informational use only. Users assume all legal and personal risks. We do not encourage illegal activity.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                Text("Security: Prefer tunneled DNS; avoid public Wi-Fi; keep the app updated.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                Button("می‌پذیرم / I understand and accept the risks", action: onAccept)
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ConnectView: View {
    @Bindable var vpn: VpnController
    @State private var shareLink = ""
    @State private var showAdvanced = false

    var body: some View {
        VStack(spacing: 16) {
            Text(vpn.statusText)
                .font(.headline)
            if vpn.isConnecting {
                ProgressView()
            } else if vpn.isConnected {
                Button("قطع اتصال / Disconnect") {
                    Task { await vpn.disconnect() }
                }
            } else {
                Button("اتصال / Connect") {
                    Task { await vpn.connect() }
                }
            }
            if let err = vpn.errorMessage {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button(showAdvanced ? "پنهان کردن پیشرفته" : "پیشرفته / Advanced") {
                showAdvanced.toggle()
            }
            .buttonStyle(.borderless)
            if showAdvanced {
                if vpn.xrayExtensionAvailable {
                    TextField("vless:// / vmess:// / trojan://", text: $shareLink, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .padding(.horizontal)
                    Button("Import share link") {
                        vpn.importedShareLink = shareLink.trimmingCharacters(in: .whitespacesAndNewlines)
                        shareLink = ""
                    }
                    .disabled(shareLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let active = vpn.importedShareLink, !active.isEmpty {
                        Text("Xray link active — Connect uses Xray extension")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button("Clear share link (use Psiphon)") {
                            vpn.clearShareLink()
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    Text("Xray extension not in this build — run scripts/fetch-ios-tunnel-deps.sh and embed IranVPNTunnelXray.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            Text("Conduit P2P is not available as an iOS station; default path is Psiphon.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
