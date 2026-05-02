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