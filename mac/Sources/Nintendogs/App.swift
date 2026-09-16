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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let panel = PetPanel()
        self.panel = panel
        panel.orderFrontRegardless()
        do {
            guard let url = AssetLocator.shibaModel() else {
                throw AssetLocator.MissingAsset(message: "Shiba assets not found. Run `npm run assets:mac`.")
            }
            let loaded = try ModelLoader.load(url, targetHeight: SceneHost.dogHeight)
            panel.sceneHost.setPet(loaded.node)
            guard let clipURL = AssetLocator.shibaClip(named: "shiba_test_tailwag") else {
                throw AssetLocator.MissingAsset(message: "Tail-wag clip not found.")
            }
            let clip = try AnimationLoader.apply(
                clipURL,
                to: loaded.node,
                key: "tailwag",
                repeats: true
            )
            panel.sceneHost.setAnimationActive(true)
            status = String(
                format: "Black Shiba loaded · tail wag %.1fs on %@",
                clip.duration,
                clip.targetNames.joined(separator: ", ")
            )
        } catch {
            status = "Load failed: \(error.localizedDescription)"
        }
    }

    func togglePanel() {
        guard let panel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
}
