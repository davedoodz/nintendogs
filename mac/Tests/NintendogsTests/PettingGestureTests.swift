import CoreGraphics
import Testing
@testable import Nintendogs

@Test func headRubBeginsStrokesAndEndsExactlyOnce() {
    var gesture = PettingGesture()
    gesture.begin(at: .zero, overHead: true)

    #expect(gesture.drag(to: CGPoint(x: 3, y: 0), overHead: true, at: 0.1) == nil)
    #expect(gesture.drag(to: CGPoint(x: 5, y: 0), overHead: true, at: 0.2) == .began)
    #expect(gesture.drag(to: CGPoint(x: 25, y: 0), overHead: true, at: 0.5) == .stroke)
    #expect(gesture.end() == .ended)
    #expect(gesture.end() == nil)
}

@Test func strokeRequiresBothDistanceAndElapsedTime() {
    var gesture = PettingGesture()
    gesture.begin(at: .zero, overHead: true)
    #expect(gesture.drag(to: CGPoint(x: 5, y: 0), overHead: true, at: 0.2) == .began)

    #expect(gesture.drag(to: CGPoint(x: 30, y: 0), overHead: true, at: 0.25) == nil)
    #expect(gesture.drag(to: CGPoint(x: 31, y: 0), overHead: true, at: 0.5) == .stroke)
    #expect(gesture.drag(to: CGPoint(x: 40, y: 0), overHead: true, at: 0.8) == nil)
    #expect(gesture.drag(to: CGPoint(x: 48, y: 0), overHead: true, at: 1.1) == nil)
    #expect(gesture.drag(to: CGPoint(x: 49, y: 0), overHead: true, at: 1.4) == .stroke)
}

@Test func slightHeadPressDriftRemainsReservedForPetting() {
    var gesture = PettingGesture()
    gesture.begin(at: .zero, overHead: true)

    #expect(gesture.drag(to: CGPoint(x: 3, y: 0), overHead: false, at: 0.1) == nil)
    #expect(gesture.beganOnHead)
    #expect(gesture.end() == nil)
}

@Test func leavingAndReenteringHeadKeepsOneHeldLifecycle() {
    var gesture = PettingGesture()
    gesture.begin(at: .zero, overHead: true)
    #expect(gesture.drag(to: CGPoint(x: 5, y: 0), overHead: true, at: 0.2) == .began)

    #expect(gesture.drag(to: CGPoint(x: 8, y: 0), overHead: false, at: 0.3) == nil)
    #expect(gesture.drag(to: CGPoint(x: 12, y: 0), overHead: true, at: 0.5) == nil)
    #expect(gesture.end() == .ended)
    #expect(gesture.end() == nil)
}

@Test func bodyDragNeverStartsPetting() {
    var gesture = PettingGesture()
    gesture.begin(at: .zero, overHead: false)

    #expect(gesture.drag(to: CGPoint(x: 40, y: 0), overHead: false, at: 1) == nil)
    #expect(gesture.end() == nil)
}
