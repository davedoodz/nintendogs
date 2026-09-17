import Foundation

/// Converts pointer samples into one held petting lifecycle. SceneHost remains responsible
/// for deciding whether each sample hits the animated head; this type owns only movement
/// thresholds, stroke cadence and balanced begin/end delivery.
struct PettingGesture {
    enum Event: Equatable {
        case began
        case stroke
        case ended
    }

    static let startDistance: CGFloat = 4
    static let strokeDistance: CGFloat = 18
    static let strokeInterval: TimeInterval = 0.18

    private(set) var beganOnHead = false
    private(set) var isActive = false
    private var trackingHead = false
    private var startPoint: CGPoint?
    private var lastPoint: CGPoint?
    private var accumulatedDistance: CGFloat = 0
    private var lastStrokeTime: TimeInterval = 0

    mutating func begin(at point: CGPoint, overHead: Bool) {
        reset()
        startPoint = point
        lastPoint = point
        beganOnHead = overHead
        trackingHead = overHead
    }

    mutating func drag(to point: CGPoint, overHead: Bool, at time: TimeInterval) -> Event? {
        guard let startPoint else { return nil }
        let segment = lastPoint.map { hypot(point.x - $0.x, point.y - $0.y) } ?? 0
        lastPoint = point
        let total = hypot(point.x - startPoint.x, point.y - startPoint.y)
        if !trackingHead {
            guard beganOnHead, overHead else { return nil }
            trackingHead = true
            accumulatedDistance = 0
        }
        guard overHead else {
            trackingHead = false
            accumulatedDistance = 0
            return nil
        }
        accumulatedDistance += segment
        if !isActive, total >= Self.startDistance {
            isActive = true
            accumulatedDistance = 0
            lastStrokeTime = time
            return .began
        }
        if isActive,
           accumulatedDistance >= Self.strokeDistance,
           time - lastStrokeTime >= Self.strokeInterval {
            accumulatedDistance = 0
            lastStrokeTime = time
            return .stroke
        }
        return nil
    }

    mutating func end() -> Event? {
        let event = finishIfNeeded()
        reset()
        return event
    }

    private mutating func finishIfNeeded() -> Event? {
        guard isActive else { return nil }
        isActive = false
        return .ended
    }

    private mutating func reset() {
        beganOnHead = false
        trackingHead = false
        isActive = false
        startPoint = nil
        lastPoint = nil
        accumulatedDistance = 0
        lastStrokeTime = 0
    }
}
