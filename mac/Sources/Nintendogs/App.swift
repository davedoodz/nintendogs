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
    @Published var status = "Loading…"
    @Published var needs = PetNeeds()
    @Published var failure: String?
    private var behavior: PetBehavior?
    private var animations: AnimationController?
    private let store = PetStore(url: PetStore.defaultURL)
    private var loop: Task<Void, Never>?
    private var lastTick = Date()
    private var lastSave = Date()
    private var previewing = false

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
            panel.sceneHost.setPet(loaded.node)
            animations = try AnimationController(root: loaded.node)
            panel.sceneHost.onCall = { [weak self] in self?.interact(.call) }
            panel.sceneHost.onStroke = { [weak self] in self?.interact(.pet) }
            refresh()
            panel.orderFrontRegardless()
            lastTick = now
            lastSave = now
            loop = Task { [weak self] in
                var previous = ProcessInfo.processInfo.systemUptime
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
                    guard let self else { break }
                    let uptime = ProcessInfo.processInfo.systemUptime
                    self.animations?.update(deltaTime: max(0, uptime - previous))
                    self.panel?.sceneHost.sceneTime = self.animations?.sceneTime ?? 0
                    previous = uptime
                    let now = Date()
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
        previewing = false
        behavior?.interact(activity, at: Date())
        refresh()
        save()
    }

    func preview(_ name: String) {
        do {
            try animations?.playClip(named: name)
            previewing = true
            status = "Preview: \(name)"
            panel?.sceneHost.setAnimationActive(true)
        } catch { failure = error.localizedDescription }
    }

    private func refresh() {
        guard let behavior else { return }
        needs = behavior.state.needs
        if !previewing {
            animations?.play(behavior.state.activity, careRequest: behavior.state.careRequest != nil)
            status = behavior.state.careRequest ?? behavior.state.activity.rawValue.capitalized
            panel?.sceneHost.showCare(activity: behavior.state.activity, needs: needs)
        }
        panel?.sceneHost.setAnimationActive(panel?.isVisible == true && animations?.isAnimating == true)
    }

    private func save() {
        guard let behavior else { return }
        do { try store.save(behavior.state); failure = nil }
        catch { failure = "Save failed: \(error.localizedDescription)" }
    }

    func applicationWillTerminate(_ notification: Notification) {
        loop?.cancel()
        behavior?.tick(at: Date())
        save()
    }

    func togglePanel() {
        guard let panel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        refresh()
    }
}
