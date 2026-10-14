import XCTest
@testable import TogetherPoC

final class PGSBitmapCompositionTests: XCTestCase {
    private func sample(x: Int = 10, y: Int = 20, indices: [UInt8] = [0, 1]) -> PGSBitmapFrame {
        PGSBitmapFrame(videoWidth: 100, videoHeight: 50, objects: [
            PGSBitmapObject(x: x, y: y, width: 2, height: 1, indices: indices,
                            paletteARGB: [0x00000000, 0x804080FF])
        ])
    }

    func testOriginalPaletteAlphaAndRGBAChannels() {
        let layers = PGSBitmapComposition.layers(for: sample())
        XCTAssertEqual(layers.count, 1)
        XCTAssertEqual(layers[0].rgba, [0, 0, 0, 0, 64, 128, 255, 128])
        XCTAssertEqual(layers[0].normalizedRect(videoWidth: 100, videoHeight: 50)?.x, 0.1)
        XCTAssertEqual(layers[0].normalizedRect(videoWidth: 100, videoHeight: 50)?.y, 0.4)
    }

    func testClippingUsesCorrectSourcePixel() {
        let layers = PGSBitmapComposition.layers(for: sample(x: -1, y: 49))
        XCTAssertEqual(layers.count, 1)
        XCTAssertEqual(layers[0].x, 0)
        XCTAssertEqual(layers[0].width, 1)
        XCTAssertEqual(layers[0].rgba, [64, 128, 255, 128])
    }

    func testRejectsMalformedSizesAndOutOfRangePaletteSafely() {
        let oversized = PGSBitmapObject(x: 0, y: 0, width: Int.max, height: Int.max,
                                         indices: [], paletteARGB: [0])
        XCTAssertTrue(PGSBitmapComposition.layers(for: PGSBitmapFrame(
            videoWidth: 100, videoHeight: 50, objects: [oversized])).isEmpty)
        let missing = PGSBitmapComposition.layers(for: sample(indices: [0, 255]))
        XCTAssertEqual(missing.first?.rgba, [0, 0, 0, 0, 0, 0, 0, 0])
    }

    func testTimelineShowClearSeekAndReset() {
        var timeline = PGSBitmapTimeline()
        let frame = sample()
        timeline.replace(with: [PGSBitmapEvent(time: 7, frame: nil),
                                PGSBitmapEvent(time: 2, frame: frame)])
        XCTAssertNil(timeline.frame(at: 1.99))
        XCTAssertNotNil(timeline.frame(at: 2))
        XCTAssertNotNil(timeline.frame(at: 6.99))
        XCTAssertNil(timeline.frame(at: 7))
        XCTAssertNotNil(timeline.frame(at: 3)) // backward seek recomputes
        timeline.clear()
        XCTAssertNil(timeline.frame(at: 3))
    }

    func testSeparateBitmapObjectsKeepIndependentCoordinates() {
        let first = sample().objects[0]
        let second = PGSBitmapObject(x: 80, y: 30, width: 1, height: 1,
                                     indices: [0], paletteARGB: [0xFFFFFFFF])
        let layers = PGSBitmapComposition.layers(for: PGSBitmapFrame(
            videoWidth: 100, videoHeight: 50, objects: [first, second]))
        XCTAssertEqual(layers.count, 2)
        XCTAssertEqual(layers[1].x, 80)
        XCTAssertEqual(layers[1].rgba, [255, 255, 255, 255])
    }
}
