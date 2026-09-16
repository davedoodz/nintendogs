import SwiftUI

/// Contents of the notch tray (R1, R3): a black panel continuous with the notch, one cell per
/// object. The top band covers the notch itself so the drop-out reads as one shape.
struct TrayView: View {
    let items: [ItemSprite]
    /// Height of the notch (or the fallback hover strip) the tray hangs from.
    let notchHeight: CGFloat
    let trayHeight: CGFloat
    let onPick: (ItemSprite) -> Void

    @State private var hovered: ItemSprite?

    private static let cornerRadius: CGFloat = 13

    var body: some View {
        VStack(spacing: 0) {
            Color.black
                .frame(height: notchHeight)
            HStack(spacing: 2) {
                ForEach(items, id: \.self) { item in
                    cell(item)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
            .frame(height: trayHeight)
        }
        .background(Color.black)
        .clipShape(
            UnevenRoundedRectangle(
                bottomLeadingRadius: Self.cornerRadius,
                bottomTrailingRadius: Self.cornerRadius
            )
        )
    }

    private func cell(_ item: ItemSprite) -> some View {
        VStack(spacing: 4) {
            item.view
                .frame(width: 34, height: 34)
            Text(item.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(hovered == item ? 0.95 : 0.62))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(hovered == item ? 0.15 : 0))
        )
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                hovered = item
            } else if hovered == item {
                hovered = nil
            }
        }
        .onTapGesture { onPick(item) }
    }
}
