import SwiftUI
import PetKit

@main
struct NintendogsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Shiba", systemImage: "pawprint.fill") {
            StatusMenu(delegate: delegate)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private(set) var panel: PetPanel?
    private var notchTray: NotchTrayPanel?
    private let heldItems = HeldItemSession()
    @Published var status = "Loading…"
    @Published var needs = PetNeeds()
    @Published var failure: String?
    private var behavior: PetBehavior?
    private var animations: AnimationController?
    private var ambient: AmbientDirector?
    private let store = PetStore(url: PetStore.defaultURL)
    private var loop: Task<Void, Never>?
    private var lastTick = Date()
    private var lastSave = Date()
    private var previewing = false
    @Published var wanderEnabled = true
    @Published var ambientFrequency = 1.0
    private var wanderCountdown: TimeInterval = 55
    private var presenceTime: TimeInterval = 0
    private var interactionTime = -Double.infinity
    private var wasHovering = false
    private var localHour = Calendar.current.component(.hour, from: Date())
    private var workspaceSleeping = false
    private var lastGreeting = -Double.infinity
    private var morningGreetingDay: Date?
    private var fetchSequence: FetchSequence?
    private var fetchPhase: FetchSequence.Phase?
    private var fetchIsThrowing = false
    private var fetchBallAttached = false
    private var ballExpiresAt: Date?
    private static let ballLifetime: TimeInterval = 5 * 60

    private func observePresence() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(suspendPresence), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(suspendPresence), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(suspendPresence), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(resumePresence), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(resumePresence), name: NSWorkspace.screensDidWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(resumePresence), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    }

    @objc private func suspendPresence() {
        workspaceSleeping = true
        panel?.sceneHost.stopWander()
        panel?.sceneHost.setAnimationActive(false)
        save()
    }

    @objc private func resumePresence() {
        workspaceSleeping = false
        let now = Date()
        behavior?.tick(at: now)
        lastTick = now
        let uptime = ProcessInfo.processInfo.systemUptime
        // Waking the display and session emits several notifications.
        if uptime - lastGreeting >= 15, behavior?.isRestingOnRequest == false {
            lastGreeting = uptime
            greet()
        }
        refresh()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do {
            let now = Date()
            let state = try store.load(at: now)
            var brain = PetBehavior(state: state)
            brain.tick(at: now)
            behavior = brain
            guard let url = AssetLocator.shibaModel() else {
                throw AssetLocator.MissingAsset(message: "Shiba assets not found.")
            }
            let loaded = try ModelLoader.load(url, targetHeight: SceneHost.dogHeight)
            let panel = PetPanel()
            self.panel = panel
            try panel.sceneHost.setPet(loaded.node, rawHeight: loaded.rawHeight)
            animations = try AnimationController(root: loaded.node)
            ambient = AmbientDirector(controller: animations!)
            panel.sceneHost.onCall = { [weak self] in self?.interact(.call) }
            panel.sceneHost.onStroke = { [weak self] in self?.interact(.pet) }
            panel.sceneHost.onPlay = { [weak self] in self?.interact(.play) }
            panel.sceneHost.onBallPicked = { [weak self] in
                self?.ballExpiresAt = nil
                self?.hold(.ball)
            }
            if let screen = NotchTrayPanel.preferredScreen() {
                let tray = NotchTrayPanel(screen: screen)
                tray.onPick = { [weak self] item in self?.hold(item) }
                tray.onNotchEntered = { [weak self] in self?.cancelHold() }
                tray.present()
                notchTray = tray
            }
            heldItems.onClick = { [weak self] point, screen in
                self?.throwHeld(at: point, on: screen)
            }
            heldItems.onCancel = { [weak self] in self?.cancelHold() }
            observePresence()
            refresh()
            if (7..<11).contains(localHour) { greet() }
            panel.orderFrontRegardless()
            lastTick = now
            lastSave = now
            loop = Task { [weak self] in
                var previous = ProcessInfo.processInfo.systemUptime
                while !Task.isCancelled {
                    let active = self?.workspaceSleeping == false && self?.panel?.isVisible == true
                    do { try await Task.sleep(for: .milliseconds(active ? 33 : 250)) } catch { break }
                    guard let self else { break }
                    let uptime = ProcessInfo.processInfo.systemUptime
                    let delta = min(0.1, max(0, uptime - previous))
                    self.advancePresence(deltaTime: delta, active: !self.workspaceSleeping && self.panel?.isVisible == true)
                    previous = uptime
                    let now = Date()
                    if let expiry = self.ballExpiresAt, now >= expiry, self.fetchSequence == nil {
                        self.panel?.sceneHost.removeBall()
                        self.ballExpiresAt = nil
                    }
                    if now.timeIntervalSince(self.lastTick) >= 1 || now < self.lastTick {
                        self.behavior?.tick(at: now)
                        self.lastTick = now
                        self.refresh()
                    }
                    if now.timeIntervalSince(self.lastSave) >= 30 {
                        self.save()
                        self.lastSave = now
                    }
                }
            }
        } catch {
            failure = error.localizedDescription
            status = "Unable to start care loop"
        }
    }

    func interact(_ activity: PetActivity) {
        guard behavior != nil else { return }
        if fetchSequence != nil { cancelFetch() }
        previewing = false
        interactionTime = presenceTime
        wasHovering = false
        ambient?.setAttention(false)
        panel?.sceneHost.stopWander()
        behavior?.interact(activity, at: Date())
        if let behavior {
            animations?.play(behavior.state.activity, careRequest: behavior.state.careRequest != nil, restart: true)
        }
        refresh()
        save()
    }

    func preview(_ name: String) {
        do {
            try animations?.playClip(named: name)
            previewing = true
            panel?.sceneHost.stopWander()
            status = "Preview: \(name)"
            panel?.sceneHost.setAnimationActive(true)
        } catch { failure = error.localizedDescription }
    }

    private func refresh() {
        guard let behavior else { return }
        localHour = Calendar.current.component(.hour, from: Date())
        needs = behavior.state.needs
        if !previewing {
            if fetchSequence == nil {
                animations?.play(behavior.state.activity, careRequest: behavior.state.careRequest != nil)
            }
            if fetchSequence != nil {
                status = fetchIsThrowing ? "Throwing" : "Fetching"
            } else if let request = behavior.state.careRequest {
                status = request
            } else if panel?.sceneHost.isWandering == true {
                status = "Exploring"
            } else if panel?.sceneHost.cursorAttention == true && !behavior.isInteracting && behavior.state.activity != .sleep {
                status = "Watching you"
            } else {
                status = behavior.state.activity.rawValue.capitalized
            }
            panel?.sceneHost.showCare(activity: behavior.state.activity, needs: needs)
        }
        panel?.sceneHost.setAnimationActive(!workspaceSleeping && panel?.isVisible == true && animations?.isAnimating == true)
    }

    /// Foreground animation time never includes hidden or system-sleep gaps.
    func advancePresence(deltaTime: TimeInterval, active: Bool, cursorOverride: CGPoint? = nil) {
        guard active, deltaTime > 0, let panel, let animations, let ambient, let brain = behavior else { return }
        let dt = min(deltaTime, 0.1)
        let host = panel.sceneHost
        presenceTime += dt
        if fetchSequence != nil {
            advanceFetch(by: dt, host: host, animations: animations)
            return
        }
        host.wanderEnabled = wanderEnabled
        let activity = brain.state.activity
        let suppressed = previewing || brain.isInteracting || brain.isRestingOnRequest
        if suppressed || !wanderEnabled {
            host.stopWander()
            animations.endLocomotion()
        }
        let isGaitPlaying = animations.currentClip == AnimationController.Locomotion.walk.rawValue
            || animations.currentClip == AnimationController.Locomotion.run.rawValue
        host.updatePresence(deltaTime: dt, activity: previewing ? .sleep : activity,
                            wandering: isGaitPlaying && !suppressed, cursorOverride: cursorOverride)
        if !previewing, host.cursorAttention != wasHovering {
            wasHovering = host.cursorAttention
            ambient.setAttention(wasHovering)
        }
        if !suppressed, host.cursorAttention {
            host.stopWander()
            animations.endLocomotion()
            behavior?.noticeAttention(at: Date(), seconds: dt)
        }
        if !host.isWandering, animations.isLocomoting { animations.endLocomotion() }
        if !suppressed, !host.cursorAttention, !host.isWandering,
           activity == .idle || (activity == .sit && brain.state.careRequest != nil) {
            wanderCountdown -= dt
            if wanderEnabled, wanderCountdown <= 0, presenceTime - interactionTime > 3 {
                let towardBowl = brain.state.careRequest != nil
                let running = brain.state.needs.fun > 75 && !towardBowl && Bool.random()
                host.startWander(running: running, towardBowl: towardBowl)
                if host.isWandering, animations.startLocomotion(host.isRunning ? .run : .walk) {
                    wanderCountdown = Double.random(in: 45...120)
                } else {
                    host.stopWander()
                    wanderCountdown = 1
                }
            }
        }
        ambient.frequencyMultiplier = ambientFrequency
        ambient.setExternalLocomotion(host.isWandering)
        ambient.update(deltaTime: dt, needs: brain.state.needs, activity: activity,
                       careRequest: brain.state.careRequest != nil, suppressed: suppressed, hour: localHour)
        animations.update(deltaTime: dt)
        host.sceneTime = animations.sceneTime
        host.setAnimationActive(animations.isAnimating)
    }

    private func greet() {
        guard behavior != nil, !previewing else { return }
        let now = Date()
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: now)
        let morning = (7..<11).contains(calendar.component(.hour, from: now)) && morningGreetingDay != day
        if morning {
            morningGreetingDay = day
            animations?.preferStretchOnNextWake()
        }
        panel?.sceneHost.stopWander()
        animations?.endLocomotion()
        behavior?.interact(.idle, at: now)
        refresh()
        ambient?.greet(morning: morning)
    }

    func hold(_ item: ItemSprite) {
        notchTray?.collapseTray()
        if let screen = NotchTrayPanel.preferredScreen() {
            heldItems.cancelRect = NotchTrayPanel.notchRect(on: screen)
        }
        heldItems.begin(item)
    }

    func cancelHold() {
        heldItems.end()
    }

    /// Accepts the held item only on the display that owns the pet panel. Other displays keep
    /// the item held (the v1 arena is intentionally single-display).
    func throwHeld(at point: NSPoint, on screen: NSScreen) {
        guard screen === panel?.screen, let item = heldItems.item, let panel else { return }
        switch item {
        case .ball:
            panel.enterArena(on: screen)
            guard let ground = panel.sceneHost.groundPoint(forScreenPoint: point) else {
                panel.leaveArena()
                return
            }
            heldItems.end()
            beginFetch(to: ground)
        case .foodBowl, .waterBowl:
            heldItems.end()
            ballExpiresAt = nil
            panel.sceneHost.removeBall()
            interact(item == .foodBowl ? .eat : .drink)
        }
    }

    private func beginFetch(to landing: SIMD2<Double>) {
        guard let panel, let animations else { return }
        previewing = false
        ballExpiresAt = nil
        panel.sceneHost.stopWander()
        animations.endLocomotion()
        ambient?.setAttention(false)
        let home = panel.sceneHost.petPosition
        let durations = FetchSequence.ClipDurations(
            pickup: animations.duration(ofClip: "shiba_fetch_pickup") ?? 2.5,
            happy: animations.duration(ofClip: "shiba_happy") ?? 2.5
        )
        let sequence = FetchSequence(
            home: SIMD2(Double(home.x), Double(home.z)),
            ball: landing,
            clipDurations: durations
        )
        fetchSequence = sequence
        fetchPhase = nil
        fetchBallAttached = false
        fetchIsThrowing = true
        status = "Throwing"
        panel.sceneHost.throwBall(to: landing)
    }

    private func advanceFetch(by dt: TimeInterval, host: SceneHost, animations: AnimationController) {
        if fetchIsThrowing {
            if host.advanceBallThrow(by: dt), let sequence = fetchSequence {
                fetchIsThrowing = false
                behavior?.interact(.fetch, at: Date(), duration: sequence.totalDuration)
                refresh()
            }
            animations.update(deltaTime: dt)
            host.sceneTime = animations.sceneTime
            host.setAnimationActive(true)
            return
        }
        guard var sequence = fetchSequence else { return }
        sequence.advance(by: dt)
        fetchSequence = sequence
        host.setPetPose(position: sequence.position, heading: sequence.heading)
        if fetchBallAttached != sequence.ballAttached {
            host.attachBall(toMouth: sequence.ballAttached)
            fetchBallAttached = sequence.ballAttached
        }
        if !sequence.ballAttached {
            host.placeBall(at: sequence.ballPosition)
        }
        if fetchPhase != sequence.phase {
            fetchPhase = sequence.phase
            if let clip = sequence.clip {
                do { try animations.playClip(named: clip) }
                catch { failure = error.localizedDescription }
            }
        }
        animations.update(deltaTime: dt)
        host.sceneTime = animations.sceneTime
        host.setAnimationActive(animations.isAnimating)
        if sequence.phase == .done {
            finishFetch(sequence)
        }
    }

    private func finishFetch(_ sequence: FetchSequence) {
        guard let panel else { return }
        panel.sceneHost.attachBall(toMouth: false)
        panel.sceneHost.placeBall(at: sequence.ballPosition)
        panel.sceneHost.setPetPose(position: sequence.position, heading: sequence.heading)
        panel.leaveArena()
        fetchSequence = nil
        fetchPhase = nil
        fetchIsThrowing = false
        fetchBallAttached = false
        ballExpiresAt = Date().addingTimeInterval(Self.ballLifetime)
        animations?.play(.idle, restart: true)
        refresh()
        save()
    }

    private func cancelFetch() {
        guard fetchSequence != nil, let panel else { return }
        let restingBall = panel.sceneHost.ballGroundPosition
        panel.sceneHost.attachBall(toMouth: false)
        if let restingBall { panel.sceneHost.placeBall(at: restingBall) }
        panel.leaveArena()
        fetchSequence = nil
        fetchPhase = nil
        fetchIsThrowing = false
        fetchBallAttached = false
        ballExpiresAt = Date().addingTimeInterval(Self.ballLifetime)
        behavior?.interact(.idle, at: Date())
        animations?.play(.idle, restart: true)
    }

    private func save() {
        guard let behavior else { return }
        do { try store.save(behavior.state); failure = nil }
        catch { failure = "Save failed: \(error.localizedDescription)" }
    }

    func applicationWillTerminate(_ notification: Notification) {
        loop?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        behavior?.tick(at: Date())
        save()
    }

    func togglePanel() {
        guard let panel else { return }
        panel.sceneHost.stopWander()
        animations?.endLocomotion()
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        refresh()
    }
}
