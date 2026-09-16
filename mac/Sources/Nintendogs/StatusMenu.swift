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
        Divider()
        Button("Give food") { delegate.interact(.eat) }
        Button("Give water") { delegate.interact(.drink) }
        Button("Pet Shiba") { delegate.interact(.pet) }
        Button("Play together") { delegate.interact(.play) }
        Button("Call / wake") { delegate.interact(.call) }
        Button("Rest") { delegate.interact(.sleep) }
        Button("Resume autonomous behavior") { delegate.interact(.idle) }
        Menu("Preview animations") {
            ForEach(AnimationController.clipNames, id: \.self) { clip in
                Button(clip.replacingOccurrences(of: "shiba_", with: "")) { delegate.preview(clip) }
            }
        }
        Divider()
        Button("Show / hide pet") { delegate.togglePanel() }
        Button("Rotate pet 90°") { delegate.panel?.sceneHost.rotatePet() }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}
