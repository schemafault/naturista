import Foundation
import GRDB

actor DatabaseService {
    static let shared = DatabaseService()

    private var dbQueue: DatabaseQueue?

    private init() {}

    func initialize() throws {
        var config = Configuration()
        config.prepareDatabase { db in
            db.trace { print("SQL: \($0)") }
        }

        dbQueue = try DatabaseQueue(path: AppPaths.database.path, configuration: config)
        try migrator.migrate(dbQueue!)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "entries") { t in
                t.column("id", .text).primaryKey()
                t.column("createdAt", .text).notNull()
                t.column("capturedAt", .text)
                t.column("originalImageFilename", .text).notNull()
                t.column("workingImageFilename", .text).notNull()
                t.column("identificationJson", .text).notNull().defaults(to: "")
                t.column("modelConfidence", .text)
                t.column("userStatus", .text).notNull().defaults(to: "unreviewed")
                t.column("illustrationFilename", .text)
                t.column("plateFilename", .text)
                t.column("notes", .text).notNull().defaults(to: "")
            }
        }
        migrator.registerMigration("v2_pinned") { db in
            try db.alter(table: "entries") { t in
                t.add(column: "pinned", .boolean).notNull().defaults(to: false)
            }
        }
        migrator.registerMigration("v3_thumbnails") { db in
            try db.alter(table: "entries") { t in
                t.add(column: "thumbnailFilename", .text)
            }
        }
        return migrator
    }

    func saveEntry(_ entry: Entry) throws {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        try dbQueue.write { db in
            try entry.save(db)
        }
    }

    func fetchEntry(id: String) throws -> Entry? {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        return try dbQueue.read { db in
            try Entry.fetchOne(db, key: id)
        }
    }

    func fetchAllEntries() throws -> [Entry] {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        return try dbQueue.read { db in
            try Entry.order(Entry.Columns.createdAt.desc).fetchAll(db)
        }
    }

    func fetchEntriesMissingThumbnail(limit: Int) throws -> [Entry] {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        return try dbQueue.read { db in
            try Entry
                .filter(Entry.Columns.thumbnailFilename == nil)
                .order(Entry.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func updateThumbnailFilename(id: String, thumbnailFilename: String) throws {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        _ = try dbQueue.write { db in
            try Entry
                .filter(Entry.Columns.id == id)
                .updateAll(db, Entry.Columns.thumbnailFilename.set(to: thumbnailFilename))
        }
    }

    func getEntryCount() throws -> Int {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        return try dbQueue.read { db in
            try Entry.fetchCount(db)
        }
    }

    func deleteEntry(id: String) throws {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        _ = try dbQueue.write { db in
            try Entry.deleteOne(db, key: id)
        }
    }

    @discardableResult
    func setPinned(id: String, pinned: Bool) throws -> Entry? {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        return try dbQueue.write { db in
            guard var entry = try Entry.fetchOne(db, key: id) else { return nil }
            entry.pinned = pinned
            try entry.update(db)
            return entry
        }
    }
}

enum DatabaseError: Error {
    case notInitialized
}