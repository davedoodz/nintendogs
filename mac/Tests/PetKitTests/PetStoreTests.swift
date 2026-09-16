import Testing
import Foundation
@testable import PetKit

private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("PetStoreTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("pet-state.json")
}

@Test func loadWithoutASaveReturnsAFreshStateStampedAtTheGivenDate() throws {
    let store = PetStore(url: temporaryURL())
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let state = try store.load(at: now)
    #expect(state.needs == PetNeeds())
    #expect(state.activity == .idle)
    #expect(state.lastUpdated == now)
}

@Test func saveThenLoadRoundTrips() throws {
    let store = PetStore(url: temporaryURL())
    // Whole-second timestamp: ISO-8601 encoding truncates fractional seconds,
    // so a sub-second Date would not round-trip exactly.
    let original = PetState(
        needs: PetNeeds(hunger: 12.5, thirst: 33, energy: 77.25, fun: 40, cleanliness: 90, affection: 61),
        activity: .sit,
        lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)
    )
    try store.save(original)
    let loaded = try store.load(at: Date(timeIntervalSince1970: 1_700_000_500))
    #expect(loaded == original)
}

@Test func saveOverwritesAPreviousSaveAtomically() throws {
    let store = PetStore(url: temporaryURL())
    let first = PetState(needs: PetNeeds(hunger: 5), activity: .idle, lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))
    let second = PetState(needs: PetNeeds(hunger: 55), activity: .play, lastUpdated: Date(timeIntervalSince1970: 1_700_000_100))
    try store.save(first)
    try store.save(second)
    let loaded = try store.load(at: Date(timeIntervalSince1970: 1_700_000_200))
    #expect(loaded == second)
}

@Test func corruptJSONThrowsAndLeavesTheFileUntouched() throws {
    let url = temporaryURL()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let corrupt = Data("{ this is not valid json".utf8)
    try corrupt.write(to: url)

    let store = PetStore(url: url)
    #expect(throws: PetStore.StoreError.self) {
        try store.load(at: Date())
    }
    // A failed load must not have "repaired" the file by writing a fresh state over it.
    let stillOnDisk = try Data(contentsOf: url)
    #expect(stillOnDisk == corrupt, "load must not silently overwrite a corrupt save")
}

@Test func outOfRangeNeedValueIsRejectedAsCorrupt() throws {
    let url = temporaryURL()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let json = """
    {"needs":{"hunger":500,"thirst":0,"energy":100,"fun":100,"cleanliness":100,"affection":50},\
    "activity":"idle","lastUpdated":"2026-01-01T00:00:00Z"}
    """
    try Data(json.utf8).write(to: url)

    let store = PetStore(url: url)
    #expect(throws: PetStore.StoreError.self) {
        try store.load(at: Date())
    }
}
