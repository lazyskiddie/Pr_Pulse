import Foundation
import Network
import Observation

@MainActor @Observable
final class NetworkMonitor {
    var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "prpulse.network"))
    }
}
