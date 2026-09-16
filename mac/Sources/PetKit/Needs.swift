import Foundation

/// The pet's care meters. `hunger` and `thirst` are **deficits**: 0 means fully
/// fed/hydrated, 100 means starving/parched. `energy`, `fun`, `cleanliness` and
/// `affection` are the opposite: 0 is the worst state, 100 the best. Every field
/// is clamped to `PetNeeds.bounds` and is guaranteed finite (never NaN/infinite).
public struct PetNeeds: Codable, Sendable, Equatable {
    public static let bounds: ClosedRange<Double> = 0...100

    public var hunger: Double
    public var thirst: Double
    public var energy: Double
    public var fun: Double
    public var cleanliness: Double
    public var affection: Double

    /// A freshly adopted pet: not hungry or thirsty, fully rested, entertained
    /// and clean, with affection starting at a neutral midpoint that grows with care.
    public init(
        hunger: Double = 0,
        thirst: Double = 0,
        energy: Double = 100,
        fun: Double = 100,
        cleanliness: Double = 100,
        affection: Double = 50
    ) {
        self.hunger = hunger.clamped(to: Self.bounds)
        self.thirst = thirst.clamped(to: Self.bounds)
        self.energy = energy.clamped(to: Self.bounds)
        self.fun = fun.clamped(to: Self.bounds)
        self.cleanliness = cleanliness.clamped(to: Self.bounds)
        self.affection = affection.clamped(to: Self.bounds)
    }

    private enum CodingKeys: String, CodingKey {
        case hunger, thirst, energy, fun, cleanliness, affection
    }

    /// Rejects corrupt saves outright (NaN/infinite/out-of-range) instead of
    /// silently clamping them into shape, so a damaged file surfaces as a
    /// decode error rather than quietly mutating into a plausible-looking pet.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func validated(_ key: CodingKeys) throws -> Double {
            let value = try container.decode(Double.self, forKey: key)
            guard value.isFinite, Self.bounds.contains(value) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: container,
                    debugDescription: "\(key.rawValue) must be a finite value in \(Self.bounds), got \(value)"
                )
            }
            return value
        }
        hunger = try validated(.hunger)
        thirst = try validated(.thirst)
        energy = try validated(.energy)
        fun = try validated(.fun)
        cleanliness = try validated(.cleanliness)
        affection = try validated(.affection)
    }

    /// Re-bounds every field after arithmetic drift; used internally by `PetBehavior`.
    mutating func clamp() {
        hunger = hunger.clamped(to: Self.bounds)
        thirst = thirst.clamped(to: Self.bounds)
        energy = energy.clamped(to: Self.bounds)
        fun = fun.clamped(to: Self.bounds)
        cleanliness = cleanliness.clamped(to: Self.bounds)
        affection = affection.clamped(to: Self.bounds)
    }
}

/// What the pet is doing right now. `idle`/`sit`/`sleep` are chosen autonomously
/// by `PetBehavior.tick`; the rest are momentary interactions triggered by `interact`.
public enum PetActivity: String, Codable, Sendable, CaseIterable, Equatable {
    case idle, sit, sleep, eat, drink, play, call, pet
}

/// A snapshot of the pet: current meters, what it is doing, and when this
/// snapshot was last advanced. This is the only type `PetStore` persists.
public struct PetState: Codable, Sendable, Equatable {
    public var needs: PetNeeds
    public var activity: PetActivity
    public var lastUpdated: Date
    /// Optional for decoding saves written before presence-aware naps existed.
    public var lastInteractionAt: Date?

    public init(needs: PetNeeds = PetNeeds(), activity: PetActivity = .idle, lastUpdated: Date = Date(), lastInteractionAt: Date? = nil) {
        self.needs = needs
        self.activity = activity
        self.lastUpdated = lastUpdated
        self.lastInteractionAt = lastInteractionAt ?? lastUpdated
    }

    /// A short status hint for chrome (menu bar, panel) when the pet wants care
    /// and isn't already receiving it: nil while asleep or mid-interaction, since
    /// there's nothing useful for the user to do in either case.
    public var careRequest: String? {
        guard activity == .idle || activity == .sit else { return nil }
        let hungry = needs.hunger > 70
        let thirsty = needs.thirst > 70
        switch (hungry, thirsty) {
        case (true, true): return "hungry and thirsty"
        case (true, false): return "hungry"
        case (false, true): return "thirsty"
        case (false, false): return nil
        }
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        guard isFinite else { return range.lowerBound }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
