import SwiftUI
import PetKit

struct StatusMenu: View {
    @ObservedObject var delegate: AppDelegate


    var body: some View {
        Text("Shiba · \(delegate.status)")
        if let failure = delegate.failure { Text(failure) }
        Divider()
        Text("Hunger: \(Int(delegate.needs.hunger))% · Thirst: \(Int(delegate.needs.thirst))%")
        Text("Energy: \(Int(delegate.needs.energy))% · Fun: \(Int(delegate.needs.fun))%")
        Text("Cleanliness: \(Int(delegate.needs.cleanliness))% · Affection: \(Int(delegate.needs.affection))%")
        Text("Hover to say hello · Stroke the head to pet")
        Text("Whistle from any app: \(GlobalHotKey.whistleDisplayName)")
        Divider()
        Button("Give food") { delegate.interact(.eat) }
        Button("Give water") { delegate.interact(.drink) }
        Button("Pet Shiba") { delegate.interact(.pet) }
        Button("Play together") { delegate.interact(.play) }
        Button("Whistle / wake (\(GlobalHotKey.whistleDisplayName))") { delegate.whistle() }
        Button("Rest") { delegate.interact(.sleep) }
        Button("Resume autonomous behavior") { delegate.interact(.idle) }
        Menu("Personality") {
            Toggle("Explore the panel", isOn: $delegate.wanderEnabled)
            Picker("Activity", selection: $delegate.ambientFrequency) {
                Text("Calm").tag(0.65)
                Text("Natural").tag(1.0)
                Text("Lively").tag(1.5)
            }
        }
        Menu("Animation diagnostics") {
            ForEach(AnimationController.clipNames, id: \.self) { clip in
                Button(clip.replacingOccurrences(of: "shiba_", with: "")) { delegate.preview(clip) }
            }
            Button("Return to autonomous behavior") { delegate.interact(.idle) }
        }
        Divider()
        Button("Show / hide pet") { delegate.togglePanel() }
        Button("Rotate pet 90°") { delegate.panel?.sceneHost.rotatePet() }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}
