import Testing
@testable import Nintendogs

@Test func pleasureMouthOpensBrieflyOncePerCycle() {
    #expect(ExpressionAnimator.pleasureMouthOpenAmount(at: 0) == 0)
    #expect(ExpressionAnimator.pleasureMouthOpenAmount(at: 0.71) == 0)
    #expect(ExpressionAnimator.pleasureMouthOpenAmount(at: 0.86) > 0.99)
    #expect(ExpressionAnimator.pleasureMouthOpenAmount(at: 1) < 0.000_001)
}
