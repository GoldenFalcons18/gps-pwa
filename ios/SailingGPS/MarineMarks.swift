import SwiftUI
import UIKit

enum MarineMarks {
    static let choices: [(String, String)] = [
        ("marine.lighthouse", "灯台"), ("marine.net", "網"), ("exclamationmark.triangle.fill", "危険"),
        ("marine.buoy", "ブイ"), ("mountain.2.fill", "岩礁"), ("marine.anchor", "錨"), ("sailboat.fill", "帆船"), ("ferry.fill", "船"),
        ("flag.fill", "旗"), ("star.fill", "星"), ("circle.fill", "丸"), ("mappin", "ピン"),
        ("triangle.fill", "三角"), ("square.fill", "四角"), ("diamond.fill", "ひし形"), ("house.fill", "家"),
        ("sun.max.fill", "太陽"), ("moon.fill", "月"), ("fish.fill", "魚"), ("binoculars.fill", "双眼鏡"), ("light.beacon.max.fill", "灯火")
    ]
    static func image(_ symbol: String) -> UIImage {
        guard symbol.hasPrefix("marine.") else { return UIImage(systemName: symbol) ?? UIImage(systemName: "flag.fill")! }
        return UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.black.setFill(); UIColor.black.setStroke()
            let path = UIBezierPath(); path.lineWidth = 2.2; path.lineCapStyle = .round; path.lineJoinStyle = .round
            func line(_ x: CGFloat, _ y: CGFloat, _ a: CGFloat, _ b: CGFloat) { path.move(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: a, y: b)) }
            switch symbol {
            case "marine.lighthouse":
                path.move(to: CGPoint(x: 9, y: 29)); path.addLine(to: CGPoint(x: 12, y: 12)); path.addLine(to: CGPoint(x: 20, y: 12)); path.addLine(to: CGPoint(x: 23, y: 29)); path.close(); path.stroke()
                UIBezierPath(rect: CGRect(x: 11, y: 7, width: 10, height: 6)).fill()
                let roof = UIBezierPath(); roof.move(to: CGPoint(x: 9, y: 7)); roof.addLine(to: CGPoint(x: 16, y: 2)); roof.addLine(to: CGPoint(x: 23, y: 7)); roof.close(); roof.fill()
                line(4, 29, 28, 29); line(11, 19, 21, 19); line(2, 6, 7, 9); line(2, 13, 7, 10); line(25, 9, 30, 6); line(25, 10, 30, 13)
            case "marine.net":
                path.append(UIBezierPath(roundedRect: CGRect(x: 3, y: 3, width: 26, height: 26), cornerRadius: 2))
                for value in stride(from: 4, through: 28, by: 6) {
                    let v = CGFloat(value)
                    line(3, v, v, 3); line(v, 29, 29, v); line(3, 32-v, v, 29); line(v, 3, 29, 32-v)
                }
            case "marine.buoy":
                line(16, 3, 16, 24); line(8, 24, 24, 24); line(8, 24, 12, 18); line(12, 18, 20, 18); line(20, 18, 24, 24)
                UIBezierPath(ovalIn: CGRect(x: 12, y: 5, width: 8, height: 8)).fill()
                line(2, 28, 8, 30); line(8, 30, 16, 27); line(16, 27, 24, 30); line(24, 30, 30, 28)
            case "marine.anchor":
                path.append(UIBezierPath(ovalIn: CGRect(x: 12, y: 2, width: 8, height: 8)))
                line(16, 10, 16, 28); line(8, 13, 24, 13)
                path.move(to: CGPoint(x: 4, y: 19)); path.addCurve(to: CGPoint(x: 28, y: 19), controlPoint1: CGPoint(x: 5, y: 33), controlPoint2: CGPoint(x: 27, y: 33))
                line(4, 19, 3, 24); line(4, 19, 9, 20); line(28, 19, 29, 24); line(28, 19, 23, 20)
            default: break
            }
            path.stroke()
        }.withRenderingMode(.alwaysTemplate)
    }
}
struct WaypointMarkIcon: View {
    let symbol: String
    var body: some View { Image(uiImage: MarineMarks.image(symbol)).renderingMode(.template).resizable().scaledToFit().frame(width: 25, height: 25) }
}
