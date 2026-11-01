import Foundation

enum TunnelError: Error, LocalizedError {
    case probeFailed
    case pathUnavailable
    case libXray(String)

    var errorDescription: String? {
        switch self {
        case .probeFailed:
            return "Connectivity probe failed — tunnel did not reach the internet"
        case .pathUnavailable:
            return "No path available — ensure tunnel deps are fetched and the correct extension is embedded"
        case .libXray(let message):
            return "LibXray: \(message)"
        }
    }
}
