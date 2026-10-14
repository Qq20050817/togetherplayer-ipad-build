import Foundation

/// Experimental, playback-only bitmap compositor. The decoder must supply original
/// PGS palette indices and palette colors; OCR text must never be rendered here.
/// Colors use 0xAARRGGBB, output pixels use straight-alpha RGBA8.
struct PGSBitmapObject {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let indices: [UInt8]
    let paletteARGB: [UInt32]
}

struct PGSBitmapFrame {
    let videoWidth: Int
    let videoHeight: Int
    let objects: [PGSBitmapObject]
}

struct PGSBitmapLayer {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let rgba: [UInt8]

    func normalizedRect(videoWidth: Int, videoHeight: Int) -> (x: Double, y: Double, width: Double, height: Double)? {
        guard videoWidth > 0, videoHeight > 0 else { return nil }
        return (Double(x) / Double(videoWidth), Double(y) / Double(videoHeight),
                Double(width) / Double(videoWidth), Double(height) / Double(videoHeight))
    }
}

enum PGSBitmapComposition {
    // Limit work on malformed or adversarial subtitle packets.
    static let maxPixelsPerObject = 4_194_304
    static let maxObjects = 32

    static func layers(for frame: PGSBitmapFrame) -> [PGSBitmapLayer] {
        guard frame.videoWidth > 0, frame.videoHeight > 0,
              frame.videoWidth <= 16384, frame.videoHeight <= 16384,
              frame.objects.count <= maxObjects else { return [] }
        return frame.objects.compactMap { object in
            guard object.width > 0, object.height > 0,
                  object.width <= maxPixelsPerObject / object.height,
                  object.indices.count == object.width * object.height,
                  !object.paletteARGB.isEmpty,
                  object.x < frame.videoWidth, object.y < frame.videoHeight else { return nil }
            let left = max(0, object.x)
            let top = max(0, object.y)
            let right = min(frame.videoWidth, object.x + object.width)
            let bottom = min(frame.videoHeight, object.y + object.height)
            guard right > left, bottom > top else { return nil }
            let width = right - left, height = bottom - top
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            for row in 0..<height {
                let sourceRow = (top - object.y + row) * object.width
                let destinationRow = row * width * 4
                for column in 0..<width {
                    let index = Int(object.indices[sourceRow + left - object.x + column])
                    guard index < object.paletteARGB.count else { continue }
                    let argb = object.paletteARGB[index]
                    let offset = destinationRow + column * 4
                    bytes[offset] = UInt8(truncatingIfNeeded: argb >> 16)
                    bytes[offset + 1] = UInt8(truncatingIfNeeded: argb >> 8)
                    bytes[offset + 2] = UInt8(truncatingIfNeeded: argb)
                    bytes[offset + 3] = UInt8(truncatingIfNeeded: argb >> 24)
                }
            }
            return PGSBitmapLayer(x: left, y: top, width: width, height: height, rgba: bytes)
        }
    }
}

/// Show/clear events are keyed to the movie's own clock, not wall-clock time.
/// Recomputing from events on seek prevents stale PGS from surviving a jump.
struct PGSBitmapEvent {
    let time: Double
    let frame: PGSBitmapFrame?  // nil means clear
}

struct PGSBitmapTimeline {
    private(set) var events: [PGSBitmapEvent] = []

    mutating func replace(with values: [PGSBitmapEvent]) {
        events = values.filter { $0.time.isFinite && $0.time >= 0 }
            .enumerated().sorted { a, b in
                a.element.time == b.element.time ? a.offset < b.offset : a.element.time < b.element.time
            }.map(\.element)
    }

    mutating func clear() { events.removeAll(keepingCapacity: false) }

    func frame(at seconds: Double) -> PGSBitmapFrame? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        var low = 0, high = events.count
        while low < high {
            let middle = low + (high - low) / 2
            if events[middle].time <= seconds { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? events[low - 1].frame : nil
    }
}
