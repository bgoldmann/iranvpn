# Iran VPN — macOS

Swift + SwiftUI app; uses `core` as static lib or XCFramework. Tunnel via NEPacketTunnelProvider (NetworkExtension).

## Setup

1. Open `IranVPN.xcworkspace` in Xcode.
2. Network Extension: `macos/IranVPNTunnel/PacketTunnelProvider.swift` (same probe/kill-switch model as iOS).
3. Build Rust `core` XCFramework (`core/src/ffi.rs` C ABI).
4. UI never fakes Connected — waits for `NETunnelProviderManager` status.
5. Enable Network Extensions; notarize for Gatekeeper.
6. Distribute via GitHub Releases + mirror (see [docs/distribution.md](../docs/distribution.md)).

---

A modern macOS application using a **workspace + SPM package** architecture for clean separation between app shell and feature code.

## Project Architecture

```
IranVPN/
├── IranVPN.xcworkspace/              # Open this file in Xcode
├── IranVPN.xcodeproj/                # App shell project
├── IranVPN/                          # App target (minimal)
│   ├── Assets.xcassets/                # App-level assets (icons, colors)
│   ├── IranVPNApp.swift              # App entry point
│   ├── IranVPN.entitlements          # App sandbox settings
│   └── IranVPN.xctestplan            # Test configuration
├── IranVPNPackage/                   # 🚀 Primary development area
│   ├── Package.swift                   # Package configuration
│   ├── Sources/IranVPNFeature/       # Your feature code
│   └── Tests/IranVPNFeatureTests/    # Unit tests
└── IranVPNUITests/                   # UI automation tests
```

## Key Architecture Points

### Workspace + SPM Structure
- **App Shell**: `IranVPN/` contains minimal app lifecycle code
- **Feature Code**: `IranVPNPackage/Sources/IranVPNFeature/` is where most development happens
- **Separation**: Business logic lives in the SPM package, app target just imports and displays it

### Buildable Folders (Xcode 16)
- Files added to the filesystem automatically appear in Xcode
- No need to manually add files to project targets
- Reduces project file conflicts in teams

### App Sandbox
The app is sandboxed by default with basic file access permissions. Modify `IranVPN.entitlements` to add capabilities as needed.

## Development Notes

### Code Organization
Most development happens in `IranVPNPackage/Sources/IranVPNFeature/` - organize your code as you prefer.

### Public API Requirements
Types exposed to the app target need `public` access:
```swift
public struct SettingsView: View {
    public init() {}
    
    public var body: some View {
        // Your view code
    }
}
```

### Adding Dependencies
Edit `IranVPNPackage/Package.swift` to add SPM dependencies:
```swift
dependencies: [
    .package(url: "https://github.com/example/SomePackage", from: "1.0.0")
],
targets: [
    .target(
        name: "IranVPNFeature",
        dependencies: ["SomePackage"]
    ),
]
```

### Test Structure
- **Unit Tests**: `IranVPNPackage/Tests/IranVPNFeatureTests/` (Swift Testing framework)
- **UI Tests**: `IranVPNUITests/` (XCUITest framework)
- **Test Plan**: `IranVPN.xctestplan` coordinates all tests

## Configuration

### XCConfig Build Settings
Build settings are managed through **XCConfig files** in `Config/`:
- `Config/Shared.xcconfig` - Common settings (bundle ID, versions, deployment target)
- `Config/Debug.xcconfig` - Debug-specific settings  
- `Config/Release.xcconfig` - Release-specific settings
- `Config/Tests.xcconfig` - Test-specific settings

### App Sandbox & Entitlements
The app is sandboxed by default with basic file access. Edit `IranVPN/IranVPN.entitlements` to add capabilities:
```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<!-- Add other entitlements as needed -->
```

## macOS-Specific Features

### Window Management
Add multiple windows and settings panels:
```swift
@main
struct IranVPNApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        Settings {
            SettingsView()
        }
    }
}
```

### Asset Management
- **App-Level Assets**: `IranVPN/Assets.xcassets/` (app icon with multiple sizes, accent color)
- **Feature Assets**: Add `Resources/` folder to SPM package if needed

### SPM Package Resources
To include assets in your feature package:
```swift
.target(
    name: "IranVPNFeature",
    dependencies: [],
    resources: [.process("Resources")]
)
```

## Notes

### Generated with XcodeBuildMCP
This project was scaffolded using [XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP), which provides tools for AI-assisted macOS development workflows.