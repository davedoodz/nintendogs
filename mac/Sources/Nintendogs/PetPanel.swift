import AppKit

/// Frameless, transparent, always-on-top panel that never takes keyboard focus (R1).
final class PetPanel: NSPanel {
    let sceneHost = SceneHost(frame: .zero)

    init() {
        let size = NSSize(width: 720, height: 480)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screen.maxX - size.width - 24, y: screen.minY + 24)
        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        minSize = NSSize(width: 360, height: 240)
        maxSize = NSSize(width: 1080, height: 720)
        setFrameUsingName("PetPanel")
        setFrameAutosaveName("PetPanel")
        contentView = sceneHost
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
