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
        migrator.registerMigration("v4_tags") { db in
            try db.alter(table: "entries") { t in
                t.add(column: "tagsJson", .text).notNull().defaults(to: "[]")
            }
        }
        migrator.registerMigration("v5_customFluxPrompt") { db in
            try db.alter(table: "entries") { t in
                t.add(column: "customFluxPrompt", .text)
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

    @discardableResult
    func setTags(id: String, tags: [String]) throws -> Entry? {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        return try dbQueue.write { db in
            guard var entry = try Entry.fetchOne(db, key: id) else { return nil }
            entry.setTags(tags)
            try entry.update(db)
            return entry
        }
    }

    // Whitespace-only / empty strings normalise to nil so a "follow the
    // template" reset never persists a sentinel string into the DB.
    @discardableResult
    func setCustomFluxPrompt(id: String, prompt: String?) throws -> Entry? {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        let cleaned = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (cleaned?.isEmpty ?? true) ? nil : cleaned
        return try dbQueue.write { db in
            guard var entry = try Entry.fetchOne(db, key: id) else { return nil }
            entry.customFluxPrompt = normalized
            try entry.update(db)
            return entry
        }
    }

    // Rewrite a tag across every entry that has it. Per-entry dedupe is
    // handled by `setTags`, so renaming "Garden" → "garden" on an entry
    // that already has "garden" merges cleanly.
    func renameTag(from oldTag: String, to newTag: String) throws {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldTag else { return }
        try dbQueue.write { db in
            let entries = try Entry.fetchAll(db)
            for var entry in entries where entry.tags.contains(oldTag) {
                let rewritten = entry.tags.map { $0 == oldTag ? trimmed : $0 }
                entry.setTags(rewritten)
                try entry.update(db)
            }
        }
    }

    // Strip a tag from every entry that has it.
    func deleteTag(_ tag: String) throws {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        try dbQueue.write { db in
            let entries = try Entry.fetchAll(db)
            for var entry in entries where entry.tags.contains(tag) {
                entry.setTags(entry.tags.filter { $0 != tag })
                try entry.update(db)
            }
        }
    }
}

enum DatabaseError: Error {
    case notInitialized
}