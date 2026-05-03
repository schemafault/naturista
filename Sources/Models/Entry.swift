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
    var notes: String = ""

    static let databaseTableName = "entries"

    enum Columns: String, ColumnExpression {
        case id, createdAt, capturedAt, originalImageFilename, workingImageFilename
        case identificationJson, modelConfidence, userStatus
        case illustrationFilename, plateFilename, notes
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