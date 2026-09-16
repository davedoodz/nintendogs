import AppKit

/// Full-screen capture overlay for a held item (KTD3, R4-R6).
///
/// One transparent panel per display sits above every app, turns the cursor into the item's
/// sprite, and swallows left clicks so they never reach Finder or anything else. Right-click,
/// or moving back into the notch, cancels. There is deliberately no key handling: a
/// non-activating panel cannot receive `keyDown`, and a global key monitor would need Input
/// Monitoring permission (R14).
@MainActor
final class HeldItemSession {
    private(set) var item: ItemSprite?
    /// Left click inside an overlay, in screen coordinates, with the display it landed on.
    var onClick: ((NSPoint, NSScreen) -> Void)?
    /// Right click, or cursor re-entering `cancelRect`.
    var onCancel: (() -> Void)?
    /// Screen-coordinate rect (the notch) whose re-entry cancels the hold (R5).
    var cancelRect: NSRect?

    private var overlays: [HeldItemOverlay] = []
    private var cursor: NSCursor?

    var isHolding: Bool { item != nil }

    func begin(_ item: ItemSprite) {
        end()
        self.item = item
        let cursor = NSCursor(image: item.cursorImage, hotSpot: ItemSprite.cursorHotSpot)
        self.cursor = cursor
        for screen in NSScreen.screens {
            let overlay = HeldItemOverlay(screen: screen, cursor: cursor)
            overlay.onMoved = { [weak self] point in self?.moved(to: point) }
            overlay.onClick = { [weak self] point, screen in self?.onClick?(point, screen) }
            overlay.onCancel = { [weak self] in self?.cancel() }
            overlay.orderFrontRegardless()
            overlays.append(overlay)
        }
        cursor.set()
    }

    /// Tear the overlays down and restore the arrow. Safe to call when nothing is held.
    func end() {
        guard !overlays.isEmpty || item != nil else { return }
        for overlay in overlays { overlay.orderOut(nil) }
        overlays.removeAll()
        item = nil
        cursor = nil
        NSCursor.arrow.set()
    }

    private func cancel() {
        guard isHolding else { return }
        end()
        onCancel?()
    }

    private func moved(to point: NSPoint) {
        guard let cancelRect, cancelRect.contains(point) else { return }
        cancel()
    }
}

/// One display's capture panel.
@MainActor
final class HeldItemOverlay: NSPanel {
    var onMoved: ((NSPoint) -> Void)? {
        get { overlayView.onMoved }
        set { overlayView.onMoved = newValue }
    }

    var onClick: ((NSPoint, NSScreen) -> Void)? {
        get { overlayView.onClick }
        set { overlayView.onClick = newValue }
    }

    var onCancel: (() -> Void)? {
        get { overlayView.onCancel }
        set { overlayView.onCancel = newValue }
    }

    private let overlayView: OverlayView

    init(screen: NSScreen, cursor: NSCursor) {
        overlayView = OverlayView(cursor: cursor, screen: screen)
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        // Not fully clear: a hair of alpha keeps the window in the event path on every macOS
        // compositor path while staying invisible.
        backgroundColor = NSColor(white: 0, alpha: 0.001)
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = true
        contentView = overlayView
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class OverlayView: NSView {
    var onMoved: ((NSPoint) -> Void)?
    var onClick: ((NSPoint, NSScreen) -> Void)?
    var onCancel: (() -> Void)?

    private let cursor: NSCursor
    private let overlayScreen: NSScreen
    private var tracking: NSTrackingArea?

    init(cursor: NSCursor, screen: NSScreen) {
        self.cursor = cursor
        overlayScreen = screen
        super.init(frame: screen.frame)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { cursor.set() }
    override func cursorUpdate(with event: NSEvent) { cursor.set() }

    override func mouseMoved(with event: NSEvent) {
        cursor.set()
        onMoved?(screenPoint(for: event))
    }

    override func mouseDragged(with event: NSEvent) {
        cursor.set()
        onMoved?(screenPoint(for: event))
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(screenPoint(for: event), overlayScreen)
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
    }
}
