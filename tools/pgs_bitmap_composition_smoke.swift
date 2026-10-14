import Foundation

@main
struct PGSBitmapCompositionSmoke {
    static func main() {
        let object = PGSBitmapObject(x: -1, y: 2, width: 2, height: 1,
                                     indices: [0, 1], paletteARGB: [0x00000000, 0x804080FF])
        let frame = PGSBitmapFrame(videoWidth: 100, videoHeight: 50, objects: [object])
        let layers = PGSBitmapComposition.layers(for: frame)
        precondition(layers.count == 1)
        precondition(layers[0].x == 0 && layers[0].y == 2)
        precondition(layers[0].rgba == [64, 128, 255, 128])
        var timeline = PGSBitmapTimeline()
        timeline.replace(with: [PGSBitmapEvent(time: 2, frame: frame),
                                PGSBitmapEvent(time: 3, frame: nil)])
        precondition(timeline.frame(at: 2.5) != nil)
        precondition(timeline.frame(at: 3) == nil)
        precondition(timeline.frame(at: 2.5) != nil)
        print("PGS bitmap compositor smoke passed")
    }
}
