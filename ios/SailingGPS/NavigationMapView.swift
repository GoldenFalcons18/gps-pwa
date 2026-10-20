import SwiftUI
import MapKit

/// Map projection and course marks are display-only; they never enter the recorded track.
struct NavigationMapView: UIViewRepresentable {
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
    let showAllRequest: Int
    let editWaypoint: (Waypoint) -> Void
    let createWaypoint: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isPitchEnabled = false
        map.showsCompass = true
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        map.addGestureRecognizer(press)
        map.setRegion(MKCoordinateRegion(center: .init(latitude: 35.30, longitude: 139.48), latitudinalMeters: 3000, longitudinalMeters: 3000), animated: false)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        // Defer until MapKit has a laid-out view so the physical scale can be measured.
        DispatchQueue.main.async { coordinator.render(map) }
    }

    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.stopAnimation()
        map.delegate = nil
    }

    final class Pin: MKPointAnnotation {
        var id: UUID?
        var kind = "waypoint"
        var colorName: String?
        var markSymbol: String?
        var markText: String?
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NavigationMapView
        var lastShowAll = 0
        private var didInitialWaypointFit = false
        private var rendering = false
        private var signature = ""
        private var courseHeading: Double?
        private var lastLocationTime: Date?
        private var lastTrackCount = -1
        private weak var map: MKMapView?
        private var displayLink: CADisplayLink?
        private var shownHeading: Double?
        private var frameTime: CFTimeInterval = 0
        private var scaleSignature = ""
        private var wasFollowing = false
        private var previousScale: Double?
        func stopAnimation() {
            displayLink?.invalidate(); displayLink = nil; frameTime = 0
        }
        private func startAnimation() {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(animateHeading(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        @objc private func animateHeading(_ link: CADisplayLink) {
            guard parent.following, let map, let target = parent.heading else { stopAnimation(); return }
            let previous = shownHeading ?? target
            let unwrapped = CoordinateInput.unwrapHeading(from: previous, to: target)
            let dt = frameTime == 0 ? 1.0 / 30 : min(0.05, link.timestamp - frameTime)
            frameTime = link.timestamp
            shownHeading = previous + (unwrapped - previous) * (1 - exp(-dt / 0.12))
            applyCamera(map)
            if abs(unwrapped - previous) < 0.05 { stopAnimation() }
        }
        private func applyCamera(_ map: MKMapView) {
            guard parent.following, let point = parent.location, map.bounds.width > 0, map.bounds.height > 0 else { return }
            let camera = map.camera.copy() as! MKMapCamera
            camera.heading = CoordinateInput.normalizeHeading(shownHeading ?? parent.heading ?? 0)
            let pointsPerCm = (UIDevice.current.userInterfaceIdiom == .pad ? 132.0 : 163.0) / 2.54
            let center = CoordinateInput.followCenter(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude, heading: camera.heading, mapHeight: map.bounds.height, pointsPerCm: pointsPerCm, metersPerCm: parent.metersPerCm)
            camera.centerCoordinate = .init(latitude: center.latitude, longitude: center.longitude)
            camera.pitch = 0
            map.setCamera(camera, animated: false)
            // Recalibrate scale for layout/location changes, not for every compass sample.
            let key = "\(map.bounds.size)|\((point.coordinate.latitude * 100).rounded())|\(parent.metersPerCm)"
            if key != scaleSignature {
                scaleSignature = key
                let desiredMetersPerPoint = parent.metersPerCm / pointsPerCm
                let mid = CGPoint(x: map.bounds.midX, y: map.bounds.midY)
                let a = map.convert(CGPoint(x: mid.x - 25, y: mid.y), toCoordinateFrom: map)
                let b = map.convert(CGPoint(x: mid.x + 25, y: mid.y), toCoordinateFrom: map)
                let measured = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 50
                if measured.isFinite && measured > 0 {
                    camera.altitude = max(1, camera.altitude * desiredMetersPerPoint / measured)
                    map.setCamera(camera, animated: false)
                }
            }
            updateBoatRotation(map)
        }
        private func updateBoatRotation(_ map: MKMapView) {
            for pin in map.annotations.compactMap({ $0 as? Pin }) where pin.kind == "boat" {
                map.view(for: pin)?.transform = CGAffineTransform(rotationAngle: ((parent.heading ?? 0) - map.camera.heading) * .pi / 180)
            }
        }
        private func updateCourse(_ map: MKMapView) {
            let existingDots = map.annotations.compactMap { $0 as? Pin }.filter { $0.kind == "course" }
            map.removeOverlays(map.overlays.filter { ($0 as? MKPolyline)?.title == "course" })
            courseHeading = parent.heading
            guard parent.showCourse, let location = parent.location, let heading = parent.heading else { map.removeAnnotations(existingDots); return }
            var coordinates = [location.coordinate]
            for distance in stride(from: 100, through: 500, by: 100) {
                let q = CoordinateInput.destination(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, bearing: heading, meters: Double(distance))
                let coordinate = CLLocationCoordinate2D(latitude: q.latitude, longitude: q.longitude)
                coordinates.append(coordinate)
                let title = "\(distance) m"
                if let dot = existingDots.first(where: { $0.title == title }) { dot.coordinate = coordinate }
                else { let dot = Pin(); dot.kind = "course"; dot.title = title; dot.coordinate = coordinate; map.addAnnotation(dot) }
            }
            let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
            line.title = "course"; map.addOverlay(line)
        }
        init(_ parent: NavigationMapView) { self.parent = parent }

        @objc func longPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map = gesture.view as? MKMapView else { return }
            parent.following = false
            let point = gesture.location(in: map)
            let hit = map.annotations.compactMap { $0 as? Pin }.filter { parent.showWaypoints && $0.kind == "waypoint" }.first { pin in
                guard let view = map.view(for: pin) else { return false }
                return view.bounds.insetBy(dx: -8, dy: -8).contains(view.convert(point, from: map))
            }
            if let id = hit?.id, let waypoint = parent.waypoints.first(where: { $0.id == id }) { parent.editWaypoint(waypoint) }
            else { parent.createWaypoint(map.convert(point, toCoordinateFrom: map)) }
        }
        func render(_ map: MKMapView) {
            guard !rendering else { return }
            rendering = true
            defer { rendering = false }
            self.map = map
            let p = parent
            if let previousScale, previousScale != p.metersPerCm, !p.following {
                let camera = map.camera.copy() as! MKMapCamera
                camera.altitude *= p.metersPerCm / previousScale
                map.setCamera(camera, animated: false)
            }
            previousScale = p.metersPerCm
            if p.following != wasFollowing { scaleSignature = ""; wasFollowing = p.following }
            let librarySignature = (try? JSONEncoder().encode(p.library)).map { String(decoding:$0,as:UTF8.self) } ?? ""
            let key = "\(librarySignature)|\(p.waypoints.map{$0.group ?? ""}.joined())|\(p.selected?.uuidString ?? "")|\(p.waypoints.map { "\($0.id)|\($0.name)|\($0.latitude)|\($0.longitude)|\($0.colorName ?? "orange")|\($0.markSymbol ?? "flag.fill")|\($0.markText ?? "")" }.joined())|\(p.showWaypoints)|\(p.showCourse)"
            let staticChanged = key != signature
            if staticChanged {
                signature = key
                courseHeading = nil
                map.removeAnnotations(map.annotations.compactMap { $0 as? Pin }.filter { $0.kind == "waypoint" })
                map.removeOverlays(map.overlays.filter { (($0 as? MKPolyline)?.title ?? ($0 as? MKPolygon)?.title ?? "").hasPrefix("feature:") })
                for wp in p.showWaypoints ? p.waypoints : [] {
                    let pin = Pin(); pin.id = wp.id; pin.title = wp.name; pin.coordinate = wp.coordinate; pin.colorName = wp.colorName; pin.markSymbol = wp.markSymbol; pin.markText = wp.markText
                    map.addAnnotation(pin)
                }
                for f in p.library.features where f.visible && !p.library.hiddenGroups.contains(f.group) {
                    let points = f.boundary(p.waypoints.map(\.archiveEntry)).map{CLLocationCoordinate2D(latitude:$0.latitude,longitude:$0.longitude)}
                    guard points.count >= 2 else { continue }
                    if f.kind == "line" { let line=MKPolyline(coordinates:points,count:points.count);line.title="feature:"+f.color;map.addOverlay(line) }
                    else { let area=MKPolygon(coordinates:points,count:points.count);area.title="feature:"+f.color;map.addOverlay(area) }
                }
            }
            let locationChanged = lastLocationTime != p.location?.timestamp
            if locationChanged || lastTrackCount != p.track.count {
                lastLocationTime = p.location?.timestamp
                lastTrackCount = p.track.count
                map.removeOverlays(map.overlays.filter { ($0 as? MKPolyline)?.title == "track" || ($0 as? MKPolyline)?.title == "target" })
                if p.track.count > 1 {
                    let line = MKPolyline(coordinates: p.track, count: p.track.count)
                    line.title = "track"; map.addOverlay(line)
                }
            }
            if let location = p.location {
                if let pin = map.annotations.compactMap({ $0 as? Pin }).first(where: { $0.kind == "boat" }) { pin.coordinate = location.coordinate }
                else { let pin = Pin(); pin.kind = "boat"; pin.title = "現在地"; pin.coordinate = location.coordinate; map.addAnnotation(pin) }
            }
            if locationChanged || staticChanged {
                // Refresh the target path without replacing waypoint annotation views.
                map.removeOverlays(map.overlays.filter { ($0 as? MKPolyline)?.title == "target" })
                if let location = p.location, let target = p.waypoints.first(where: { $0.id == p.selected }) {
                    let line = MKPolyline(coordinates: [location.coordinate, target.coordinate], count: 2)
                    line.title = "target"; map.addOverlay(line)
                }
            }
            if staticChanged || locationChanged || courseHeading != p.heading || (p.showCourse && !map.overlays.contains(where: { ($0 as? MKPolyline)?.title == "course" })) {
                updateCourse(map)
            }
            updateBoatRotation(map)
            if !didInitialWaypointFit && p.showWaypoints && !p.waypoints.isEmpty {
                let pins = map.annotations.compactMap { $0 as? Pin }.filter { $0.kind != "course" }
                if !pins.isEmpty {
                    didInitialWaypointFit = true
                    map.showAnnotations(pins, animated: false)
                }
            }
            if lastShowAll != p.showAllRequest {
                lastShowAll = p.showAllRequest
                let pins = map.annotations.compactMap { $0 as? Pin }.filter { $0.kind != "course" }
                if !pins.isEmpty { map.showAnnotations(pins, animated: false) }
            } else if p.following {
                if shownHeading == nil { shownHeading = p.heading }
                applyCamera(map)
                if p.heading != nil { startAnimation() }
            } else { stopAnimation() }
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            var interacting = false
            for child in mapView.subviews {
                for gesture in child.gestureRecognizers ?? [] {
                    if gesture.state == UIGestureRecognizer.State.began || gesture.state == UIGestureRecognizer.State.changed { interacting = true }
                }
            }
            if interacting && parent.following { DispatchQueue.main.async { self.parent.following = false } }
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let area = overlay as? MKPolygon {
                let renderer=MKPolygonRenderer(polygon:area);let color=UIColor(waypointColor(area.title?.replacingOccurrences(of:"feature:",with:"") ?? "#00AAFF"));renderer.strokeColor=color;renderer.fillColor=color.withAlphaComponent(0.25);renderer.lineWidth=3;return renderer
            }
            if let line = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = line.title?.hasPrefix("feature:")==true ? UIColor(waypointColor(String(line.title!.dropFirst(8)))) : line.title == "target" ? .green : line.title == "course" ? .black : .orange
                renderer.lineWidth = line.title == "course" ? 2 : 3
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? Pin else { return nil }
            if pin.kind == "boat" {
                let view = MKAnnotationView(annotation: pin, reuseIdentifier: nil)
                view.image = UIImage(systemName: "location.north.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .bold))?.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
                view.transform = CGAffineTransform(rotationAngle: ((parent.heading ?? 0) - mapView.camera.heading) * .pi / 180)
                view.displayPriority = .required; view.canShowCallout = true
                return view
            }
            if pin.kind == "course" {
                let view = MKAnnotationView(annotation: pin, reuseIdentifier: nil)
                view.frame = CGRect(x: 0, y: 0, width: 8, height: 8)
                view.backgroundColor = .black; view.layer.cornerRadius = 4; view.canShowCallout = true
                view.layer.borderColor = UIColor.white.cgColor; view.layer.borderWidth = 1
                view.displayPriority = .required; view.collisionMode = .circle
                return view
            }
            let view = MKAnnotationView(annotation:pin,reuseIdentifier:nil)
            view.image=CompactWaypointMarker.image(name:pin.title ?? "",color:UIColor(waypointColor(pin.colorName)),markText:pin.markText,markSymbol:pin.markSymbol)
            view.centerOffset=CGPoint(x:0,y:-19)
            view.displayPriority = .required;view.collisionMode = .rectangle
            view.canShowCallout=false;view.isEnabled=false
            view.accessibilityLabel=pin.title
            return view
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if (view.annotation as? Pin)?.kind == "waypoint" { mapView.deselectAnnotation(view.annotation, animated: false) }
        }
    }
}


/// A fixed-size image prevents MapKit from resetting native marker transforms.
/// Every point keeps its name; selected and ordinary points share the same dimensions.
enum CompactWaypointMarker {
    static func image(name:String,color:UIColor,markText:String?,markSymbol:String?)->UIImage {
        let font=UIFont.systemFont(ofSize:9,weight:.medium)
        let attrs:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:UIColor.white,.strokeColor:UIColor.black.withAlphaComponent(0.85),.strokeWidth:-2]
        let labelSize=(name as NSString).size(withAttributes:attrs)
        let width=ceil(max(22,labelSize.width+8));let height:CGFloat=38
        return UIGraphicsImageRenderer(size:CGSize(width:width,height:height)).image { _ in
            (name as NSString).draw(at:CGPoint(x:(width-labelSize.width)/2,y:0),withAttributes:attrs)
            let x=width/2
            color.setFill()
            let tail=UIBezierPath();tail.move(to:CGPoint(x:x-6,y:27));tail.addLine(to:CGPoint(x:x,y:38));tail.addLine(to:CGPoint(x:x+6,y:27));tail.close();tail.fill()
            UIBezierPath(ovalIn:CGRect(x:x-9,y:14,width:18,height:18)).fill()
            if let text=markText,!text.isEmpty {
                let glyph:[NSAttributedString.Key:Any]=[.font:UIFont.systemFont(ofSize:10,weight:.semibold),.foregroundColor:UIColor.white]
                let size=(text as NSString).size(withAttributes:glyph)
                (text as NSString).draw(at:CGPoint(x:x-size.width/2,y:23-size.height/2),withAttributes:glyph)
            } else {
                MarineMarks.image(markSymbol ?? "flag.fill").withTintColor(.white,renderingMode:.alwaysOriginal).draw(in:CGRect(x:x-5,y:18,width:10,height:10))
            }
        }
    }
}
