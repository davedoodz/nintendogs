import Testing
import Foundation
@testable import PetKit

private let utc: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}()

/// Builds a UTC date so tests are independent of the host machine's time zone.
private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

@Test func hungerAndThirstNeverSelfSatisfyWithoutInteraction() {
    var behavior = PetBehavior(state: PetState(
        needs: PetNeeds(hunger: 10, thirst: 10),
        activity: .idle,
        lastUpdated: date(2026, 1, 1, 8)
    ))
    behavior.tick(at: date(2026, 1, 1, 20), calendar: utc) // 12h of plain idling, no care given
    #expect(behavior.state.needs.hunger > 10, "hunger is a deficit that only ever drifts up on its own")
    #expect(behavior.state.needs.thirst > 10, "thirst is a deficit that only ever drifts up on its own")
}

@Test func eatingReplenishesOnlyWhileTheInteractionRuns() {
    var behavior = PetBehavior(state: PetState(
        needs: PetNeeds(hunger: 90),
        activity: .idle,
        lastUpdated: date(2026, 1, 1, 12)
    ))
    let start = date(2026, 1, 1, 12)
    behavior.interact(.eat, at: start)
    #expect(behavior.state.activity == .eat)

    behavior.tick(at: start.addingTimeInterval(5), calendar: utc) // halfway through a 10s meal
    let midHunger = behavior.state.needs.hunger
    #expect(midHunger < 90, "hunger should be falling while eat runs")
    #expect(behavior.state.activity == .eat, "still eating at the halfway point")

    behavior.tick(at: start.addingTimeInterval(10), calendar: utc) // meal finishes
    #expect(behavior.state.activity != .eat, "activity reverts once the meal duration elapses")
    let finishedHunger = behavior.state.needs.hunger

    behavior.tick(at: start.addingTimeInterval(30), calendar: utc) // 20s later, no more eating
    #expect(
        behavior.state.needs.hunger > finishedHunger,
        "hunger resumes drifting upward once the meal ends — no automatic replenishment"
    )
}

@Test func playAndPetImproveFunAndAffection() {
    var behavior = PetBehavior(state: PetState(
        needs: PetNeeds(fun: 20, affection: 20),
        activity: .idle,
        lastUpdated: date(2026, 1, 1, 12)
    ))
    let start = date(2026, 1, 1, 12)
    behavior.interact(.play, at: start)
    behavior.tick(at: start.addingTimeInterval(12), calendar: utc) // full play session
    #expect(behavior.state.needs.fun > 20, "play should raise fun")
    #expect(behavior.state.needs.affection > 20, "play should also raise affection")

    let afterPlay = behavior.state.needs.affection
    behavior.interact(.pet, at: start.addingTimeInterval(12))
    behavior.tick(at: start.addingTimeInterval(17), calendar: utc) // full pet session
    #expect(behavior.state.needs.affection > afterPlay, "petting should raise affection further")
}

@Test func interactionsPreemptCurrentActivityIncludingSleep() {
    var behavior = PetBehavior(state: PetState(
        needs: PetNeeds(energy: 30),
        activity: .sleep,
        lastUpdated: date(2026, 1, 1, 2)
    ))
    // Force the internal state to sleep by ticking once at night with low energy.
    behavior.tick(at: date(2026, 1, 1, 2, 1), calendar: utc)
    #expect(behavior.state.activity == .sleep)

    behavior.interact(.call, at: date(2026, 1, 1, 2, 1))
    #expect(behavior.state.activity == .call, "call preempts sleep immediately")
}

@Test func callWakesASleepingPet() {
    var behavior = PetBehavior(state: PetState(
        needs: PetNeeds(energy: 40),
        activity: .idle,
        lastUpdated: date(2026, 1, 1, 23)
    ))
    behavior.tick(at: date(2026, 1, 1, 23, 1), calendar: utc)
    #expect(behavior.state.activity == .sleep, "low energy at night should autonomously fall asleep")

    behavior.interact(.call, at: date(2026, 1, 1, 23, 1))
    #expect(behavior.state.activity == .call)
    #expect(behavior.state.activity != .sleep, "call interrupts sleep")
}

@Test func careRequestIsNilWhileAsleepOrMidInteraction() {
    var trulyAsleep = PetBehavior(state: PetState(needs: PetNeeds(hunger: 80, energy: 10), activity: .idle, lastUpdated: date(2026, 1, 1, 2)))
    trulyAsleep.tick(at: date(2026, 1, 1, 2, 1), calendar: utc)
    #expect(trulyAsleep.state.activity == .sleep)
    #expect(trulyAsleep.state.careRequest == nil, "no care request while asleep")

    var eating = PetBehavior(state: PetState(needs: PetNeeds(hunger: 90), activity: .idle, lastUpdated: date(2026, 1, 1, 12)))
    eating.interact(.eat, at: date(2026, 1, 1, 12))
    #expect(eating.state.careRequest == nil, "no care request while already eating")
}

@Test func utilityBasedSelectionPrefersRestByEnergyAndTimeOfDay() {
    // High energy, daytime -> idle.
    var rested = PetBehavior(state: PetState(needs: PetNeeds(energy: 100), activity: .idle, lastUpdated: date(2026, 1, 1, 12)))
    rested.tick(at: date(2026, 1, 1, 12, 1), calendar: utc)
    #expect(rested.state.activity == .idle)

    // Low energy, daytime -> sit (not asleep, since it isn't night).
    var tiredDaytime = PetBehavior(state: PetState(needs: PetNeeds(energy: 15), activity: .idle, lastUpdated: date(2026, 1, 1, 12)))
    tiredDaytime.tick(at: date(2026, 1, 1, 12, 1), calendar: utc)
    #expect(tiredDaytime.state.activity == .sit)

    // Low energy, nighttime, needs fine -> sleep.
    var tiredNight = PetBehavior(state: PetState(needs: PetNeeds(energy: 15), activity: .idle, lastUpdated: date(2026, 1, 1, 23)))
    tiredNight.tick(at: date(2026, 1, 1, 23, 1), calendar: utc)
    #expect(tiredNight.state.activity == .sleep)
}

@Test func criticalHungerOrThirstBlocksAutonomousSleepAndRequestsCare() {
    var behavior = PetBehavior(state: PetState(
        needs: PetNeeds(hunger: 90, energy: 20),
        activity: .idle,
        lastUpdated: date(2026, 1, 1, 23)
    ))
    behavior.tick(at: date(2026, 1, 1, 23, 1), calendar: utc)
    #expect(behavior.state.activity != .sleep, "a starving pet stays up instead of sleeping through it")
    #expect(behavior.state.careRequest == "hungry")
}

@Test func sleepRecoversEnergyAndWakesAtMorningOrFullEnergy() {
    var behavior = PetBehavior(state: PetState(
        needs: PetNeeds(energy: 20),
        activity: .idle,
        lastUpdated: date(2026, 1, 1, 22)
    ))
    behavior.tick(at: date(2026, 1, 1, 22, 5), calendar: utc)
    #expect(behavior.state.activity == .sleep)
    let energyAfterFiveMinutes = behavior.state.needs.energy
    #expect(energyAfterFiveMinutes > 20, "energy recovers while asleep")

    behavior.tick(at: date(2026, 1, 2, 6, 59), calendar: utc) // still night, well rested by now
    #expect(behavior.state.needs.energy > energyAfterFiveMinutes)

    behavior.tick(at: date(2026, 1, 2, 7, 1), calendar: utc) // morning arrives
    #expect(behavior.state.activity != .sleep, "pet wakes once night ends")
}

@Test func backwardClockIsANoOp() {
    let lastUpdated = date(2026, 1, 1, 12)
    var behavior = PetBehavior(state: PetState(needs: PetNeeds(hunger: 40), activity: .idle, lastUpdated: lastUpdated))
    let before = behavior.state
    behavior.tick(at: lastUpdated.addingTimeInterval(-3600), calendar: utc)
    #expect(behavior.state == before, "a clock moving backward must not mutate needs or lastUpdated")
}

@Test func offlineCatchUpIsCappedAtTwelveHours() {
    let start = date(2026, 1, 1, 12)
    var capped = PetBehavior(state: PetState(needs: PetNeeds(cleanliness: 100), activity: .idle, lastUpdated: start))
    capped.tick(at: start.addingTimeInterval(30 * 3600), calendar: utc) // 30h real gap

    var uncappedReference = PetBehavior(state: PetState(needs: PetNeeds(cleanliness: 100), activity: .idle, lastUpdated: start))
    uncappedReference.tick(at: start.addingTimeInterval(12 * 3600), calendar: utc) // exactly 12h

    #expect(abs(capped.state.needs.cleanliness - uncappedReference.state.needs.cleanliness) < 0.5)
    #expect(capped.state.needs.cleanliness > 0, "a genuinely uncapped 30h drift would have hit the floor")
    #expect(capped.state.lastUpdated == start.addingTimeInterval(30 * 3600), "lastUpdated stamps the real time, not the capped horizon")
}

@Test func needsStayWithinFiniteBounds() {
    var behavior = PetBehavior(state: PetState(needs: PetNeeds(energy: 5), activity: .idle, lastUpdated: date(2026, 1, 1, 12)))
    behavior.tick(at: date(2026, 1, 3, 12), calendar: utc) // far beyond any single meter's full range
    for value in [
        behavior.state.needs.hunger, behavior.state.needs.thirst, behavior.state.needs.energy,
        behavior.state.needs.fun, behavior.state.needs.cleanliness, behavior.state.needs.affection,
    ] {
        #expect(value.isFinite)
        #expect(PetNeeds.bounds.contains(value))
    }
}

@Test func unattendedDaytimePetSettlesNapsAndWakesForCare() {
    let start = date(2026, 1, 1, 12)
    var pet = PetBehavior(state: PetState(lastUpdated: start))
    pet.tick(at: start.addingTimeInterval(21 * 60), calendar: utc)
    #expect(pet.state.activity == .sit)
    pet.tick(at: start.addingTimeInterval(26 * 60), calendar: utc)
    #expect(pet.state.activity == .sleep)
    let returned = start.addingTimeInterval(27 * 60)
    pet.interact(.call, at: returned)
    pet.tick(at: returned.addingTimeInterval(3), calendar: utc)
    #expect(pet.state.activity == .idle)
    #expect(pet.state.lastInteractionAt == returned)
}

@Test func legacySaveGainsPresenceHistoryWithoutLosingNeeds() throws {
    let original = PetState(needs: PetNeeds(hunger: 42), lastUpdated: date(2026, 1, 1, 12))
    let encoded = try JSONEncoder().encode(original)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "lastInteractionAt")
    let legacy = try JSONDecoder().decode(PetState.self, from: JSONSerialization.data(withJSONObject: object))
    let pet = PetBehavior(state: legacy)
    #expect(pet.state.needs.hunger == 42)
    #expect(pet.state.lastInteractionAt == original.lastUpdated)
}

@Test func hoverAttentionDoesNotCancelMealsOrRestoreHunger() {
    let start = date(2026, 1, 1, 12)
    var pet = PetBehavior(state: PetState(needs: PetNeeds(hunger: 70, affection: 50), lastUpdated: start))
    pet.noticeAttention(at: start, seconds: 100)
    #expect(pet.state.needs.hunger == 70)
    #expect(pet.state.needs.affection <= 50.1)
    pet.interact(.eat, at: start)
    pet.noticeAttention(at: start.addingTimeInterval(1), seconds: 1)
    #expect(pet.state.activity == .eat)
    #expect(pet.isInteracting)
}
