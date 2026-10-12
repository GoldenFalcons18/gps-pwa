import SwiftUI

/// Seven-segment speed display, matching the large green instrument in the reference.
struct SevenSegmentSpeed: View {
    let text: String
    private let masks = [0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d, 0x07, 0x7f, 0x6f]
    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                if character == "." {
                    Circle().fill(.green).frame(width: 10, height: 10).padding(.bottom, 2)
                } else {
                    let mask = character.wholeNumberValue.map { masks[$0] } ?? 0x40
                    GeometryReader { proxy in
                        let w = proxy.size.width
                        let h = proxy.size.height
                        let t = min(w * 0.16, h * 0.08)
                        let shapes: [[CGPoint]] = [
                            [CGPoint(x:t,y:0),CGPoint(x:w-t,y:0),CGPoint(x:w-2*t,y:t),CGPoint(x:2*t,y:t)],
                            [CGPoint(x:w,y:t),CGPoint(x:w,y:h/2-t/2),CGPoint(x:w-t,y:h/2-t),CGPoint(x:w-t,y:2*t)],
                            [CGPoint(x:w,y:h/2+t/2),CGPoint(x:w,y:h-t),CGPoint(x:w-t,y:h-2*t),CGPoint(x:w-t,y:h/2+t)],
                            [CGPoint(x:t,y:h),CGPoint(x:w-t,y:h),CGPoint(x:w-2*t,y:h-t),CGPoint(x:2*t,y:h-t)],
                            [CGPoint(x:0,y:h/2+t/2),CGPoint(x:t,y:h/2+t),CGPoint(x:t,y:h-2*t),CGPoint(x:0,y:h-t)],
                            [CGPoint(x:0,y:t),CGPoint(x:t,y:2*t),CGPoint(x:t,y:h/2-t),CGPoint(x:0,y:h/2-t/2)],
                            [CGPoint(x:t,y:h/2),CGPoint(x:2*t,y:h/2-t/2),CGPoint(x:w-2*t,y:h/2-t/2),CGPoint(x:w-t,y:h/2),CGPoint(x:w-2*t,y:h/2+t/2),CGPoint(x:2*t,y:h/2+t/2)]
                        ]
                        ForEach(0..<7) { index in
                            Path { path in path.addLines(shapes[index]); path.closeSubpath() }
                                .fill(mask & (1 << index) != 0 ? Color.green : Color(white: 0.055))
                        }
                    }
                }
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("速度 " + text)
    }
}
