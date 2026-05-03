import Foundation

// Facade over the chosen `Identifier` implementation. Existing callers
// (PipelineService, ModelLease) keep talking to GemmaActor.shared; this
// type just routes to PythonGemmaIdentifier or NativeGemmaIdentifier
// based on the IdentificationBackendStore flag.
//
// Backend choice is captured at first construction. Flipping the flag
// at runtime is honored on the next call — `shutdown()` tears down the
// active identifier; the next `identify` rebuilds for whichever backend
// the flag now reports.
actor GemmaActor {
    static let shared = GemmaActor()

    private var identifier: (any Identifier)?
    private var activeBackend: IdentificationBackend?

    private init() {}

    func identify(photoPath: String) async throws -> IdentificationResult {
        let id = await ensureIdentifier()
        return try await id.identify(photoPath: photoPath)
    }

    func shutdown() async {
        guard let id = identifier else { return }
        await id.shutdown()
        identifier = nil
        activeBackend = nil
    }

    // Builds the identifier for the currently-selected backend, or returns
    // the existing one if it still matches. Tearing down on a flag flip is
    // the same shutdown the eager FLUX path uses — safe to call from the
    // identify hot path because the shutdown is short.
    private func ensureIdentifier() async -> any Identifier {
        let desired = IdentificationBackendStore.shared.current
        if let id = identifier, activeBackend == desired { return id }

        if let existing = identifier {
            await existing.shutdown()
        }

        let next: any Identifier
        switch desired {
        case .python: next = PythonGemmaIdentifier()
        case .native: next = NativeGemmaIdentifier()
        }
        identifier = next
        activeBackend = desired
        return next
    }
}
