import Foundation

/// Persists a single `PetState` as JSON. Writes are atomic (temp file + replace);
/// a corrupt or unreadable save is surfaced as a thrown error, never silently
/// discarded and overwritten with a fresh default — the caller decides what to
/// do with a damaged file.
public struct PetStore: Sendable {
    public enum StoreError: Error, LocalizedError, Equatable {
        case corrupted(reason: String)

        public var errorDescription: String? {
            switch self {
            case .corrupted(let reason):
                "Saved pet state is corrupted: \(reason)"
            }
        }
    }

    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Nintendogs/pet.json")
    }

    /// Loads the saved state, or a fresh `PetState` (stamped `at`) if no save
    /// exists yet. Throws `StoreError.corrupted` if a save exists but can't be
    /// read or decoded — it is left on disk untouched for the caller to inspect
    /// or back up rather than being paved over here.
    public func load(at date: Date) throws -> PetState {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return PetState(needs: PetNeeds(), activity: .idle, lastUpdated: date)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw StoreError.corrupted(reason: "could not read \(url.lastPathComponent): \(error.localizedDescription)")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(PetState.self, from: data)
        } catch {
            throw StoreError.corrupted(reason: "invalid save data: \(error.localizedDescription)")
        }
    }

    /// Writes `state` atomically: encode to a sibling temp file, then swap it
    /// into place, so a crash or concurrent read never observes a half-written file.
    public func save(_ state: PetState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)

        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        try data.write(to: url, options: .atomic)
    }
}
