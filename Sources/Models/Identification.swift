import Foundation

// Typed view over Entry.identificationJson. Collapses the three storage
// shapes ("", {"error":"..."}, full IdentificationResult JSON) into one
// Status enum, and centralises the "missing kingdom defaults to plant"
// rule for legacy rows.
struct Identification: Equatable {
    enum Status: Equatable {
        case pending
        case failed(message: String)
        case ready(IdentificationResult)
    }

    let status: Status

    static func success(_ result: IdentificationResult) -> Identification {
        Identification(status: .ready(result))
    }

    static func failure(_ message: String) -> Identification {
        Identification(status: .failed(message: message))
    }

    static let pending = Identification(status: .pending)
}

extension Identification {
    var result: IdentificationResult? {
        if case .ready(let r) = status { return r }
        return nil
    }

    var failureMessage: String? {
        if case .failed(let m) = status { return m }
        return nil
    }

    var commonName: String?    { result?.topCandidate.commonName }
    var scientificName: String? { result?.topCandidate.scientificName }
    var family: String?        { result?.topCandidate.family }
    var kingdom: Kingdom       { result.map { Kingdom.parse($0.kingdom) } ?? .plant }
    var modelConfidence: String? { result?.modelConfidence }
    var visibleEvidence: [String] { result?.visibleEvidence ?? [] }
    var alternatives: [Alternative] { result?.alternatives ?? [] }
}

// MARK: - Parsing & encoding

extension Identification {
    // Parses the three legal payload shapes. Cached by JSON string so each
    // unique payload decodes exactly once across the app lifetime — the
    // LibraryView search filter would otherwise re-parse N entries per
    // keystroke.
    static func parse(_ json: String) -> Identification {
        if json.isEmpty { return .pending }
        if let cached = IdentificationCache.shared.value(for: json) {
            return cached
        }
        let parsed = decode(json)
        IdentificationCache.shared.set(parsed, for: json)
        return parsed
    }

    private static func decode(_ json: String) -> Identification {
        guard let data = json.data(using: .utf8) else {
            return .failure("Could not read identification payload.")
        }
        // Error payloads ({"error":"..."}) are emitted by the import/pipeline
        // failure paths. Try them before the structured decode so a malformed
        // IdentificationResult never masks a real error message.
        if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMessage = errorJson["error"] as? String,
           errorJson["top_candidate"] == nil {
            return .failure(errorMessage)
        }
        do {
            let result = try JSONDecoder().decode(IdentificationResult.self, from: data)
            if let err = result.error, !err.isEmpty {
                return .failure(err)
            }
            return .success(result)
        } catch {
            return .failure("Could not decode identification: \(error.localizedDescription)")
        }
    }

    // Encodes the identification to the JSON shape stored in `Entry.identificationJson`.
    func encodedJSON() -> String {
        switch status {
        case .pending:
            return ""
        case .failed(let message):
            let payload = ["error": message]
            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
                  let s = String(data: data, encoding: .utf8) else {
                return "{\"error\":\"identification failed\"}"
            }
            return s
        case .ready(let result):
            guard let data = try? JSONEncoder().encode(result),
                  let s = String(data: data, encoding: .utf8) else {
                return ""
            }
            return s
        }
    }
}

// Reference-typed cache so reading from a struct doesn't require mutation,
// and so two Entry copies of the same row share the parsed result. NSCache
// auto-evicts under memory pressure.
private final class IdentificationCache {
    static let shared = IdentificationCache()

    private let cache = NSCache<NSString, CacheEntry>()

    private final class CacheEntry {
        let value: Identification
        init(_ value: Identification) { self.value = value }
    }

    func value(for json: String) -> Identification? {
        cache.object(forKey: json as NSString)?.value
    }

    func set(_ value: Identification, for json: String) {
        cache.setObject(CacheEntry(value), forKey: json as NSString)
    }
}
