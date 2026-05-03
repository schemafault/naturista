import Foundation

struct IdentificationResult: Codable, Equatable, Sendable {
    var kingdom: String
    var modelConfidence: String
    var topCandidate: TopCandidate
    var alternatives: [Alternative]
    var visibleEvidence: [String]
    var missingEvidence: [String]
    var safetyNote: String
    var error: String?

    enum CodingKeys: String, CodingKey {
        case kingdom
        case modelConfidence = "model_confidence"
        case topCandidate = "top_candidate"
        case alternatives
        case visibleEvidence = "visible_evidence"
        case missingEvidence = "missing_evidence"
        case safetyNote = "safety_note"
        case error
    }

    // Legacy JSON (pre-multi-kingdom) has no `kingdom` key — Kingdom.parse
    // handles that default and case-normalisation in one place.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.kingdom = Kingdom.parse(try c.decodeIfPresent(String.self, forKey: .kingdom)).rawValue
        self.modelConfidence = try c.decode(String.self, forKey: .modelConfidence)
        self.topCandidate = try c.decode(TopCandidate.self, forKey: .topCandidate)
        self.alternatives = (try c.decodeIfPresent([Alternative].self, forKey: .alternatives)) ?? []
        self.visibleEvidence = (try c.decodeIfPresent([String].self, forKey: .visibleEvidence)) ?? []
        self.missingEvidence = (try c.decodeIfPresent([String].self, forKey: .missingEvidence)) ?? []
        self.safetyNote = (try c.decodeIfPresent(String.self, forKey: .safetyNote)) ?? ""
        self.error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

struct TopCandidate: Codable, Equatable, Sendable {
    var commonName: String
    var scientificName: String
    var family: String

    enum CodingKeys: String, CodingKey {
        case commonName = "common_name"
        case scientificName = "scientific_name"
        case family
    }
}

struct Alternative: Codable, Equatable, Sendable {
    var commonName: String
    var scientificName: String
    var reason: String

    enum CodingKeys: String, CodingKey {
        case commonName = "common_name"
        case scientificName = "scientific_name"
        case reason
    }
}

actor GemmaActor {
    static let shared = GemmaActor()

    private static var scriptPath: String {
        AppPaths.applicationSupport
            .appendingPathComponent("Python", isDirectory: true)
            .appendingPathComponent("gemma_service.py")
            .path
    }

    private let transport: PythonProcessTransport

    private init() {
        self.transport = PythonProcessTransport(config: .init(
            scriptPath: GemmaActor.scriptPath,
            environment: {
                [
                    "GEMMA_MODEL_PATH": NSString(string: ModelConfig.gemmaPath).expandingTildeInPath
                ]
            },
            timeoutSeconds: 310,
            warmupSeconds: 2,
            stderrLogURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("naturista_gemma.log")
        ))
    }

    private struct IdentifyRequest: Encodable, Sendable {
        let action: String
        let photo_path: String
    }

    func identify(photoPath: String) async throws -> IdentificationResult {
        let result = try await transport.call(
            IdentifyRequest(action: "identify", photo_path: photoPath),
            responseType: IdentificationResult.self
        )
        if let err = result.error, !err.isEmpty {
            throw PythonRPCError.remote(err)
        }
        return result
    }

    func shutdown() async {
        await transport.shutdown()
    }
}
