import SwiftUI

private let kibbleBrown = Color(red: 0.55, green: 0.33, blue: 0.16)
private let waterBlue = Color(red: 0.31, green: 0.63, blue: 0.91)
private let bowlOrange = Color(red: 0.93, green: 0.51, blue: 0.20)
private let bowlBlue = Color(red: 0.36, green: 0.55, blue: 0.86)

/// The dog's objects, drawn as vector sprites (KTD2).
///
/// Every pixel of item art funnels through `view` and `cursorImage`, so swapping in real
/// Nintendogs item icons later is an asset-only change behind this one enum.
enum ItemSprite: String, CaseIterable, Sendable {
    case ball
    case foodBowl
    case waterBowl

    var label: String {
        switch self {
        case .ball: "Ball"
        case .foodBowl: "Food"
        case .waterBowl: "Water"
        }
    }

    /// Side of the cursor image in points; rendered at 2x so it stays crisp on Retina.
    static let cursorSide: CGFloat = 48

    @ViewBuilder
    @MainActor
    var view: some View {
        switch self {
        case .ball: BallSprite()
        case .foodBowl: BowlSprite(contents: kibbleBrown, rim: bowlOrange)
        case .waterBowl: BowlSprite(contents: waterBlue, rim: bowlBlue)
        }
    }

    /// Cursor art for a held item (KTD3). Rendered once per item and cached: the cursor is
    /// re-set on every `mouseMoved`, so this must never re-rasterize.
    @MainActor
    var cursorImage: NSImage {
        if let cached = Self.cursorCache[self] { return cached }
        let side = Self.cursorSide
        let renderer = ImageRenderer(content: view.frame(width: side, height: side))
        renderer.scale = 2
        let image: NSImage
        if let cgImage = renderer.cgImage {
            image = NSImage(cgImage: cgImage, size: NSSize(width: side, height: side))
        } else {
            image = NSImage(size: NSSize(width: side, height: side))
        }
        Self.cursorCache[self] = image
        return image
    }

    /// Cursor hot spot: the middle of the sprite, so the item sits under the pointer.
    static let cursorHotSpot = NSPoint(x: cursorSide / 2, y: cursorSide / 2)

    @MainActor
    private static var cursorCache: [ItemSprite: NSImage] = [:]
}

// MARK: - Ball

/// Tennis ball: yellow-green sphere with the two mirrored seams.
private struct BallSprite: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.90, green: 0.95, blue: 0.42),
                                Color(red: 0.51, green: 0.67, blue: 0.11),
                            ],
                            center: UnitPoint(x: 0.34, y: 0.28),
                            startRadius: 0,
                            endRadius: side * 0.78
                        )
                    )
                Circle()
                    .strokeBorder(Color.black.opacity(0.18), lineWidth: max(0.5, side * 0.03))
                TennisSeam()
                    .stroke(Color.white.opacity(0.92), style: StrokeStyle(lineWidth: side * 0.075, lineCap: .round))
                TennisSeam()
                    .rotation(.degrees(180))
                    .stroke(Color.white.opacity(0.92), style: StrokeStyle(lineWidth: side * 0.075, lineCap: .round))
            }
            .frame(width: side, height: side)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// One seam: a bow from the upper edge to the lower edge, bulging toward the centre.
private struct TennisSeam: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.17))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.maxY - rect.height * 0.17),
            control: CGPoint(x: rect.midX + rect.width * 0.26, y: rect.midY)
        )
        return path
    }
}

// MARK: - Bowls

/// Food and water bowl: tapered ceramic body, rim ellipse, contents surface inside the rim.
private struct BowlSprite: View {
    let contents: Color
    let rim: Color


    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let rimCenterY = height * 0.34
            ZStack {
                BowlBody()
                    .fill(
                        LinearGradient(
                            colors: [rim.opacity(0.95), rim.opacity(0.62)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                BowlBody()
                    .stroke(Color.black.opacity(0.22), lineWidth: max(0.5, width * 0.022))
                Ellipse()
                    .fill(contents)
                    .frame(width: width * 0.60, height: height * 0.155)
                    .position(x: width / 2, y: rimCenterY)
                Ellipse()
                    .stroke(rim.opacity(0.95), lineWidth: max(0.8, width * 0.05))
                    .frame(width: width * 0.76, height: height * 0.20)
                    .position(x: width / 2, y: rimCenterY)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Bowl silhouette: straight top between the rim ends, sides curving to a narrow base.
private struct BowlBody: Shape {
    func path(in rect: CGRect) -> Path {
        let top = rect.minY + rect.height * 0.34
        let bottom = rect.maxY - rect.height * 0.10
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: top))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: top))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: bottom),
            control: CGPoint(x: rect.maxX - rect.width * 0.16, y: bottom)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.12, y: top),
            control: CGPoint(x: rect.minX + rect.width * 0.16, y: bottom)
        )
        path.closeSubpath()
        return path
    }
}
