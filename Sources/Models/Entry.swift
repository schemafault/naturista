import Foundation
import GRDB

struct Entry: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: String = UUID().uuidString
    var createdAt: String = ISO8601DateFormatter().string(from: Date())
    var capturedAt: String? = nil
    var originalImageFilename: String = ""
    var workingImageFilename: String = ""
    var identificationJson: String = ""
    var modelConfidence: String? = nil
    var userStatus: String = "unreviewed"
    var illustrationFilename: String? = nil
    var plateFilename: String? = nil
    var thumbnailFilename: String? = nil
    var notes: String = ""
    var pinned: Bool = false
    var tagsJson: String = "[]"
    // Per-entry override that bypasses the kingdom-template render path
    // in FluxActor. Edited via the detail view's "Illustration prompt"
    // section. Nil means "follow the rendered template" — the default.
    var customFluxPrompt: String? = nil

    static let databaseTableName = "entries"

    enum Columns: String, ColumnExpression {
        case id, createdAt, capturedAt, originalImageFilename, workingImageFilename
        case identificationJson, modelConfidence, userStatus
        case illustrationFilename, plateFilename, thumbnailFilename, notes, pinned, tagsJson
        case customFluxPrompt
    }
}

extension Entry {
    var identification: Identification {
        Identification.parse(identificationJson)
    }

    mutating func setIdentification(_ id: Identification) {
        identificationJson = id.encodedJSON()
        modelConfidence = id.modelConfidence
    }

    var tags: [String] {
        guard let data = tagsJson.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    // Trim whitespace, drop empties, dedupe (case-sensitive, order-preserving),
    // and re-encode. Centralised so callers can't smuggle in dirty input.
    mutating func setTags(_ newTags: [String]) {
        var seen = Set<String>()
        var clean: [String] = []
        for raw in newTags {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !seen.contains(t) else { continue }
            seen.insert(t)
            clean.append(t)
        }
        if let data = try? JSONEncoder().encode(clean),
           let json = String(data: data, encoding: .utf8) {
            tagsJson = json
        } else {
            tagsJson = "[]"
        }
    }
}

// Pre-kingdom-aware entries (all plants) have no `kingdom` key in their
// identificationJson. `parse(_:)` defaults to .plant so legacy rows render
// correctly with no migration.
enum Kingdom: String {
    case plant
    case animal
    case fungus
    case other

    static func parse(_ raw: String?) -> Kingdom {
        guard let raw = raw?.lowercased() else { return .plant }
        return Kingdom(rawValue: raw) ?? .plant
    }

    // Tracked-mono eyebrow shown beside Nº in the library row.
    var displayLabel: String {
        switch self {
        case .plant: return "BOTANY"
        case .animal: return "ZOOLOGY"
        case .fungus: return "MYCOLOGY"
        case .other: return "STILL LIFE"
        }
    }

    // Eyebrow over the chip list in the detail panel.
    var visibleEvidenceLabel: String {
        switch self {
        case .plant: return "Visible characters"
        case .animal: return "Field marks"
        case .fungus: return "Macroscopic features"
        case .other: return "Description"
        }
    }
}