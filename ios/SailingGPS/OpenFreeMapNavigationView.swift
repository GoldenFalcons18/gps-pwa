import SwiftUI
import MapLibre
import CoreLocation
import UIKit

struct SavedMapBounds {
    let value: MLNCoordinateBounds
    let zoom: Double
}

struct NavigationMapView: View {
    let location: CLLocation?
    let heading: Double?
    let waypoints: [Waypoint]
    let library: MapLibrary
    let showWaypoints: Bool
    let showCourse: Bool
    let track: [CLLocationCoordinate2D]
    let isRecording: Bool
    @Binding var selected: UUID?
    @Binding var following: Bool
    let metersPerCm: Double
    let onMetersPerCmChanged: (Double) -> Void
    let editWaypoint: (Waypoint) -> Void
    let createWaypoint: (CLLocationCoordinate2D) -> Void
    @AppStorage("mapProvider") private var provider = "apple"
    @AppStorage("courseLineLengthMeters") private var courseLineLengthMeters = 500
    @AppStorage("courseMarkIntervalMeters") private var courseMarkIntervalMeters = 100
    @State private var visibleBounds: SavedMapBounds?
    @State private var showOfflinePicker = false
    @State private var showSaveResult = false
    @State private var saveMessage = ""

    var body: some View {
        Group {
            if provider == "openfreemap" {
                OpenFreeMapMapView(
                    location: location,
                    heading: heading,
                    waypoints: waypoints,
                    library: library,
                    showWaypoints: showWaypoints,
                    showCourse: showCourse,
                    courseLineLengthMeters: courseLineLengthMeters,
                    courseMarkIntervalMeters: courseMarkIntervalMeters,
                    track: track,
                    isRecording: isRecording,
                    selected: $selected,
                    following: $following,
                    metersPerCm: metersPerCm,
                    onMetersPerCmChanged: onMetersPerCmChanged,
                    editWaypoint: editWaypoint,
                    createWaypoint: createWaypoint,
                    onViewportChanged: { bounds, zoom in visibleBounds = SavedMapBounds(value: bounds, zoom: zoom) }
                )
                .fullScreenCover(isPresented: $showOfflinePicker) {
                    OfflineRegionPickerView(initialBounds: visibleBounds) { bounds, minZoom, maxZoom, name in
                        OpenFreeMapOfflineStore.save(bounds: bounds, minZoom: minZoom, maxZoom: maxZoom, name: name) { message in
                            saveMessage = message
                            showSaveResult = true
                        }
                    }
                }
                .alert("地図の保存", isPresented: $showSaveResult) {
                    Button("閉じる") { saveMessage = "" }
                } message: { Text(saveMessage) }
            } else {
                AppleNavigationMapView(
                    location: location, heading: heading, waypoints: waypoints, library: library,
                    showWaypoints: showWaypoints, showCourse: showCourse,
                    courseLineLengthMeters: courseLineLengthMeters,
                    courseMarkIntervalMeters: courseMarkIntervalMeters,
                    track: track,
                    isRecording: isRecording, selected: $selected, following: $following, metersPerCm: metersPerCm,
                    onMetersPerCmChanged: onMetersPerCmChanged,
                    editWaypoint: editWaypoint, createWaypoint: createWaypoint
                )
            }
        }
    }
}

enum OpenFreeMapOfflineStore {
    static let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

    static func save(bounds: MLNCoordinateBounds, minZoom: Int, maxZoom: Int, name: String, completion: @escaping (String) -> Void) {
        let storage = MLNOfflineStorage.shared
        storage.setMaximumAllowedMapboxTiles(3000)
        let region = MLNTilePyramidOfflineRegion(
            styleURL: styleURL,
            bounds: bounds,
            fromZoomLevel: Double(minZoom),
            toZoomLevel: Double(maxZoom)
        )
        let context = (try? JSONSerialization.data(withJSONObject: [
            "name": name,
            "provider": "OpenFreeMap"
        ])) ?? Data()
        storage.addPack(for: region, withContext: context) { pack, error in
            DispatchQueue.main.async {
                guard let pack else {
                    completion(error?.localizedDescription ?? "地図を保存できませんでした。")
                    return
                }
                pack.resume()
                completion("地図の保存を開始しました。通信状況により完了まで時間がかかります。")
            }
        }
    }
}

struct OfflineRegionPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let initialBounds: SavedMapBounds?
    let onSave: (MLNCoordinateBounds, Int, Int, String) -> Void
    @State private var selectedBounds: SavedMapBounds?
    @State private var minZoom = 8
    @State private var maxZoom = 12
    @State private var name = "オフライン地図"
    @State private var didInitializeZoom = false
    @State private var previewMinimumZoom = true

    private var tileCount: Int64 {
        guard let selectedBounds else { return 0 }
        return Self.estimate(selectedBounds.value, minZoom: minZoom, maxZoom: maxZoom)
    }
    private var saveAllowed: Bool { tileCount > 0 && tileCount <= 3_000 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                OfflineRegionMap(initial: initialBounds) { bounds, zoom in
                    selectedBounds = SavedMapBounds(value: bounds, zoom: zoom)
                    if !didInitializeZoom {
                        didInitializeZoom = true
                        maxZoom = Int(zoom.rounded()).clamped(to: 4...18)
                        minZoom = max(4, maxZoom - 2)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .inset(by: 24)
                        .stroke(Color.orange, lineWidth: 2)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .top) {
                    Text("枠内を保存します · 地図を動かして範囲を選択")
                        .font(.footnote.bold())
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.65))
                        .foregroundStyle(.white)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)

                if let selectedBounds {
                    let sw = selectedBounds.value.sw
                    let ne = selectedBounds.value.ne
                    Text(String(format: "南西 %.4f°, %.4f°   北東 %.4f°, %.4f°", sw.latitude, sw.longitude, ne.latitude, ne.longitude))
                        .font(.caption.monospacedDigit())
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("地図範囲を読み込み中…").font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    Button("最小ズーム") { previewMinimumZoom = true }
                        .buttonStyle(.bordered).tint(previewMinimumZoom ? .orange : .gray)
                    Button("最大ズーム") { previewMinimumZoom = false }
                        .buttonStyle(.bordered).tint(previewMinimumZoom ? .gray : .orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(previewMinimumZoom ? "最小" : "最大")ズーム \(previewMinimumZoom ? minZoom : maxZoom) の地図表示")
                    .font(.caption.bold()).frame(maxWidth: .infinity, alignment: .leading)
                OfflineZoomPreviewMap(
                    bounds: selectedBounds ?? initialBounds,
                    zoom: Double(previewMinimumZoom ? minZoom : maxZoom)
                )
                .frame(height: 145)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                TextField("保存名", text: $name)
                    .textFieldStyle(.roundedBorder)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("最小ズーム")
                        Spacer()
                        Text("\(minZoom)").monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { Double(minZoom) },
                        set: { minZoom = min(Int($0.rounded()), maxZoom) }
                    ), in: 4...18, step: 1)
                    HStack {
                        Text("最大ズーム")
                        Spacer()
                        Text("\(maxZoom)").monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { Double(maxZoom) },
                        set: { maxZoom = max(Int($0.rounded()), minZoom) }
                    ), in: 4...18, step: 1)
                }
                .font(.footnote)
                .padding(.horizontal, 4)

                Text(tileCount <= 3_000
                     ? "保存タイル: \(tileCount.formatted()) / 3,000"
                     : "保存タイル: \(tileCount.formatted())（上限 3,000。範囲またはズームを小さくしてください）")
                    .font(.callout.bold())
                    .foregroundStyle(saveAllowed ? .white : .red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .navigationTitle("オフラインマップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let selectedBounds, saveAllowed else { return }
                        onSave(selectedBounds.value, minZoom, maxZoom, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "オフライン地図" : name)
                        dismiss()
                    }.disabled(!saveAllowed)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.orange)
    }

    private static func estimate(_ bounds: MLNCoordinateBounds, minZoom: Int, maxZoom: Int) -> Int64 {
        let west = bounds.sw.longitude, east = bounds.ne.longitude
        let south = max(-85.05112878, min(85.05112878, bounds.sw.latitude))
        let north = max(-85.05112878, min(85.05112878, bounds.ne.latitude))
        guard west.isFinite, east.isFinite, south.isFinite, north.isFinite, south <= north else { return 0 }
        var total: Int64 = 0
        for zoom in minZoom...maxZoom {
            let n = pow(2.0, Double(zoom))
            let maxIndex = Int64(n) - 1
            let x0 = Int64(floor((west + 180) / 360 * n)).clamped(to: 0...maxIndex)
            let x1 = Int64(floor((east + 180) / 360 * n)).clamped(to: 0...maxIndex)
            func y(_ latitude: Double) -> Int64 {
                let radians = latitude * .pi / 180
                return Int64(floor((1 - asinh(tan(radians)) / .pi) / 2 * n)).clamped(to: 0...maxIndex)
            }
            let yNorth = y(north), ySouth = y(south)
            let xCount = east >= west ? x1 - x0 + 1 : maxIndex + 1 - x0 + x1 + 1
            let rows = ySouth - yNorth + 1
            if xCount > 3_000 || rows > 3_000 || xCount * rows > 3_000 - total { return 3_001 }
            total += xCount * rows
        }
        return total
    }
}

private struct OfflineZoomPreviewMap: UIViewRepresentable {
    let bounds: SavedMapBounds?
    let zoom: Double

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: OpenFreeMapOfflineStore.styleURL)
        map.isPitchEnabled = false
        map.isScrollEnabled = false
        map.isZoomEnabled = false
        map.isRotateEnabled = false
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let center: CLLocationCoordinate2D
        if let bounds {
            center = CLLocationCoordinate2D(
                latitude: (bounds.value.sw.latitude + bounds.value.ne.latitude) / 2,
                longitude: (bounds.value.sw.longitude + bounds.value.ne.longitude) / 2
            )
        } else {
            center = CLLocationCoordinate2D(latitude: 35.30, longitude: 139.48)
        }
        if abs(map.zoomLevel - zoom) > 0.05 || CLLocation(latitude: map.centerCoordinate.latitude, longitude: map.centerCoordinate.longitude)
            .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude)) > 5 {
            map.setCenter(center, zoomLevel: zoom, animated: false)
        }
    }
}

struct OfflineMapSettingsAction: View {
    @State private var showingPicker = false
    @State private var showingResult = false
    @State private var result = ""

    var body: some View {
        Button("オフライン地図を保存") { showingPicker = true }
            .fullScreenCover(isPresented: $showingPicker) {
                OfflineRegionPickerView(initialBounds: nil) { bounds, minZoom, maxZoom, name in
                    OpenFreeMapOfflineStore.save(bounds: bounds, minZoom: minZoom, maxZoom: maxZoom, name: name) { message in
                        result = message
                        showingResult = true
                    }
                }
            }
            .alert("オフライン地図", isPresented: $showingResult) {
                Button("閉じる") { result = "" }
            } message: {
                Text(result)
            }
    }
}

private struct OfflineRegionMap: UIViewRepresentable {
    let initial: SavedMapBounds?
    let onViewportChanged: (MLNCoordinateBounds, Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onViewportChanged) }
    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: OpenFreeMapOfflineStore.styleURL)
        map.delegate = context.coordinator
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        if let initial {
            let center = CLLocationCoordinate2D(
                latitude: (initial.value.sw.latitude + initial.value.ne.latitude) / 2,
                longitude: (initial.value.sw.longitude + initial.value.ne.longitude) / 2
            )
            map.setCenter(center, zoomLevel: initial.zoom, animated: false)
        } else {
            map.setCenter(CLLocationCoordinate2D(latitude: 35.30, longitude: 139.48), zoomLevel: 11, animated: false)
        }
        return map
    }
    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.onViewportChanged = onViewportChanged
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var onViewportChanged: (MLNCoordinateBounds, Double) -> Void
        init(_ onViewportChanged: @escaping (MLNCoordinateBounds, Double) -> Void) {
            self.onViewportChanged = onViewportChanged
        }
        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) { report(mapView) }
        func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) { report(mapView) }
        private func report(_ map: MLNMapView) {
            let inset: CGFloat = 24
            guard map.bounds.width > inset * 2, map.bounds.height > inset * 2 else { return }
            let sw = map.convert(CGPoint(x: inset, y: map.bounds.height - inset), toCoordinateFrom: map)
            let ne = map.convert(CGPoint(x: map.bounds.width - inset, y: inset), toCoordinateFrom: map)
            onViewportChanged(MLNCoordinateBounds(sw: sw, ne: ne), map.zoomLevel)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

private struct OpenFreeMapMapView: UIViewRepresentable {
    let location: CLLocation?
    let heading: Double?
    let waypoints: [Waypoint]
    let library: MapLibrary
    let showWaypoints: Bool
    let showCourse: Bool
    let courseLineLengthMeters: Int
    let courseMarkIntervalMeters: Int
    let track: [CLLocationCoordinate2D]
    let isRecording: Bool
    @Binding var selected: UUID?
    @Binding var following: Bool
    let metersPerCm: Double
    let onMetersPerCmChanged: (Double) -> Void
    let editWaypoint: (Waypoint) -> Void
    let createWaypoint: (CLLocationCoordinate2D) -> Void
    let onViewportChanged: (MLNCoordinateBounds, Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: OpenFreeMapOfflineStore.styleURL)
        map.delegate = context.coordinator
        map.isPitchEnabled = false
        map.showsCompassView = true
        map.showsAttributionButton = true
        map.centerCoordinate = CLLocationCoordinate2D(latitude: 35.30, longitude: 139.48)
        map.zoomLevel = 12
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        for recognizer in map.gestureRecognizers ?? [] where recognizer is UILongPressGestureRecognizer {
            press.require(toFail: recognizer)
        }
        map.addGestureRecognizer(press)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.render(map)
    }

    final class Pin: MLNPointAnnotation {
        var waypointID: UUID?
        var isBoat = false
        var markText: String?
        var markSymbol: String?
        var colorName: String?
        var courseDistance: Int?
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: OpenFreeMapMapView
        weak var map: MLNMapView?
        private var pins: [Pin] = []
        private var boatPin: Pin?
        private var coursePins: [Int: Pin] = [:]
        private var waypointSignature = ""
        private var cameraUpdateInProgress = false
        private var previousMetersPerCm: Double?
        private var followZoomOffset: Double?
        private var lastTrackRecording: Bool?
        private var userScaleChangePending = false

        init(_ parent: OpenFreeMapMapView) { self.parent = parent }

        func render(_ map: MLNMapView) {
            self.map = map
            if let previousMetersPerCm, previousMetersPerCm != parent.metersPerCm, !parent.following {
                let zoom = map.zoomLevel + log2(previousMetersPerCm / parent.metersPerCm)
                map.zoomLevel = min(max(zoom, 2), 20)
            }
            previousMetersPerCm = parent.metersPerCm
            let visibleWaypoints = parent.showWaypoints
                ? parent.waypoints.filter { !parent.library.hiddenGroups.contains($0.group ?? "") }
                : []
            let signature = visibleWaypoints.map {
                "\($0.id.uuidString):\($0.latitude):\($0.longitude):\($0.name):\($0.markText ?? ""):\($0.markSymbol ?? "flag.fill"):\($0.colorName ?? "orange")"
            }.joined(separator: "|") + "|" + parent.library.hiddenGroups.sorted().joined(separator: ",")
            if signature != waypointSignature {
                let oldPins = pins.filter { !$0.isBoat }
                map.removeAnnotations(oldPins)
                pins.removeAll { !$0.isBoat }
                if parent.showWaypoints {
                    let newPins = visibleWaypoints.map { waypoint -> Pin in
                        let pin = Pin()
                        pin.coordinate = waypoint.coordinate
                        pin.title = waypoint.name
                        pin.subtitle = waypoint.note
                        pin.waypointID = waypoint.id
                        pin.markText = waypoint.markText
                        pin.markSymbol = waypoint.markSymbol
                        pin.colorName = waypoint.colorName
                        pins.append(pin)
                        return pin
                    }
                    map.addAnnotations(newPins)
                }
                waypointSignature = signature
            }
            if let location = parent.location {
                if let boatPin {
                    boatPin.coordinate = location.coordinate
                } else {
                    let boat = Pin()
                    boat.coordinate = location.coordinate
                    boat.title = "現在地"
                    boat.isBoat = true
                    boat.markText = "▲"
                    boatPin = boat
                    pins.append(boat)
                    map.addAnnotation(boat)
                }
            }
            updateLines(map)

            if parent.following, let location = parent.location {
                cameraUpdateInProgress = true
                let baseZoom = 17 - log2(max(parent.metersPerCm, 12.5) / 25)
                let zoom = min(18, max(5, baseZoom + (followZoomOffset ?? 0)))
                map.setCenter(location.coordinate, zoomLevel: zoom, direction: parent.heading ?? 0, animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.cameraUpdateInProgress = false }
            }
        }

        private func updateLines(_ map: MLNMapView) {
            guard let style = map.style else { return }
            let trackColor = parent.isRecording ? UIColor.systemOrange : UIColor.systemGray
            let definitions: [(String, UIColor, CGFloat)] = [
                ("sailing-track", trackColor, 4),
                ("sailing-target", .systemGreen, 3),
                ("sailing-course", .black, 2)
            ]
            for (sourceID, color, width) in definitions {
                let layerID = sourceID + "-line"
                let source: MLNShapeSource
                if let existing = style.source(withIdentifier: sourceID) as? MLNShapeSource {
                    source = existing
                } else {
                    source = MLNShapeSource(identifier: sourceID, shape: nil, options: nil)
                    style.addSource(source)
                }
                if style.layer(withIdentifier: layerID) == nil {
                    let layer = MLNLineStyleLayer(identifier: layerID, source: source)
                    layer.lineColor = NSExpression(forConstantValue: color)
                    layer.lineWidth = NSExpression(forConstantValue: width)
                    layer.lineCap = NSExpression(forConstantValue: "round")
                    style.addLayer(layer)
                }
            }
            if lastTrackRecording != parent.isRecording {
                (style.layer(withIdentifier: "sailing-track-line") as? MLNLineStyleLayer)?.lineColor = NSExpression(forConstantValue: trackColor)
                lastTrackRecording = parent.isRecording
            }
            (style.source(withIdentifier: "sailing-track") as? MLNShapeSource)?.shape =
                parent.track.count > 1 ? makeLine(parent.track) : nil
            let target = parent.location.flatMap { location -> MLNPolyline? in
                guard let waypoint = parent.waypoints.first(where: {
                    $0.id == parent.selected && !parent.library.hiddenGroups.contains($0.group ?? "")
                }) else { return nil }
                return makeLine([location.coordinate, waypoint.coordinate])
            }
            (style.source(withIdentifier: "sailing-target") as? MLNShapeSource)?.shape = target
            let course = parent.location.flatMap { location -> MLNPolyline? in
                guard parent.showCourse, let heading = parent.heading else { return nil }
                let length = parent.courseLineLengthMeters.clamped(to: 100...5000)
                let interval = parent.courseMarkIntervalMeters.clamped(to: 25...length)
                let distances = Array(stride(from: interval, through: length, by: interval))
                var coordinates = [location.coordinate]
                coordinates.append(contentsOf: distances.map {
                    Self.destination(from: location.coordinate, bearing: heading, meters: Double($0))
                })
                if distances.last != length {
                    coordinates.append(Self.destination(from: location.coordinate, bearing: heading, meters: Double(length)))
                }
                return makeLine(coordinates)
            }
            (style.source(withIdentifier: "sailing-course") as? MLNShapeSource)?.shape = course

            let validDistances = Set(stride(
                from: parent.courseMarkIntervalMeters.clamped(to: 25...parent.courseLineLengthMeters.clamped(to: 100...5000)),
                through: parent.courseLineLengthMeters.clamped(to: 100...5000),
                by: parent.courseMarkIntervalMeters.clamped(to: 25...parent.courseLineLengthMeters.clamped(to: 100...5000))
            ))
            if parent.showCourse, let location = parent.location, let heading = parent.heading {
                for distance in validDistances {
                    let pin: Pin
                    if let existing = coursePins[distance] {
                        pin = existing
                    } else {
                        pin = Pin()
                        pin.courseDistance = distance
                        pin.title = "\(distance) m"
                        coursePins[distance] = pin
                        map.addAnnotation(pin)
                    }
                    pin.coordinate = Self.destination(from: location.coordinate, bearing: heading, meters: Double(distance))
                }
            } else {
                for pin in coursePins.values { map.removeAnnotation(pin) }
                coursePins.removeAll()
            }
            let staleDistances = coursePins.keys.filter { !validDistances.contains($0) }
            for distance in staleDistances {
                if let pin = coursePins.removeValue(forKey: distance) {
                    map.removeAnnotation(pin)
                }
            }
        }

        private func makeLine(_ coordinates: [CLLocationCoordinate2D]) -> MLNPolyline? {
            guard coordinates.count > 1 else { return nil }
            var points = coordinates
            guard let first = points.withUnsafeBufferPointer({ $0.baseAddress }) else { return nil }
            return MLNPolyline(coordinates: first, count: UInt(points.count))
        }

        private func makeLine(_ coordinates: [CLLocationCoordinate2D], title: String) -> MLNPolyline? {
            guard coordinates.count > 1 else { return nil }
            var points = coordinates
            guard let first = points.withUnsafeBufferPointer({ $0.baseAddress }) else { return nil }
            let line = MLNPolyline(coordinates: first, count: UInt(points.count))
            line.title = title
            return line
        }

        private static func destination(from start: CLLocationCoordinate2D, bearing: Double, meters: Double) -> CLLocationCoordinate2D {
            let radius = 6_371_000.0
            let angular = meters / radius
            let direction = bearing * .pi / 180
            let lat1 = start.latitude * .pi / 180
            let lon1 = start.longitude * .pi / 180
            let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(direction))
            let lon2 = lon1 + atan2(sin(direction) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
            return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
        }

        @objc func longPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map else { return }
            parent.following = false
            let coordinate = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            let visibleWaypoints = parent.showWaypoints
                ? parent.waypoints.filter { !parent.library.hiddenGroups.contains($0.group ?? "") }
                : []
            let hit = visibleWaypoints.min {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                < CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            }.flatMap { waypoint -> Waypoint? in
                CLLocation(latitude: waypoint.latitude, longitude: waypoint.longitude).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) < 55 ? waypoint : nil
            }
            if let hit { parent.editWaypoint(hit) } else { parent.createWaypoint(coordinate) }
        }

        func mapView(_ mapView: MLNMapView, regionWillChangeAnimated animated: Bool) {
            let interacting = mapView.gestureRecognizers?.contains {
                $0.state == .began || $0.state == .changed
            } ?? false
            if interacting {
                userScaleChangePending = true
                if !cameraUpdateInProgress { parent.following = false }
            }
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            parent.onViewportChanged(mapView.visibleCoordinateBounds, mapView.zoomLevel)
            guard userScaleChangePending else { return }
            userScaleChangePending = false
            let pointsPerCm = (UIDevice.current.userInterfaceIdiom == .pad ? 132.0 : 163.0) / 2.54
            let left = mapView.convert(CGPoint(x: 0, y: mapView.bounds.midY), toCoordinateFrom: mapView)
            let right = mapView.convert(CGPoint(x: mapView.bounds.maxX, y: mapView.bounds.midY), toCoordinateFrom: mapView)
            let physicalWidthCm = mapView.bounds.width / pointsPerCm
            guard physicalWidthCm > 0 else { return }
            let scale = CLLocation(latitude: left.latitude, longitude: left.longitude)
                .distance(from: CLLocation(latitude: right.latitude, longitude: right.longitude)) / physicalWidthCm
            guard scale.isFinite, scale > 0, abs(scale - parent.metersPerCm) / parent.metersPerCm > 0.02 else { return }
            let calibratedScale = min(max(scale, 12.5), 6400)
            let baseZoom = 17 - log2(max(calibratedScale, 12.5) / 25)
            followZoomOffset = mapView.zoomLevel - baseZoom
            previousMetersPerCm = calibratedScale
            DispatchQueue.main.async { self.parent.onMetersPerCmChanged(calibratedScale) }
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            updateLines(mapView)
        }

        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            switch annotation.title ?? "" {
            case "track": return .systemOrange
            case "target": return .systemGreen
            default: return .white
            }
        }

        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat {
            annotation.title == "track" ? 4 : 3
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard let pin = annotation as? Pin else { return nil }
            let id = pin.courseDistance != nil ? "course-distance" : (pin.isBoat ? "boat" : "waypoint")
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) ?? MLNAnnotationView(annotation: pin, reuseIdentifier: id)
            view.annotation = pin
            if let distance = pin.courseDistance {
                view.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
                view.backgroundColor = .black
                view.layer.cornerRadius = 4
                view.layer.borderWidth = 1
                view.layer.borderColor = UIColor.white.cgColor
                view.subviews.forEach { $0.removeFromSuperview() }
                return view
            }
            view.bounds = CGRect(x: 0, y: 0, width: 156, height: 54)
            view.centerOffset = CGVector(dx: 0, dy: 10)
            view.backgroundColor = .clear
            view.layer.cornerRadius = 0
            view.layer.borderWidth = 0
            view.subviews.forEach { $0.removeFromSuperview() }

            let marker = UIView(frame: CGRect(x: 61, y: 0, width: 34, height: 34))
            marker.backgroundColor = pin.isBoat ? UIColor.black : UIColor(waypointColor(pin.colorName))
            marker.layer.cornerRadius = 17
            marker.layer.borderWidth = 1.5
            marker.layer.borderColor = UIColor.white.cgColor
            view.addSubview(marker)
            if let markText = pin.markText, !markText.isEmpty {
                let mark = UILabel(frame: marker.bounds)
                mark.text = markText
                mark.textColor = .white
                mark.font = .boldSystemFont(ofSize: 16)
                mark.textAlignment = .center
                mark.adjustsFontSizeToFitWidth = true
                mark.minimumScaleFactor = 0.6
                marker.addSubview(mark)
            } else {
                let image = UIImageView(frame: marker.bounds.insetBy(dx: 7, dy: 7))
                image.image = MarineMarks.image(pin.markSymbol ?? "flag.fill").withRenderingMode(.alwaysTemplate)
                image.tintColor = .white
                image.contentMode = .scaleAspectFit
                marker.addSubview(image)
            }
            if !pin.isBoat, let name = pin.title, !name.isEmpty {
                let nameLabel = UILabel(frame: CGRect(x: 0, y: 36, width: 156, height: 17))
                nameLabel.text = name
                nameLabel.textColor = .white
                nameLabel.backgroundColor = UIColor.black.withAlphaComponent(0.82)
                nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
                nameLabel.textAlignment = .center
                nameLabel.adjustsFontSizeToFitWidth = true
                nameLabel.minimumScaleFactor = 0.65
                nameLabel.lineBreakMode = .byTruncatingTail
                nameLabel.layer.cornerRadius = 4
                nameLabel.clipsToBounds = true
                view.addSubview(nameLabel)
            }
            return view
        }

    }
}
