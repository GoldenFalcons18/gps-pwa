import SwiftUI
import MapKit

struct MapLibraryView: View {
    @ObservedObject var gps: GPSRecorder
    let export: ([Waypoint],[MapFeature],String)->Void
    let importFile: ()->Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [UUID] = []
    @State private var groupName = ""
    @State private var destinationGroup = ""
    @State private var scope = "all"
    @State private var exportGroup = ""
    @State private var featureDraft: MapFeature?
    @State private var error = ""
    @State private var showingError = false
    @State private var renameGroup: String?
    @State private var renamedGroup = ""
    @State private var confirmGroup: String?
    @State private var confirmFeature: MapFeature?
    @State private var rgbGroup: String?
    private var groups: [String] { Array(Set(["メインフォルダ"] + gps.library.groups + gps.waypoints.compactMap(\.group) + gps.library.features.map(\.group))).filter{!$0.isEmpty}.sorted() }
    private func commit(_ items:[Waypoint],_ library:MapLibrary) {
        do { try gps.saveLibrary(items,library) } catch { self.error=error.localizedDescription;showingError=true }
    }
    var body: some View {
        NavigationStack {
            List {
                importSection
                exportSection
                groupsSection
                featuresSection
                waypointSelectionSection
            }.buttonStyle(.borderless)
                .onAppear {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--preview-circle-editor") { featureDraft=MapFeature(name:gps.waypoints.first?.name ?? "円エリア",kind:"circle",waypointIDs:gps.waypoints.first.map{[$0.id]} ?? []) }
                    #endif
                }
                .navigationTitle("地点・グループ・エリア")
                .toolbar { ToolbarItem(placement:.confirmationAction){Button("閉じる"){dismiss()}} }
                .sheet(item:$featureDraft){f in MapFeatureEditor(feature:f,waypoints:gps.waypoints,groups:groups){updated in var l=gps.library;l.features.removeAll{$0.id==updated.id};l.features.append(updated);commit(gps.waypoints,l)} }
                .sheet(isPresented:Binding(get:{rgbGroup != nil},set:{if !$0{rgbGroup=nil}})) { if let group=rgbGroup { FolderRGBColorEditor(group:group,initial:gps.library.groupColors[group] ?? WaypointFolderColors.fallback){hex in var l=gps.library;l.groupColors[group]=hex;commit(gps.waypoints,l);rgbGroup=nil} } }
                .alert("処理できませんでした",isPresented:$showingError){Button("OK",role:.cancel){}}message:{Text(error)}
                .alert("グループ名",isPresented:Binding(get:{renameGroup != nil},set:{if !$0{renameGroup=nil}})) {
                    TextField("名前",text:$renamedGroup)
                    Button("保存"){guard let old=renameGroup else{return};let n=renamedGroup.trimmingCharacters(in:.whitespacesAndNewlines);guard !n.isEmpty else{return};var l=gps.library;l.groups=Array(Set(groups.filter{$0 != old}+[n])).sorted();l.hiddenGroups=l.hiddenGroups.map{$0==old ? n : $0};if let color=l.groupColors.removeValue(forKey:old){l.groupColors[n]=color};l.features=l.features.map{f in var f=f;if f.group==old{f.group=n};return f};commit(gps.waypoints.map{w in var w=w;if w.group==old{w.group=n};return w},l);renameGroup=nil}
                    Button("キャンセル",role:.cancel){renameGroup=nil}
                }
                .confirmationDialog("グループを削除しますか？地点と図形はメインフォルダへ移します。",isPresented:Binding(get:{confirmGroup != nil},set:{if !$0{confirmGroup=nil}}),titleVisibility:.visible){Button("グループを削除",role:.destructive){guard let g=confirmGroup else{return};var l=gps.library;l.groups=groups.filter{$0 != g};l.hiddenGroups.removeAll{$0==g};l.groupColors.removeValue(forKey:g);l.features=l.features.map{f in var f=f;if f.group==g{f.group=""};return f};commit(gps.waypoints.map{w in var w=w;if w.group==g{w.group="メインフォルダ"};return w},l);confirmGroup=nil}}
                .confirmationDialog("図形を削除しますか？",isPresented:Binding(get:{confirmFeature != nil},set:{if !$0{confirmFeature=nil}}),titleVisibility:.visible){Button("削除",role:.destructive){var l=gps.library;l.features.removeAll{$0.id==confirmFeature?.id};commit(gps.waypoints,l);confirmFeature=nil}}
        }.preferredColorScheme(.dark).tint(.orange)
    }
    private var importSection: some View { Section("インポート") {
                    Button("KMZ / KML / JSONを取り込む",action:importFile)
                    Text("コンパス55のKMZを選べます。既存の地点は残して追加し、同じ内容の地点は重複を省きます。").font(.caption)
                } }
    private var exportSection: some View { Section("エクスポート") {
                    Picker("対象",selection:$scope) { Text("全件").tag("all");Text("グループ").tag("group");Text("選択した地点").tag("selected") }
                    if scope == "group" { Picker("グループ",selection:$exportGroup) { Text("メインフォルダ").tag("");ForEach(groups,id:\.self){Text($0).tag($0)} } }
                    HStack { Button("KMZ"){output("kmz")};Spacer();Button("KML"){output("kml")};Spacer();Button("JSON・地点のみ"){output("json")} }
                } }
    private var groupsSection: some View { Section("グループ") {
                    HStack { TextField("新しいグループ名",text:$groupName);Button("追加") { let g=groupName.trimmingCharacters(in:.whitespacesAndNewlines);guard !g.isEmpty else{return};var l=gps.library;l.groups=Array(Set(groups+[g])).sorted();if l.groupColors[g] == nil { l.groupColors[g]=WaypointFolderColors.fallback };commit(gps.waypoints,l);groupName="" } }
                    ForEach(groups,id:\.self){g in
                        HStack {
                            Toggle(isOn:Binding(get:{!gps.library.hiddenGroups.contains(g)},set:{shown in var l=gps.library;l.hiddenGroups.removeAll{$0==g};if !shown{l.hiddenGroups.append(g)};commit(gps.waypoints,l)})) { HStack { Circle().fill(waypointColor(gps.library.groupColors[g] ?? WaypointFolderColors.fallback)).frame(width:12,height:12);Text("\(g) (\(gps.waypoints.filter{($0.group ?? "")==g}.count))") } }
                            Menu {
                                Section("フォルダの既定色") { ForEach(WaypointFolderColors.palette){item in Button { var l=gps.library;l.groupColors[g]=item.hex;commit(gps.waypoints,l) } label:{Label(item.name,systemImage:(gps.library.groupColors[g] ?? WaypointFolderColors.fallback)==item.hex ? "checkmark.circle.fill" : "circle.fill").tint(waypointColor(item.hex)) } };Button("RGBを指定…"){rgbGroup=g} }
                                Button("名前を変更"){renameGroup=g;renamedGroup=g}
                                Button("削除・地点はメインフォルダへ",role:.destructive){confirmGroup=g}
                            } label:{Image(systemName:"ellipsis.circle")}
                        }
                    }
                    Picker("選択した地点の移動先",selection:$destinationGroup){Text("メインフォルダ").tag("");ForEach(groups,id:\.self){Text($0).tag($0)}}
                    Button("選択した\(selected.count)地点を移動") { commit(gps.waypoints.map{w in var w=w;if selected.contains(w.id){w.group=destinationGroup.isEmpty ? "メインフォルダ" : destinationGroup};return w},gps.library) }.disabled(selected.isEmpty)
                } }
    private var featuresSection: some View { Section("エリア・直線") {
                    HStack { Button("円"){featureDraft=MapFeature(name:"円エリア",kind:"circle")};Spacer();Button("囲み"){featureDraft=MapFeature(name:"囲みエリア",kind:"area")};Spacer();Button("直線"){featureDraft=MapFeature(name:"直線",kind:"line")} }
                    ForEach(gps.library.features){f in HStack {
                        Button(f.name){featureDraft=f};Spacer()
                        Toggle("表示",isOn:Binding(get:{f.visible},set:{value in var l=gps.library;if let i=l.features.firstIndex(where:{$0.id==f.id}){l.features[i].visible=value};commit(gps.waypoints,l)})).labelsHidden()
                        Button(role:.destructive){confirmFeature=f} label:{Image(systemName:"trash")}
                    } }
                } }
    private var waypointSelectionSection: some View { Section("地点を選択（出力・所属変更用）") {
                    ForEach(gps.waypoints){w in Button {
                        if selected.contains(w.id){selected.removeAll{$0==w.id}}else{selected.append(w.id)}
                    } label:{HStack{Image(systemName:selected.contains(w.id) ? "checkmark.circle.fill" : "circle");Text(w.name);Spacer();Text((w.group ?? "").isEmpty ? "メインフォルダ" : w.group!).font(.caption)}} }
                } }
    private func output(_ format:String) {
        var items = gps.waypoints.filter{scope=="all" || (scope=="group" ? ($0.group ?? "")==exportGroup : selected.contains($0.id))}
        let ids=Set(items.map(\.id))
        let features = format=="json" ? [] : gps.library.features.filter{f in scope=="all" || (scope=="group" ? f.group==exportGroup : !f.waypointIDs.isEmpty && Set(f.waypointIDs).isSubset(of:ids))}
        let needed=Set(features.flatMap(\.waypointIDs));items += gps.waypoints.filter{needed.contains($0.id) && !ids.contains($0.id)}
        guard !items.isEmpty || !features.isEmpty else { error="出力する地点・図形を選んでください";showingError=true;return }
        export(items,features,format)
    }
}

private struct FolderRGBColorEditor:View {
    let group:String
    let initial:String
    let onSave:(String)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var red=""
    @State private var green=""
    @State private var blue=""
    private func components(_ hex:String)->[String] {
        let value=hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard value.count==6,let number=UInt32(value,radix:16) else{return ["255","170","0"]}
        return [String((number>>16)&255),String((number>>8)&255),String(number&255)]
    }
    var body:some View {
        NavigationStack { Form {
            Section("\(group) のRGB色") {
                TextField("R（0〜255）",text:$red).keyboardType(.numberPad)
                TextField("G（0〜255）",text:$green).keyboardType(.numberPad)
                TextField("B（0〜255）",text:$blue).keyboardType(.numberPad)
                HStack { Text("プレビュー");Spacer();RoundedRectangle(cornerRadius:6).fill(Color(red:Double(min(max(Int(red) ?? 0,0),255))/255,green:Double(min(max(Int(green) ?? 0,0),255))/255,blue:Double(min(max(Int(blue) ?? 0,0),255))/255)).frame(width:48,height:28) }
            }
        }.navigationTitle("RGB色を指定").toolbar {
            ToolbarItem(placement:.cancellationAction){Button("キャンセル"){dismiss()}}
            ToolbarItem(placement:.confirmationAction){Button("保存"){let values=[red,green,blue].compactMap(Int.init);guard values.count==3,values.allSatisfy({(0...255).contains($0)}) else{return};onSave(String(format:"#%02X%02X%02X",values[0],values[1],values[2]));dismiss()}.disabled(![red,green,blue].allSatisfy{Int($0).map{(0...255).contains($0)} ?? false)} }
        }.onAppear{let c=components(initial);red=c[0];green=c[1];blue=c[2]} }
    }
}

struct MapFeatureEditor: View {
    @State var feature: MapFeature
    let waypoints: [Waypoint]
    let groups: [String]
    let save: (MapFeature)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var error = ""
    @State private var radiusUnit = "m"
    @State private var pointFolder = ""
    private var pointFolders:[String] { Array(Set(groups + waypoints.compactMap(\.group))).filter{!$0.isEmpty}.sorted() }
    private var radiusFactor: Double { radiusUnit == "km" ? 1000 : radiusUnit == "nm" ? 1852 : 1 }
    var body: some View {
        NavigationStack {
            Form {
                TextField("名前",text:$feature.name)
                if feature.kind=="circle" { HStack { Text("半径");TextField("200",value:Binding(get:{feature.radius/radiusFactor},set:{feature.radius=$0*radiusFactor}),format:.number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) };Picker("半径の単位",selection:$radiusUnit){Text("m").tag("m");Text("km").tag("km");Text("nm").tag("nm")}.pickerStyle(.segmented) }
                ColorPicker("色",selection:Binding(get:{waypointColor(feature.color)},set:{c in let ui=UIColor(c);var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0;ui.getRed(&r,green:&g,blue:&b,alpha:&a);feature.color=String(format:"#%02X%02X%02X",Int(r*255),Int(g*255),Int(b*255))}),supportsOpacity:false)
                Picker("グループ",selection:$feature.group){Text("メインフォルダ").tag("");ForEach(groups,id:\.self){Text($0).tag($0)}}
                Section("作成中の地図") { FeatureDraftMap(feature:feature,entries:waypoints.map(\.archiveEntry)).frame(height:240);Text("選択順に結びます。保存するまでは仮表示です。").font(.caption) }
                Section(feature.kind=="circle" ? "中心を1地点選択" : "結ぶ順に地点を選択") {
                    Picker("地点のフォルダ",selection:$pointFolder){ForEach(pointFolders,id:\.self){Text($0).tag($0)}}
                    Text("選択済み: \(feature.waypointIDs.count)地点。フォルダを切り替えても選択は残ります。").font(.caption)
                    if feature.waypointIDs.isEmpty && !feature.coordinates.isEmpty { Text("取り込み済みの座標を維持しています。地点を選ぶと結び直します。").font(.caption) }
                    ForEach(waypoints.filter{($0.group ?? "")==pointFolder}){w in Button {
                        if feature.waypointIDs.contains(w.id){feature.waypointIDs.removeAll{$0==w.id}}
                        else if feature.kind=="circle"{feature.waypointIDs=[w.id];feature.name=w.name}
                        else{feature.waypointIDs.append(w.id)}
                    }label:{HStack{Text(feature.waypointIDs.firstIndex(of:w.id).map{"\($0+1)."} ?? "○");Text(w.name)}} }
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }.onAppear { let saved=UserDefaults.standard.string(forKey:"mainWaypointFolder") ?? "";pointFolder=pointFolders.contains(saved) ? saved : (waypoints.first(where:{feature.waypointIDs.contains($0.id)})?.group ?? pointFolders.first ?? "") }.navigationTitle(feature.kind=="circle" ? "円エリア" : feature.kind=="area" ? "囲みエリア" : "地点間の直線")
                .toolbar {
                    ToolbarItem(placement:.cancellationAction){Button("キャンセル"){dismiss()}}
                    ToolbarItem(placement:.confirmationAction){Button("保存"){
                        do { guard feature.kind != "circle" || feature.waypointIDs.count==1 || (feature.waypointIDs.isEmpty && feature.coordinates.count==1) else{throw WaypointArchive.ArchiveError.invalid};if feature.kind=="circle",let id=feature.waypointIDs.first,let center=waypoints.first(where:{$0.id==id}) { feature.name=center.name };try feature.validate();save(feature);dismiss() }catch{self.error="地点数・半径・名前を確認してください。囲みは3地点以上、線は2地点以上が必要です。"}
                    }}
                }
        }.preferredColorScheme(.dark).tint(.orange)
    }
}


/// Preview only: editing never modifies the saved library until Save is tapped.
struct FeatureDraftMap: UIViewRepresentable {
    let feature: MapFeature
    let entries: [WaypointArchive.Entry]
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MKMapView { let map=MKMapView();map.delegate=context.coordinator;return map }
    func updateUIView(_ map:MKMapView,context:Context) {
        context.coordinator.color=UIColor(waypointColor(feature.color));context.coordinator.entries=entries
        map.removeOverlays(map.overlays);map.removeAnnotations(map.annotations)
        let selected=entries.filter{feature.waypointIDs.contains($0.id)}
        let visible=selected.isEmpty ? entries : selected
        for entry in visible { let a=MKPointAnnotation();a.coordinate=CLLocationCoordinate2D(latitude:entry.latitude,longitude:entry.longitude);a.title=entry.name;map.addAnnotation(a) }
        let coordinates=feature.boundary(entries).map{CLLocationCoordinate2D(latitude:$0.latitude,longitude:$0.longitude)}
        if coordinates.count>=3 && feature.kind != "line" { map.addOverlay(MKPolygon(coordinates:coordinates,count:coordinates.count)) }
        else if coordinates.count>=2 { map.addOverlay(MKPolyline(coordinates:coordinates,count:coordinates.count)) }
        let all=coordinates + visible.map{CLLocationCoordinate2D(latitude:$0.latitude,longitude:$0.longitude)}
        var rect=MKMapRect.null
        for coordinate in all { let point=MKMapPoint(coordinate);rect=rect.union(MKMapRect(x:point.x,y:point.y,width:1,height:1)) }
        if !rect.isNull {
            if rect.size.width<100 && rect.size.height<100,let first=all.first { map.setRegion(MKCoordinateRegion(center:first,latitudinalMeters:600,longitudinalMeters:600),animated:false) }
            else { map.setVisibleMapRect(rect,edgePadding:UIEdgeInsets(top:35,left:25,bottom:35,right:25),animated:false) }
        }
    }
    final class Coordinator:NSObject,MKMapViewDelegate {
        var color=UIColor.systemBlue
        var entries:[WaypointArchive.Entry]=[]
        func mapView(_ mapView:MKMapView,viewFor annotation:MKAnnotation)->MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let entry=entries.first{$0.latitude==annotation.coordinate.latitude && $0.longitude==annotation.coordinate.longitude}
            let mark=entry?.mark ?? "symbol:flag.fill"
            let view=MKAnnotationView(annotation:annotation,reuseIdentifier:nil)
            view.image=CompactWaypointMarker.image(name:(annotation as? MKPointAnnotation)?.title ?? "",color:entry.map{UIColor(waypointColor($0.color))} ?? color,markText:mark.hasPrefix("text:") ? String(mark.dropFirst(5)) : nil,markSymbol:mark.hasPrefix("symbol:") ? String(mark.dropFirst(7)) : "flag.fill")
            view.centerOffset=CGPoint(x:0,y:-19);view.displayPriority = .required;view.canShowCallout=true;return view
        }
        func mapView(_ mapView:MKMapView,rendererFor overlay:MKOverlay)->MKOverlayRenderer {
            if let polygon=overlay as? MKPolygon { let r=MKPolygonRenderer(polygon:polygon);r.strokeColor=color;r.fillColor=color.withAlphaComponent(0.22);r.lineWidth=2;return r }
            if let line=overlay as? MKPolyline { let r=MKPolylineRenderer(polyline:line);r.strokeColor=color;r.lineWidth=3;return r }
            return MKOverlayRenderer(overlay:overlay)
        }
    }
}

