import SwiftUI
import MapLibre
import CoreLocation
import UIKit

private struct SavedMapBounds {
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
    @Binding var selected: UUID?
    @Binding var following: Bool
    let metersPerCm: Double
    let editWaypoint: (Waypoint) -> Void
    let createWaypoint: (CLLocationCoordinate2D) -> Void
    @AppStorage("mapProvider") private var provider = "apple"
    @State private var visibleBounds: SavedMapBounds?
    @State private var showSaveConfirmation = false
    @State private var showSaveResult = false
    @State private var saveMessage = ""

    var body: some View {
        Group {
            if provider == "openfreemap" {
                OpenFreeMapMapView(
                    location: location,
                    heading: heading,
                    waypoints: waypoints,
                    showWaypoints: showWaypoints,
                    showCourse: showCourse,
                    track: track,
                    selected: $selected,
                    following: $following,
                    metersPerCm: metersPerCm,
                    editWaypoint: editWaypoint,
                    createWaypoint: createWaypoint,
                    onViewportChanged: { bounds, zoom in visibleBounds = SavedMapBounds(value: bounds, zoom: zoom) }
                )
                .overlay(alignment: .bottomTrailing) {
                    Button("地図を保存") { showSaveConfirmation = true }
                        .font(.caption).buttonStyle(.borderedProminent).tint(.orange)
                        .foregroundStyle(.black).padding(8)
                }
                .alert("オフライン地図を保存", isPresented: $showSaveConfirmation) {
                    Button("保存") {
                        guard let visibleBounds else {
                            saveMessage = "地図の範囲を取得できませんでした。"
                            showSaveResult = true
                            return
                        }
                        OpenFreeMapOfflineStore.save(bounds: visibleBounds, completion: { message in
                            saveMessage = message
                            showSaveResult = true
                        })
                    }
                    Button("キャンセル", role: .cancel) {}
                } message: {
                    Text("現在表示している範囲を保存します。端末全体で最大3,000タイルまで保存します。")
                }
                .alert("地図の保存", isPresented: $showSaveResult) {
                    Button("閉じる") { saveMessage = "" }
                } message: { Text(saveMessage) }
            } else {
                AppleNavigationMapView(
                    location: location, heading: heading, waypoints: waypoints, library: library,
                    showWaypoints: showWaypoints, showCourse: showCourse, track: track,
                    selected: $selected, following: $following, metersPerCm: metersPerCm,
                    editWaypoint: editWaypoint, createWaypoint: createWaypoint
                )
            }
        }
    }
}

private enum OpenFreeMapOfflineStore {
    static let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

    static func save(bounds: SavedMapBounds, completion: @escaping (String) -> Void) {
        let storage = MLNOfflineStorage.shared
        storage.setMaximumAllowedMapboxTiles(3000)
        let region = MLNTilePyramidOfflineRegion(
            styleURL: styleURL,
            bounds: bounds.value,
            fromZoomLevel: max(4, bounds.zoom - 1),
            toZoomLevel: min(18, bounds.zoom + 2)
        )
        let context = (try? JSONSerialization.data(withJSONObject: [
            "name": "表示範囲",
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

private struct OpenFreeMapMapView: UIViewRepresentable {
    let location: CLLocation?
    let heading: Double?
    let waypoints: [Waypoint]
    let showWaypoints: Bool
    let showCourse: Bool
    let track: [CLLocationCoordinate2D]
    @Binding var selected: UUID?
    @Binding var following: Bool
    let metersPerCm: Double
    let editWaypoint: (Waypoint) -> Void
    let createWaypoint: (CLLocationCoordinate2D) -> Void
    let onViewportChanged: (MLNCoordinateBounds, Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: OpenFreeMapOfflineStore.styleURL)
        map.delegate = context.coordinator
        map.pitchEnabled = false
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
        var mark = "●"
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: OpenFreeMapMapView
        weak var map: MLNMapView?
        private var pins: [Pin] = []
        private var boatPin: Pin?
        private var waypointSignature = ""
        private var cameraUpdateInProgress = false

        init(_ parent: OpenFreeMapMapView) { self.parent = parent }

        func render(_ map: MLNMapView) {
            self.map = map
            let signature = parent.showWaypoints
                ? parent.waypoints.map { "\($0.id.uuidString):\($0.latitude):\($0.longitude):\($0.name):\($0.markText ?? $0.markSymbol ?? "●")" }.joined(separator: "|")
                : "hidden"
            if signature != waypointSignature {
                let oldPins = pins.filter { !$0.isBoat }
                map.removeAnnotations(oldPins)
                pins.removeAll { !$0.isBoat }
                if parent.showWaypoints {
                    let newPins = parent.waypoints.map { waypoint -> Pin in
                        let pin = Pin()
                        pin.coordinate = waypoint.coordinate
                        pin.title = waypoint.name
                        pin.subtitle = waypoint.note
                        pin.waypointID = waypoint.id
                        pin.mark = waypoint.markText ?? waypoint.markSymbol ?? "●"
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
                    boat.mark = "▲"
                    boatPin = boat
                    pins.append(boat)
                    map.addAnnotation(boat)
                }
            }
            updateLines(map)

            if parent.following, let location = parent.location {
                cameraUpdateInProgress = true
                let zoom = min(18, max(5, 17 - log2(max(parent.metersPerCm, 12.5) / 25)))
                map.setCenter(location.coordinate, zoomLevel: zoom, direction: parent.heading ?? 0, animated: false)
                DispatchQueue.main.async { self.cameraUpdateInProgress = false }
            }
            parent.onViewportChanged(map.visibleCoordinateBounds, map.zoomLevel)
        }

        private func updateLines(_ map: MLNMapView) {
            guard let style = map.style else { return }
            let definitions: [(String, UIColor, CGFloat)] = [
                ("sailing-track", .systemOrange, 4),
                ("sailing-target", .systemGreen, 3),
                ("sailing-course", .white, 2)
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
            (style.source(withIdentifier: "sailing-track") as? MLNShapeSource)?.shape =
                parent.track.count > 1 ? makeLine(parent.track) : nil
            let target = parent.location.flatMap { location -> MLNPolyline? in
                guard let waypoint = parent.waypoints.first(where: { $0.id == parent.selected }) else { return nil }
                return makeLine([location.coordinate, waypoint.coordinate])
            }
            (style.source(withIdentifier: "sailing-target") as? MLNShapeSource)?.shape = target
            let course = parent.location.flatMap { location -> MLNPolyline? in
                guard parent.showCourse, let heading = parent.heading else { return nil }
                return makeLine([location.coordinate, Self.destination(from: location.coordinate, bearing: heading, meters: 2500)])
            }
            (style.source(withIdentifier: "sailing-course") as? MLNShapeSource)?.shape = course
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
            let hit = parent.waypoints.min {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                < CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            }.flatMap { waypoint -> Waypoint? in
                CLLocation(latitude: waypoint.latitude, longitude: waypoint.longitude).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) < 55 ? waypoint : nil
            }
            if let hit { parent.editWaypoint(hit) } else { parent.createWaypoint(coordinate) }
        }

        func mapView(_ mapView: MLNMapView, regionWillChangeAnimated animated: Bool) {
            if mapView.gestureInProgress && !cameraUpdateInProgress { parent.following = false }
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            parent.onViewportChanged(mapView.visibleCoordinateBounds, mapView.zoomLevel)
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
            let id = pin.isBoat ? "boat" : "waypoint"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) ?? MLNAnnotationView(annotation: pin, reuseIdentifier: id)
            view.annotation = pin
            view.bounds = CGRect(x: 0, y: 0, width: 34, height: 34)
            view.backgroundColor = pin.isBoat ? UIColor.black : UIColor.systemOrange
            view.layer.cornerRadius = 17
            view.layer.borderWidth = 1.5
            view.layer.borderColor = UIColor.white.cgColor
            let label = UILabel(frame: view.bounds)
            label.text = pin.mark
            label.textColor = .white
            label.font = .boldSystemFont(ofSize: 16)
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.6
            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(label)
            return view
        }

        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            guard let pin = annotation as? Pin, let id = pin.waypointID else { return }
            parent.selected = id
        }
    }
}
