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
        contentAspectRatio = NSSize(width: 3, height: 2)
        setFrameUsingName("PetPanel")
        setFrameAutosaveName("PetPanel")
        contentView = sceneHost
    }

    /// Home frame recorded while the panel is expanded to the fetch arena.
    private var arenaHomeFrame: NSRect?
    private var arenaHomeMaxSize: NSSize?

    var isInArena: Bool { arenaHomeFrame != nil }

    /// Expands to cover `screen` so a throw can land anywhere on the desktop, while the scene
    /// keeps the home world-to-screen mapping exactly (KTD4): the dog's on-screen size and
    /// home spot do not move.
    func enterArena(on screen: NSScreen) {
        guard arenaHomeFrame == nil else { return }
        let home = frame
        let arena = screen.frame
        arenaHomeFrame = home
        arenaHomeMaxSize = maxSize
        // The arena frame must never become the remembered frame.
        setFrameAutosaveName("")
        // `setFrame` honours both of these, so they have to come off first.
        maxSize = arena.size
        contentAspectRatio = .zero
        ignoresMouseEvents = true
        // Projection first: resizing with the home projection still applied would render one
        // frame at the wrong scale.
        sceneHost.applyHomeProjection(home: home, arena: arena)
        setFrame(arena, display: true)
    }

    /// Once the throw overlay is gone, let dog gestures cancel the active fetch. The arena
    /// remains nonactivating; clicks outside the rendered dog are simply ignored by SceneHost.
    func enableArenaInteractions() {
        guard isInArena else { return }
        ignoresMouseEvents = false
    }

    /// Reverses `enterArena` in the opposite order.
    ///
    /// Re-arming the autosave name has to come *before* the frame is restored: AppKit applies
    /// the stored frame the moment a name is set, which otherwise teleports the panel to
    /// whatever was last saved — including an off-screen frame from a display that is no
    /// longer attached. Setting the name first, then the home frame, then saving it, leaves
    /// the stored frame equal to the home frame the arena was entered from.
    func leaveArena() {
        guard let home = arenaHomeFrame else { return }
        arenaHomeFrame = nil
        contentAspectRatio = NSSize(width: 3, height: 2)
        if let arenaHomeMaxSize { maxSize = arenaHomeMaxSize }
        arenaHomeMaxSize = nil
        setFrameAutosaveName("PetPanel")
        setFrame(home, display: true)
        saveFrame(usingName: "PetPanel")
        sceneHost.restoreProjection()
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
