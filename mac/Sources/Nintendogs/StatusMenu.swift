import SwiftUI

struct StatusMenu: View {
    @ObservedObject var delegate: AppDelegate

    var body: some View {
        Text(delegate.status)
        Divider()
        Button("Show / hide pet") { delegate.togglePanel() }
        Button("Rotate pet 90°") { delegate.panel?.sceneHost.rotatePet() }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}
