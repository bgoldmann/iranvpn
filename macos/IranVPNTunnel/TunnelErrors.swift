import Foundation

enum TunnelError: LocalizedError {
    case pathUnavailable
    case probeFailed
    case libXray(String)

    var errorDescription: String? {
        switch self {
        case .pathUnavailable:
            return "No tunnel path available"
        case .probeFailed:
            return "Connectivity probe failed"
        case .libXray(let message):
            return "LibXray: \(message)"
        }
    }
}
