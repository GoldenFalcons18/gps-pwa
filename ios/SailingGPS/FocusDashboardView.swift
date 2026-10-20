import SwiftUI

/// Three large readings; Both headings share the selected north reference.
struct FocusDashboardView:View {
    let speed:String
    let course:Double?
    let isCompass:Bool
    let targetBearing:Double?
    let unit:String
    @Binding var mode:Int
    @Binding var magnetic:Bool
    let chooseTarget:()->Void
    let openMenu:()->Void
    private func card(_ label:String,_ value:String,_ color:Color)->some View {
        GeometryReader { bounds in
            VStack(spacing:4) {
                Text(label).font(.title3).foregroundStyle(.gray)
                Text(value).font(.system(size:min(bounds.size.width*0.30,bounds.size.height*0.65),weight:.bold,design:.monospaced))
                    .minimumScaleFactor(0.3).lineLimit(1).foregroundStyle(color)
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
            }.padding(8).frame(maxWidth:.infinity,maxHeight:.infinity)
                .overlay(RoundedRectangle(cornerRadius:8).stroke(.gray))
        }
    }
    var body:some View {
        VStack(spacing:8) {
            HStack {
                ForEach(0..<3) { index in
                    Button(["速度","地図","3項目"][index]) { mode=index }
                        .frame(maxWidth:.infinity).buttonStyle(.bordered).tint(index==mode ? .green:.orange)
                }
                Button(magnetic ? "磁北":"真北") {magnetic.toggle()}.tint(.orange)
                Button(action:openMenu) { Image(systemName:"line.3.horizontal") }.accessibilityLabel("メニュー")
            }.font(.headline).padding(.bottom,4)
            card("SOG / "+unit,speed,.green)
            card((isCompass ? "コンパス方位":"COG") + (magnetic ? "（磁北）":"（真北）"),course.map{String(format:"%.0f°",$0.rounded().truncatingRemainder(dividingBy:360))} ?? "—",.white)
            Button(action:chooseTarget) {
                card("目標方位" + (magnetic ? "（磁北）":"（真北）"),targetBearing.map{String(format:"%.0f°",$0.rounded().truncatingRemainder(dividingBy:360))} ?? "—",.orange)
            }.buttonStyle(.plain).frame(maxWidth:.infinity,maxHeight:.infinity).accessibilityHint("タップして目標地点を変更")
        }.padding(8).background(.black).preferredColorScheme(.dark)
    }
}
