import NetworkExtension
import SwiftUI

/// US-001: Zero-config Connect/Disconnect. Never fakes Connected.
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
        .frame(minWidth: 360, minHeight: 280)
        .task { await vpn.refreshStatus() }
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
                Text("Unauthorized VPN use is illegal in Iran (Supreme Council of Cyberspace, Feb 2024). This app is for research and informational use only. Users assume all legal and personal risks.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                Text("Security: Prefer tunneled DNS; avoid public Wi-Fi; keep updated.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                Button("می‌پذیرم / I understand and accept the risks", action: onAccept)
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
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
                Text(err).foregroundStyle(.red).font(.caption)
            }
            Button(showAdvanced ? "Hide advanced" : "پیشرفته / Advanced") {
                showAdvanced.toggle()
            }
            if showAdvanced {
                TextField("vless:// share link", text: $shareLink, axis: .vertical)
                    .lineLimit(2...4)
                Button("Import") {
                    vpn.importedShareLink = shareLink.trimmingCharacters(in: .whitespacesAndNewlines)
                    shareLink = ""
                }
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
