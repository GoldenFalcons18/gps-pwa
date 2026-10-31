#if os(iOS) || os(watchOS)
import SwiftUI

struct SignalClassLogoMark: View {
    let name: String
    var color: Color = .black

    private var mark: String {
        let value = name.replacingOccurrences(of: "class-", with: "")
        let marks = [
            "A-Cat":"A", "Optimist":"O", "Starling":"★", "ILCA":"ILCA",
            "49er FX":"49er FX", "49er":"49er", "29er":"29er", "420":"420", "470":"470",
            "Laser":"Laser", "Laser Pico":"Pico", "Laser 4.7":"4.7",
            "J/22":"J22", "J/24":"J24", "J/70":"J70", "J/80":"J80", "J/105":"J105",
            "Flying Fifteen":"15", "Flying 11":"11", "International 14":"14",
            "Formula 18":"F18", "Nacra 17":"N17", "Nacra 15":"N15",
            "Cyclone 13":"C13", "Melges 24":"M24", "WASZP":"WASZP", "Wing Foil":"Foil"
        ]
        if let mark = marks[value] { return mark }
        let pieces = value.split(separator: " ")
        if pieces.count > 1 {
            let initials = pieces.compactMap(\.first).map(String.init).joined()
            return initials.count >= 2 ? initials : String(value.prefix(8))
        }
        return value
    }

    @ViewBuilder
    private var fallbackMark: some View {
        ZStack {
            Text(mark)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .italic()
                .minimumScaleFactor(0.28)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .foregroundStyle(color)
                .padding(.horizontal, 3)
            if name == "A-Cat" {
                VStack(spacing: 3) {
                    Spacer()
                    Rectangle().fill(color).frame(width: 35, height: 3)
                    Rectangle().fill(color).frame(width: 28, height: 3)
                }.padding(.bottom, 5)
            } else if name == "Optimist" {
                Circle().stroke(color, lineWidth: 3).padding(9)
            }
        }
    }

    var body: some View {
        Group {
            #if os(iOS)
            if let image = SignalClassLogoAssets.image(for: name) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            } else {
                fallbackMark
            }
            #else
            fallbackMark
            #endif
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityLabel(name)
    }
}

struct SignalInternationalFlagArtwork: View {
    let name: String

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let white = Color.white, black = Color.black, red = Color(red: 0.86, green: 0.02, blue: 0.08)
            let blue = Color(red: 0.0, green: 0.12, blue: 0.91), yellow = Color.yellow
            let colors: [Color]
            let code = name.lowercased()
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
                context.fill(Path(CGRect(x: x * size.width, y: y * size.height, width: w * size.width, height: h * size.height)), with: .color(color))
            }
            func polygon(_ points: [CGPoint], _ color: Color) {
                var path = Path()
                guard let first = points.first else { return }
                path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height)) }
                path.closeSubpath()
                context.fill(path, with: .color(color))
            }
            func stripes(_ list: [Color], vertical: Bool) {
                for (index, color) in list.enumerated() {
                    let n = CGFloat(list.count), pos = CGFloat(index) / n, extent = 1 / n
                    if vertical { rect(pos, 0, extent, 1, color) } else { rect(0, pos, 1, extent, color) }
                }
            }
            func cross(_ color: Color, width: CGFloat = 0.22) {
                rect(0.5 - width / 2, 0, width, 1, color)
                rect(0, 0.5 - width / 2, 1, width, color)
            }
            func diagonalBand(_ low: CGFloat, _ high: CGFloat, _ color: Color) {
                func clip(_ points: [CGPoint], boundary: CGFloat, keepBelow: Bool) -> [CGPoint] {
                    guard !points.isEmpty else { return [] }
                    var output: [CGPoint] = []
                    for index in points.indices {
                        let a = points[index], b = points[(index + 1) % points.count]
                        let fa = a.x + a.y - boundary, fb = b.x + b.y - boundary
                        let insideA = keepBelow ? fa <= 0 : fa >= 0
                        let insideB = keepBelow ? fb <= 0 : fb >= 0
                        if insideA { output.append(a) }
                        if insideA != insideB {
                            let t = fa / (fa - fb)
                            output.append(CGPoint(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y)))
                        }
                    }
                    return output
                }
                var points = [CGPoint(x:0,y:0),CGPoint(x:1,y:0),CGPoint(x:1,y:1),CGPoint(x:0,y:1)]
                points = clip(points, boundary: high, keepBelow: true)
                points = clip(points, boundary: low, keepBelow: false)
                polygon(points, color)
            }
            func pennant(_ palette: [Color], stripesVertical: Bool = true, mark: String = "") {
                var pennantPath = Path()
                pennantPath.move(to: .zero)
                pennantPath.addLine(to: CGPoint(x: size.width, y: size.height * 0.5))
                pennantPath.addLine(to: CGPoint(x: 0, y: size.height))
                pennantPath.closeSubpath()
                var clipped = context
                clipped.clip(to: pennantPath)
                for (index, color) in palette.enumerated() {
                    let n = CGFloat(palette.count), pos = CGFloat(index) / n, extent = 1 / n
                    let frame = stripesVertical
                        ? CGRect(x: pos * size.width, y: 0, width: extent * size.width, height: size.height)
                        : CGRect(x: 0, y: pos * size.height, width: size.width, height: extent * size.height)
                    clipped.fill(Path(frame), with: .color(color))
                }
                switch mark {
                case "redCircle": clipped.fill(Path(ellipseIn:CGRect(x:size.width*0.27,y:size.height*0.32,width:size.width*0.23,height:size.height*0.36)),with:.color(red))
                case "whiteCircle": clipped.fill(Path(ellipseIn:CGRect(x:size.width*0.27,y:size.height*0.32,width:size.width*0.23,height:size.height*0.36)),with:.color(white))
                case "whiteCross", "redCross":
                    let color = mark == "whiteCross" ? white : red
                    clipped.fill(Path(CGRect(x:size.width*0.42,y:0,width:size.width*0.16,height:size.height)),with:.color(color))
                    clipped.fill(Path(CGRect(x:0,y:size.height*0.40,width:size.width,height:size.height*0.20)),with:.color(color))
                case "yellowTriangle", "whiteTriangle":
                    let color = mark == "yellowTriangle" ? yellow : white
                    var triangle = Path()
                    triangle.move(to:CGPoint(x:size.width*0.12,y:size.height*0.20))
                    triangle.addLine(to:CGPoint(x:size.width*0.67,y:size.height*0.50))
                    triangle.addLine(to:CGPoint(x:size.width*0.12,y:size.height*0.80))
                    triangle.closeSubpath()
                    clipped.fill(triangle,with:.color(color))
                case "blackBand": clipped.fill(Path(CGRect(x:0,y:size.height*0.35,width:size.width*0.70,height:size.height*0.30)),with:.color(black))
                default: break
                }
            }

            switch code {
            case "alpha":
                colors=[white,blue]; rect(0,0,1,1,white); rect(0.5,0,0.5,1,blue)
                polygon([CGPoint(x:0.72,y:0.34),CGPoint(x:1,y:0.5),CGPoint(x:0.72,y:0.66)],white)
            case "bravo":
                colors=[red]; rect(0,0,1,1,red)
                polygon([CGPoint(x:0.68,y:0.34),CGPoint(x:1,y:0.5),CGPoint(x:0.68,y:0.66)],white)
            case "charlie": colors=[blue,white,red,white,blue]; stripes(colors,vertical:false)
            case "delta": colors=[yellow,blue,yellow]; stripes(colors,vertical:false)
            case "echo": colors=[blue,red]; stripes(colors,vertical:false)
            case "foxtrot": colors=[white]; rect(0,0,1,1,white); polygon([CGPoint(x:0.5,y:0.12),CGPoint(x:0.88,y:0.5),CGPoint(x:0.5,y:0.88),CGPoint(x:0.12,y:0.5)],red)
            case "golf": colors=[yellow,blue,yellow,blue,yellow]; stripes(colors,vertical:true)
            case "hotel": colors=[white,red]; stripes(colors,vertical:true)
            case "india": colors=[yellow]; rect(0,0,1,1,yellow); context.fill(Path(ellipseIn:CGRect(x:size.width*0.27,y:size.height*0.2,width:size.width*0.46,height:size.height*0.6)),with:.color(black))
            case "juliett": colors=[blue,white,blue]; stripes(colors,vertical:false)
            case "kilo": colors=[yellow,blue]; stripes(colors,vertical:true)
            case "lima": colors=[yellow,black,yellow,black]; rect(0,0,0.5,0.5,yellow); rect(0.5,0,0.5,0.5,black); rect(0,0.5,0.5,0.5,black); rect(0.5,0.5,0.5,0.5,yellow)
            case "mike": colors=[blue]; rect(0,0,1,1,blue); cross(white,width:0.18)
            case "november": colors=[white,blue]; rect(0,0,1,1,white); for x in 0..<4 { for y in 0..<4 where (x+y)%2==0 { rect(CGFloat(x)/4,CGFloat(y)/4,0.25,0.25,blue) } }
            case "oscar": colors=[yellow,red]; rect(0,0,1,1,yellow); polygon([CGPoint(x:0,y:0),CGPoint(x:1,y:0),CGPoint(x:0,y:1)],red)
            case "papa": colors=[blue]; rect(0,0,1,1,blue); rect(0.34,0.30,0.32,0.40,white)
            case "quebec": colors=[yellow]; rect(0,0,1,1,yellow)
            case "romeo":
                colors=[red,yellow]; rect(0,0,1,1,red); cross(yellow,width:0.16)
            case "sierra": colors=[white,blue]; rect(0,0,1,1,white); rect(0.36,0.34,0.28,0.32,blue)
            case "tango": colors=[red,white,blue]; stripes(colors,vertical:true)
            case "uniform": colors=[red,white]; rect(0,0,1,1,white); rect(0,0,0.5,0.5,red); rect(0.5,0.5,0.5,0.5,red)
            case "victor":
                colors=[white,red]; rect(0,0,1,1,white)
                polygon([CGPoint(x:0,y:0),CGPoint(x:0.22,y:0),CGPoint(x:1,y:0.78),CGPoint(x:1,y:1),CGPoint(x:0.78,y:1),CGPoint(x:0,y:0.22)],red)
                polygon([CGPoint(x:1,y:0),CGPoint(x:1,y:0.22),CGPoint(x:0.22,y:1),CGPoint(x:0,y:1),CGPoint(x:0,y:0.78),CGPoint(x:0.78,y:0)],red)
            case "whiskey": colors=[blue]; rect(0,0,1,1,blue); rect(0.18,0.12,0.64,0.76,white); rect(0.34,0.30,0.32,0.40,red)
            case "x-ray": colors=[white]; rect(0,0,1,1,white); cross(blue,width:0.18)
            case "yankee":
                colors=[red,yellow]
                for index in 0..<8 {
                    let low=CGFloat(index)*0.25, high=low+0.25
                    diagonalBand(low, high, index % 2 == 0 ? red : yellow)
                }
            case "zulu":
                colors=[black,yellow,blue,red]
                polygon([CGPoint(x:0,y:0),CGPoint(x:1,y:0),CGPoint(x:0.5,y:0.5)],black)
                polygon([CGPoint(x:1,y:0),CGPoint(x:1,y:1),CGPoint(x:0.5,y:0.5)],yellow)
                polygon([CGPoint(x:1,y:1),CGPoint(x:0,y:1),CGPoint(x:0.5,y:0.5)],red)
                polygon([CGPoint(x:0,y:1),CGPoint(x:0,y:0),CGPoint(x:0.5,y:0.5)],blue)
            case "answering pennant": colors=[red,white]; pennant([red,white,red,white,red],stripesVertical:true)
            case "first substitute": colors=[blue,yellow]; pennant([blue],mark:"yellowTriangle")
            case "second substitute": colors=[blue,white]; pennant([blue],mark:"whiteTriangle")
            case "third substitute": colors=[white,black]; pennant([white],mark:"blackBand")
            case "fourth substitute": colors=[red,yellow]; pennant([red,yellow,red],stripesVertical:false)
            default:
                let n = Int(code.filter(\.isNumber)) ?? 0
                if code.contains("nato") {
                    colors = [white, blue, red, yellow]
                    switch n {
                    case 0:
                        rect(0,0,1,1,white); cross(blue,width:0.10)
                        for x in [CGFloat(0.12),CGFloat(0.88)] { for y in [CGFloat(0.12),CGFloat(0.88)] {
                            rect(x-0.035,y-0.035,0.07,0.07,blue)
                        } }
                    case 1: stripes([red,yellow],vertical:false)
                    case 2: stripes([yellow,red],vertical:false)
                    case 3: stripes([blue,red],vertical:false)
                    case 4: rect(0,0,1,1,red); cross(white,width:0.17)
                    case 5: rect(0,0,1,1,yellow); cross(blue,width:0.17)
                    case 6:
                        rect(0,0,1,1,white)
                        for offset in stride(from: -1.0, through: 1.0, by: 0.25) {
                            var path = Path()
                            path.move(to: CGPoint(x: max(0, offset) * size.width, y: max(0, -offset) * size.height))
                            path.addLine(to: CGPoint(x: min(1, offset + 1) * size.width, y: min(1, 1 - offset) * size.height))
                            context.stroke(path, with: .color(blue), lineWidth: max(2, size.height * 0.09))
                        }
                    case 7: stripes([red,white,red],vertical:true)
                    case 8: rect(0,0,1,1,yellow); rect(0.4,0,0.2,1,blue)
                    default: rect(0,0,1,1,blue)
                    }
                } else {
                    switch n {
                    case 0: colors=[yellow,red]; pennant([yellow,red,yellow])
                    case 1: colors=[white,red]; pennant([white],mark:"redCircle")
                    case 2: colors=[blue,white]; pennant([blue],mark:"whiteCircle")
                    case 3: colors=[red,white,blue]; pennant([red,white,blue],stripesVertical:false)
                    case 4: colors=[red,white]; pennant([red],mark:"whiteCross")
                    case 5: colors=[yellow,blue]; pennant([yellow,blue],stripesVertical:false)
                    case 6: colors=[black,white]; pennant([black,white],stripesVertical:false)
                    case 7: colors=[yellow,red]; pennant([yellow,red],stripesVertical:false)
                    case 8: colors=[white,red]; pennant([white],mark:"redCross")
                    default: colors=[white,red,black,yellow]; pennant([white,red,black,yellow])
                    }
                }
            }
            context.stroke(Path(bounds), with: .color(.black.opacity(0.75)), lineWidth: max(1, size.width * 0.012))
        }.aspectRatio(1.5, contentMode: .fit)
    }
}
#endif
