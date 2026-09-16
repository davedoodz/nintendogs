import AppKit
import SwiftUI

/// Black tray that drops out of the MacBook notch on hover (KTD1, R1-R3).
///
/// Collapsed, the panel is exactly the notch rect with an empty transparent content view: no
/// SwiftUI, no timers, nothing rendering (R13). Hovering installs the `TrayView` host and
/// animates the frame downward; leaving for `closeDelay` tears the host back down.
@MainActor
final class NotchTrayPanel: NSPanel {
    /// Height of the item row hanging below the notch.
    static let trayHeight: CGFloat = 92
    /// Hover strip used on Macs without a notch (R3).
    private static let fallbackStrip = NSSize(width: 200, height: 6)
    private static let closeDelay: TimeInterval = 0.4
    private static let openDuration: TimeInterval = 0.12

    /// An item was clicked. The tray is already collapsed when this fires.
    var onPick: ((ItemSprite) -> Void)?
    /// The cursor came back into the notch region: cancels a held item (R5).
    var onNotchEntered: (() -> Void)?

    /// True when the panel sits over a real notch rather than the fallback hover strip.
    let usesNotch: Bool

    private let collapsedFrame: NSRect
    private let expandedFrame: NSRect
    private let bandHeight: CGFloat
    private let hoverView = HoverView()
    private var host: NSHostingView<TrayView>?
    private var closeTimer: Timer?
    private(set) var isExpanded = false

    /// The notch rect in screen coordinates, or `nil` on a display without one.
    static func notchRect(on screen: NSScreen) -> NSRect? {
        let inset = screen.safeAreaInsets.top
        guard inset > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX
        else { return nil }
        return NSRect(
            x: left.maxX,
            y: screen.frame.maxY - inset,
            width: right.minX - left.maxX,
            height: inset
        )
    }

    /// Prefer a display that actually has a notch; otherwise the main display's top strip.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { notchRect(on: $0) != nil } ?? NSScreen.main
    }

    init(screen: NSScreen) {
        let notch = Self.notchRect(on: screen)
        usesNotch = notch != nil
        let collapsed = notch ?? NSRect(
            x: screen.frame.midX - Self.fallbackStrip.width / 2,
            y: screen.frame.maxY - Self.fallbackStrip.height,
            width: Self.fallbackStrip.width,
            height: Self.fallbackStrip.height
        )
        collapsedFrame = collapsed
        bandHeight = collapsed.height
        expandedFrame = NSRect(
            x: collapsed.minX,
            y: collapsed.maxY - (collapsed.height + Self.trayHeight),
            width: collapsed.width,
            height: collapsed.height + Self.trayHeight
        )
        super.init(
            contentRect: collapsed,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = false
        hoverView.onEnter = { [weak self] in self?.expand() }
        hoverView.onExit = { [weak self] in self?.scheduleCollapse() }
        contentView = hoverView
        setFrame(collapsed, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Show the collapsed panel without activating the app (R2).
    func present() {
        orderFrontRegardless()
    }

    private func expand() {
        closeTimer?.invalidate()
        closeTimer = nil
        onNotchEntered?()
        guard !isExpanded else { return }
        isExpanded = true
        let content = TrayView(
            items: ItemSprite.allCases,
            notchHeight: bandHeight,
            trayHeight: Self.trayHeight,
            onPick: { [weak self] item in self?.pick(item) }
        )
        let host = NSHostingView(rootView: content)
        // Pinned to the top with a constant height, so growing the window downward slides the
        // item row out from under the notch instead of squashing it.
        host.frame = NSRect(
            x: 0,
            y: collapsedFrame.height - expandedFrame.height,
            width: expandedFrame.width,
            height: expandedFrame.height
        )
        host.autoresizingMask = [.minYMargin]
        hoverView.addSubview(host)
        self.host = host
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.openDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(expandedFrame, display: true)
        }
    }

    private func scheduleCollapse() {
        guard isExpanded else { return }
        closeTimer?.invalidate()
        closeTimer = Timer.scheduledTimer(withTimeInterval: Self.closeDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.collapse() }
        }
    }

    private func pick(_ item: ItemSprite) {
        collapse()
        onPick?(item)
    }

    private func collapse() {
        closeTimer?.invalidate()
        closeTimer = nil
        guard isExpanded else { return }
        isExpanded = false
        setFrame(collapsedFrame, display: true)
        host?.removeFromSuperview()
        host = nil
    }

    /// Collapse from outside, e.g. when an item is thrown elsewhere.
    func collapseTray() {
        collapse()
    }
}

/// Transparent view that reports cursor entry and exit while the app is inactive.
private final class HoverView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var tracking: NSTrackingArea?

    override var isOpaque: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
