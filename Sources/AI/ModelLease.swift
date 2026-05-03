import Foundation

// Encodes two GPU-memory rules as one invariant:
//
//   1. Only one model holds GPU memory at a time — taking the lease for
//      one tenant releases whichever other tenant was warm.
//   2. Some tenants release eagerly on exit (Flux is heavyweight and
//      always one-shot per pipeline run); others stay warm so the next
//      caller skips the warmup cost (Gemma serves consecutive imports).

enum ModelLeaseTenant: Sendable {
    case identification   // Gemma — kept warm across consecutive identifies
    case illustration     // Flux — released after each generate to free VRAM

    fileprivate var releasesEagerly: Bool {
        switch self {
        case .identification: return false
        case .illustration:   return true
        }
    }
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

        do {
            let result = try await work()
            await releaseIfEager(tenant)
            return result
        } catch {
            await releaseIfEager(tenant)
            throw error
        }
    }

    private func releaseIfEager(_ tenant: ModelLeaseTenant) async {
        guard tenant.releasesEagerly else { return }
        await release(tenant)
        if current == tenant { current = nil }
    }

    private func release(_ tenant: ModelLeaseTenant) async {
        switch tenant {
        case .identification: await GemmaActor.shared.shutdown()
        case .illustration:   await FluxActor.shared.shutdown()
        }
    }
}
