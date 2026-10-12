import SwiftUI
import MapKit

/// Map projection and course marks are display-only; they never enter the recorded track.
struct NavigationMapView: UIViewRepresentable {
    let location: CLLocation?
    let heading: Double?
    let waypoints: [Waypoint]
    let track: [CLLocationCoordinate2D]
    @Binding var selected: UUID?
    @Binding var following: Bool
    let showAllRequest: Int
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
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NavigationMapView
        var lastShowAll = 0
        private var rendering = false
        private var signature = ""
        private var courseHeading: Double?
        private weak var map: MKMapView?
        private var displayLink: CADisplayLink?
        private var shownHeading: Double?
        private var frameTime: CFTimeInterval = 0
        private var scaleSignature = ""
        private var wasFollowing = false
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
            camera.centerCoordinate = point.coordinate
            camera.heading = CoordinateInput.normalizeHeading(shownHeading ?? parent.heading ?? 0)
            camera.pitch = 0
            map.setCamera(camera, animated: false)
            // Recalibrate scale for layout/location changes, not for every compass sample.
            let key = "\(map.bounds.size)|\(point.coordinate.latitude)"
            if key != scaleSignature {
                scaleSignature = key
                let pointsPerCm = (UIDevice.current.userInterfaceIdiom == .pad ? 132.0 : 163.0) / 2.54
                let desiredMetersPerPoint = 200 / pointsPerCm
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
            map.removeAnnotations(map.annotations.compactMap { $0 as? Pin }.filter { $0.kind == "course" })
            map.removeOverlays(map.overlays.filter { ($0 as? MKPolyline)?.title == "course" })
            courseHeading = parent.heading
            guard let location = parent.location, let heading = parent.heading else { return }
            var coordinates = [location.coordinate]
            for distance in stride(from: 100, through: 500, by: 100) {
                let q = CoordinateInput.destination(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, bearing: heading, meters: Double(distance))
                let coordinate = CLLocationCoordinate2D(latitude: q.latitude, longitude: q.longitude)
                coordinates.append(coordinate)
                let dot = Pin(); dot.kind = "course"; dot.title = "\(distance) m"; dot.coordinate = coordinate
                map.addAnnotation(dot)
            }
            let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
            line.title = "course"; map.addOverlay(line)
        }
        init(_ parent: NavigationMapView) { self.parent = parent }

        @objc func longPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map = gesture.view as? MKMapView else { return }
            parent.following = false
            parent.createWaypoint(map.convert(gesture.location(in: map), toCoordinateFrom: map))
        }
        func render(_ map: MKMapView) {
            guard !rendering else { return }
            rendering = true
            defer { rendering = false }
            self.map = map
            let p = parent
            if p.following != wasFollowing { scaleSignature = ""; wasFollowing = p.following }
            let key = "\(p.location?.timestamp.timeIntervalSince1970 ?? 0)|\(p.selected?.uuidString ?? "")|\(p.waypoints.map { "\($0.id)|\($0.name)|\($0.latitude)|\($0.longitude)|\($0.colorName ?? "orange")" }.joined())|\(p.track.count)"
            if key != signature {
                signature = key
                courseHeading = nil
                map.removeAnnotations(map.annotations)
                map.removeOverlays(map.overlays)
                for wp in p.waypoints {
                    let pin = Pin(); pin.id = wp.id; pin.title = wp.name; pin.coordinate = wp.coordinate; pin.colorName = wp.colorName
                    map.addAnnotation(pin)
                }
                if p.track.count > 1 { map.addOverlay(MKPolyline(coordinates: p.track, count: p.track.count)) }
                if let location = p.location {
                    let pin = Pin(); pin.kind = "boat"; pin.title = "現在地"; pin.coordinate = location.coordinate
                    map.addAnnotation(pin)
                    if let target = p.waypoints.first(where: { $0.id == p.selected }) {
                        let line = MKPolyline(coordinates: [location.coordinate, target.coordinate], count: 2)
                        line.title = "target"; map.addOverlay(line)
                    }

                }
            }
            if key != signature || courseHeading != p.heading || !map.overlays.contains(where: { ($0 as? MKPolyline)?.title == "course" }) {
                updateCourse(map)
            }
            updateBoatRotation(map)
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
            if let line = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = line.title == "target" ? .green : line.title == "course" ? .black : .orange
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
            let view = MKMarkerAnnotationView(annotation: pin, reuseIdentifier: nil)
            view.markerTintColor = UIColor(waypointColor(pin.colorName))
            view.glyphImage = UIImage(systemName: pin.kind == "boat" ? "location.north.fill" : "flag.fill")
            view.displayPriority = .required
            view.titleVisibility = .visible
            view.canShowCallout = true
            return view
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let id = (view.annotation as? Pin)?.id { parent.selected = id }
        }
    }
}
