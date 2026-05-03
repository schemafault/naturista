import Foundation

// Encodes the "only one model holds GPU memory at a time" rule as an
// invariant rather than something every caller has to remember. Any work
// that wants exclusive access to one tenant shuts down the *other* warm
// tenant on entry.

enum ModelLeaseTenant: Sendable {
    case identification   // Gemma
    case illustration     // Flux
}

actor ModelLease {
    static let shared = ModelLease()

    private var current: ModelLeaseTenant?

    func withExclusive<T: Sendable>(
        _ tenant: ModelLeaseTenant,
        _ work: () async throws -> T
    ) async throws -> T {
        if let other = current, other != tenant {
            await release(other)
        }
        current = tenant
        return try await work()
    }

    private func release(_ tenant: ModelLeaseTenant) async {
        switch tenant {
        case .identification: await GemmaActor.shared.shutdown()
        case .illustration:   await FluxActor.shared.shutdown()
        }
    }
}
