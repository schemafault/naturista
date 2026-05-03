import Foundation

// The identification subsystem returns one of these per call. Decoder
// tolerates legacy pre-multi-kingdom rows (no `kingdom` key) by falling
// back through Kingdom.parse, and tolerates absent optional arrays so a
// minimally-conforming model still decodes.
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

