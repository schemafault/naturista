import Foundation
import Network
import Combine

// Thin wrapper around NWPathMonitor exposing a single @Published bool.
// Used by OnboardingState to disable the "Download and continue" button
// when the device is offline.
@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isReachable: Bool = true

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "naturista.onboarding.network")

    init() {
        self.monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            Task { @MainActor in
                self?.isReachable = reachable
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
