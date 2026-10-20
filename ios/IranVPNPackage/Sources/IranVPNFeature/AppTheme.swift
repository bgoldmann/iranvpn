import SwiftUI

/// Shared Iran VPN brand tokens (teal + gold). Light surfaces, no purple/glow.
enum AppTheme {
    static let primary = Color(red: 0.043, green: 0.239, blue: 0.227) // #0B3D3A
    static let accent = Color(red: 0.769, green: 0.647, blue: 0.455) // #C4A574
    static let mist = Color(red: 0.945, green: 0.957, blue: 0.961) // cool gray
    static let paleTeal = Color(red: 0.86, green: 0.93, blue: 0.92)
    static let onPrimary = Color.white
    static let danger = Color(red: 0.75, green: 0.22, blue: 0.20)

    static var atmosphere: LinearGradient {
        LinearGradient(
            colors: [mist, paleTeal, mist],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension View {
    func iranVpnAtmosphere() -> some View {
        background(AppTheme.atmosphere.ignoresSafeArea())
    }
}
