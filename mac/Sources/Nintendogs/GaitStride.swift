import Foundation

/// Fixed-root clips need root travel opposite the planted paw's backward motion.
/// Measure contact-phase velocity, not full-cycle excursion (which includes swing).
enum GaitStride {
    enum MeasurementError: LocalizedError {
        case invalidClip(String)
        var errorDescription: String? {
            switch self {
            case .invalidClip(let name): "Cannot measure the planted-paw motion in \(name)."
            }
        }
    }

    static func speed(clip: URL, scale: CGFloat) throws -> CGFloat {
        let name = clip.deletingPathExtension().lastPathComponent
        let document = try XMLDocument(contentsOf: clip)
        let chain = ["skl_root", "waist", "Lleg1", "Lleg2", "Lfoot1", "Lfoot2"]
        func values(_ id: String) throws -> [Double] {
            let path = "//*[local-name()='source'][@id='\(id)']/*[local-name()='float_array']"
            guard let text = try document.nodes(forXPath: path).first?.stringValue else {
                throw MeasurementError.invalidClip(name)
            }
            return try text.split(whereSeparator: \.isWhitespace).map {
                guard let number = Double($0), number.isFinite else { throw MeasurementError.invalidClip(name) }
                return number
            }
        }
        let times = try values("\(name)_skl_root_input")
        let channels = try chain.map { try values("\(name)_\($0)_output") }
        guard times.count > 2, channels.allSatisfy({ $0.count == times.count * 16 }) else {
            throw MeasurementError.invalidClip(name)
        }
        var heights: [Double] = []
        var forward: [Double] = []
        for frame in times.indices {
            let start = frame * 16
            var world = Array(channels[0][start..<start + 16])
            for channel in channels.dropFirst() {
                world = multiply(world, Array(channel[start..<start + 16]))
            }
            heights.append(world[7])
            forward.append(world[11])
        }
        let low = heights.min()!
        let contactHeight = low + (heights.max()! - low) * 0.25
        var distance = 0.0
        var contactTime = 0.0
        for index in 1..<times.count {
            let dt = times[index] - times[index - 1]
            guard dt > 0 else { throw MeasurementError.invalidClip(name) }
            let backward = forward[index - 1] - forward[index]
            if heights[index] <= contactHeight, heights[index - 1] <= contactHeight, backward > 0 {
                distance += backward
                contactTime += dt
            }
        }
        guard contactTime > 0, distance > 0, scale.isFinite, scale > 0 else {
            throw MeasurementError.invalidClip(name)
        }
        return CGFloat(distance / contactTime) * scale
    }

    private static func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
        var result = [Double](repeating: 0, count: 16)
        for row in 0..<4 {
            for column in 0..<4 {
                for inner in 0..<4 {
                    result[row * 4 + column] += a[row * 4 + inner] * b[inner * 4 + column]
                }
            }
        }
        return result
    }
}
