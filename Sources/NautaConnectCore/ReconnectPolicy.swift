import Foundation

/// Pure policy helpers for periodic session health checks and automatic reconnection.
public enum ReconnectPolicy {
    public static let supportedIntervals = [30, 60, 120, 300]
    public static let defaultIntervalSeconds = 60

    public enum FailureDisposition: Equatable {
        case retry(delay: TimeInterval)
        case stop(reason: String)
    }

    /// Classifies a failed auto-reconnect login attempt into a backoff retry or a fatal stop.
    public static func disposition(for error: Error, attempt: Int) -> FailureDisposition {
        if case PortalError.loginRejected(let message) = error {
            let lower = message.lowercased()
            // Right after a Wi-Fi drop, the AC can momentarily report an active session before freeing it.
            let isAlreadyConnected = lower.contains("conectado") || lower.contains("connected")
            if isAlreadyConnected && attempt < 4 {
                return .retry(delay: backoffDelay(forAttempt: attempt))
            }
            return .stop(reason: message)
        }
        return .retry(delay: backoffDelay(forAttempt: attempt))
    }

    public static func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        switch attempt {
        case ...1: return 15
        case 2: return 30
        case 3: return 60
        case 4: return 120
        default: return 300
        }
    }
}
