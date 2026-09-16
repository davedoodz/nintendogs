/// Coarse emotional state used only to drive visible expression layers.
/// Needs remain the durable source of truth; this type is intentionally ephemeral.
public enum PetMood: String, Sendable, Equatable {
    case calm, content, excited, alert, low, asleep
}

public enum PetEyeState: String, CaseIterable, Sendable, Hashable {
    case open, closed, squint, wide
}

/// One frame's target values for additive face/tail/life motion.
public struct PetExpressionTargets: Sendable, Equatable {
    public let mood: PetMood
    public let eyes: PetEyeState
    public let tailPitchDegrees: Double
    public let tailTipPitchDegrees: Double
    public let wagAmplitudeDegrees: Double
    public let wagFrequencyHz: Double
    public let wagBiasDegrees: Double
    public let mouthOpenDegrees: Double
    public let tongueOut: Double
    public let breathingHz: Double
    public let breathingDegrees: Double
    public let earsBackDegrees: Double

    public init(
        mood: PetMood,
        eyes: PetEyeState,
        tailPitchDegrees: Double,
        tailTipPitchDegrees: Double,
        wagAmplitudeDegrees: Double,
        wagFrequencyHz: Double,
        wagBiasDegrees: Double,
        mouthOpenDegrees: Double,
        tongueOut: Double,
        breathingHz: Double,
        breathingDegrees: Double,
        earsBackDegrees: Double
    ) {
        self.mood = mood
        self.eyes = eyes
        self.tailPitchDegrees = tailPitchDegrees
        self.tailTipPitchDegrees = tailTipPitchDegrees
        self.wagAmplitudeDegrees = wagAmplitudeDegrees
        self.wagFrequencyHz = wagFrequencyHz
        self.wagBiasDegrees = wagBiasDegrees
        self.mouthOpenDegrees = mouthOpenDegrees
        self.tongueOut = tongueOut
        self.breathingHz = breathingHz
        self.breathingDegrees = breathingDegrees
        self.earsBackDegrees = earsBackDegrees
    }
}

public enum PetExpression {
    private static let asleep = PetExpressionTargets(
        mood: .asleep, eyes: .closed,
        tailPitchDegrees: 0, tailTipPitchDegrees: 0,
        wagAmplitudeDegrees: 0, wagFrequencyHz: 0, wagBiasDegrees: 0,
        mouthOpenDegrees: 0, tongueOut: 0,
        breathingHz: 0.35, breathingDegrees: 0.7, earsBackDegrees: -4
    )
    private static let alert = PetExpressionTargets(
        mood: .alert, eyes: .wide,
        tailPitchDegrees: -16, tailTipPitchDegrees: -20,
        wagAmplitudeDegrees: 0, wagFrequencyHz: 0, wagBiasDegrees: 0,
        mouthOpenDegrees: 0, tongueOut: 0,
        breathingHz: 0.65, breathingDegrees: 0.35, earsBackDegrees: 8
    )
    private static let petting = PetExpressionTargets(
        mood: .content, eyes: .closed,
        tailPitchDegrees: -12, tailTipPitchDegrees: -18,
        wagAmplitudeDegrees: 22, wagFrequencyHz: 3.5, wagBiasDegrees: 6,
        mouthOpenDegrees: 12, tongueOut: 0.2,
        breathingHz: 0.7, breathingDegrees: 0.65, earsBackDegrees: -18
    )
    private static let running = PetExpressionTargets(
        mood: .excited, eyes: .open,
        tailPitchDegrees: -10, tailTipPitchDegrees: -14,
        wagAmplitudeDegrees: 8, wagFrequencyHz: 2.2, wagBiasDegrees: 0,
        mouthOpenDegrees: 8, tongueOut: 0.3,
        breathingHz: 0.8, breathingDegrees: 0.75, earsBackDegrees: -6
    )
    private static let excited = PetExpressionTargets(
        mood: .excited, eyes: .open,
        tailPitchDegrees: -14, tailTipPitchDegrees: -16,
        wagAmplitudeDegrees: 24, wagFrequencyHz: 4, wagBiasDegrees: 6,
        mouthOpenDegrees: 8, tongueOut: 0.3,
        breathingHz: 0.8, breathingDegrees: 0.75, earsBackDegrees: -6
    )
    private static let low = PetExpressionTargets(
        mood: .low, eyes: .squint,
        tailPitchDegrees: 25, tailTipPitchDegrees: 10,
        wagAmplitudeDegrees: 3, wagFrequencyHz: 0.4, wagBiasDegrees: -3,
        mouthOpenDegrees: 0, tongueOut: 0,
        breathingHz: 0.4, breathingDegrees: 0.35, earsBackDegrees: -8
    )
    private static let content = PetExpressionTargets(
        mood: .content, eyes: .open,
        tailPitchDegrees: -12, tailTipPitchDegrees: -18,
        wagAmplitudeDegrees: 12, wagFrequencyHz: 1.2, wagBiasDegrees: 4,
        mouthOpenDegrees: 0, tongueOut: 0,
        breathingHz: 0.55, breathingDegrees: 0.55, earsBackDegrees: -4
    )
    private static let calm = PetExpressionTargets(
        mood: .calm, eyes: .open,
        tailPitchDegrees: -8, tailTipPitchDegrees: -14,
        wagAmplitudeDegrees: 3.6, wagFrequencyHz: 0.7, wagBiasDegrees: 0,
        mouthOpenDegrees: 0, tongueOut: 0,
        breathingHz: 0.5, breathingDegrees: 0.5, earsBackDegrees: 0
    )
    private static let attentiveCalm = PetExpressionTargets(
        mood: .calm, eyes: .open,
        tailPitchDegrees: -8, tailTipPitchDegrees: -14,
        wagAmplitudeDegrees: 6, wagFrequencyHz: 0.7, wagBiasDegrees: 0,
        mouthOpenDegrees: 0, tongueOut: 0,
        breathingHz: 0.5, breathingDegrees: 0.5, earsBackDegrees: 0
    )

    /// Maps durable needs plus immediate context to expression-layer targets.
    /// `engaged` means direct attention or interaction within the recent window.
    public static func targets(
        needs: PetNeeds,
        activity: PetActivity,
        engaged: Bool,
        running: Bool
    ) -> PetExpressionTargets {
        if activity == .sleep { return asleep }
        if activity == .call { return alert }
        if activity == .pet { return petting }
        if running { return self.running }
        if activity == .play || activity == .fetch { return excited }

        let hasCriticalNeed = needs.energy < 25
            || needs.hunger > 75
            || needs.thirst > 75
            || needs.fun < 25
        if hasCriticalNeed { return low }

        // Affection stays high for the pet's lifetime. Only direct/recent engagement
        // promotes it to the fast expression; passive content stays cheap at 10 Hz.
        if needs.affection > 65 {
            return engaged ? excited : content
        }
        return engaged ? attentiveCalm : calm
    }
}
