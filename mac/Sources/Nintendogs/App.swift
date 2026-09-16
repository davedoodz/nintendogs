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
                throw NSError(domain: "Nintendogs", code: 1, userInfo: [NSLocalizedDescriptionKey: "Shiba assets not found. Run `npm run assets:mac`."])
            }
            let loaded = try ModelLoader.load(url, targetHeight: SceneHost.dogHeight)
            panel.sceneHost.setPet(loaded.node)
            status = String(format: "Black Shiba loaded · %d skinned mesh · raw height %.1f", loaded.skinnedMeshCount, loaded.rawHeight)
        } catch {
            status = "Load failed: \(error.localizedDescription)"
        }
    }

    func togglePanel() {
        guard let panel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
}
