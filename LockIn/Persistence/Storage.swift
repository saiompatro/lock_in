import Foundation
import Observation

/// Small JSON file helper rooted at ~/Library/Application Support/Lock In/.
enum Storage {
    /// Debug snapshot mode sets this so nothing on disk is touched.
    nonisolated(unsafe) static var isReadOnly = false

    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Lock In", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        guard !isReadOnly else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }

    static func remove(_ name: String) {
        guard !isReadOnly else { return }
        try? FileManager.default.removeItem(at: url(name))
    }
}

/// The user's study spaces, persisted to study-spaces.json.
@MainActor
@Observable
final class StudySpaceStore {
    private(set) var spaces: [StudySpace]
    private let fileName = "study-spaces.json"

    var enabledSpaces: [StudySpace] { spaces.filter(\.isEnabled) }

    init() {
        spaces = Storage.load([StudySpace].self, from: fileName) ?? []
    }

    func add(_ space: StudySpace) {
        // Skip exact duplicates (same kind + target).
        if spaces.contains(where: { $0.kind == space.kind && $0.bundleID == space.bundleID
            && $0.titleContains == space.titleContains && $0.urlPattern == space.urlPattern }) { return }
        spaces.append(space)
        persist()
    }

    func update(_ space: StudySpace) {
        guard let i = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        spaces[i] = space
        persist()
    }

    func remove(id: UUID) {
        spaces.removeAll { $0.id == id }
        persist()
    }

    func remove(atOffsets offsets: IndexSet) {
        spaces.remove(atOffsets: offsets)
        persist()
    }

    func setEnabled(_ enabled: Bool, id: UUID) {
        guard let i = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[i].isEnabled = enabled
        persist()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        spaces.move(fromOffsets: fromOffsets, toOffset: toOffset)
        persist()
    }

    private func persist() { Storage.save(spaces, to: fileName) }
}

/// Finished sessions, persisted to sessions.json. Newest first.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [StudySessionRecord]
    private let fileName = "sessions.json"
    private let liveFileName = "live-session.json"

    init() {
        sessions = (Storage.load([StudySessionRecord].self, from: fileName) ?? [])
            .sorted { $0.startedAt > $1.startedAt }
    }

    func append(_ record: StudySessionRecord) {
        // Ignore accidental sessions with under 10 seconds of tracked time.
        guard record.totalTrackedSeconds >= 10 else { return }
        sessions.removeAll { $0.id == record.id }
        sessions.insert(record, at: 0)
        persist()
    }

    func delete(id: UUID) {
        sessions.removeAll { $0.id == id }
        persist()
    }

    func deleteAll() {
        sessions.removeAll()
        persist()
    }

    // MARK: Crash recovery

    /// Periodically called with a snapshot of the running session so it survives a crash or forced quit.
    func saveLiveSnapshot(_ record: StudySessionRecord?) {
        if let record { Storage.save(record, to: liveFileName) } else { Storage.remove(liveFileName) }
    }

    /// On launch: if a live snapshot exists from a previous run, save it as a finished session.
    func recoverInterruptedSession() {
        guard let record = Storage.load(StudySessionRecord.self, from: liveFileName) else { return }
        append(record)
        Storage.remove(liveFileName)
    }

    #if DEBUG
    /// Replace the in-memory list (debug snapshot mode only; Storage is read-only then).
    func loadPreviewData(_ records: [StudySessionRecord]) {
        sessions = records.sorted { $0.startedAt > $1.startedAt }
    }
    #endif

    private func persist() { Storage.save(sessions, to: fileName) }
}
